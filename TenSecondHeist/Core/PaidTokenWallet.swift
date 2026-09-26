import CloudKit
import Foundation

// The paid wallet lives in one record in the player's private iCloud database. Every
// credit or spend reads the current change tag and saves conditionally, so two
// devices cannot spend the same token. Introductory tokens remain local and free.
struct PaidWalletState: Codable, Equatable {
    var version = 1
    var credits: [String: Int] = [:]
    var revoked: Set<String> = []
    var unlocks: Set<String> = []

    var balance: Int { max(0, credits.values.reduce(0, +) - unlocks.count) }

    static func key(levelID: String, mode: AssistMode) -> String {
        switch mode {
        case .tip: "\(levelID)::tip"
        case .loop(let camera): "\(levelID)::loop:\(camera)"
        }
    }

    mutating func credit(transactionID: UInt64, count: Int) {
        let id = String(transactionID)
        guard count > 0, !revoked.contains(id), credits[id] == nil else { return }
        credits[id] = count
    }

    mutating func revoke(transactionID: UInt64) {
        let id = String(transactionID)
        credits.removeValue(forKey: id)
        revoked.insert(id)
    }

    @discardableResult mutating func spend(levelID: String, mode: AssistMode) -> Bool {
        let identifier = Self.key(levelID: levelID, mode: mode)
        if unlocks.contains(identifier) { return true }
        guard balance > 0 else { return false }
        unlocks.insert(identifier)
        return true
    }
}

enum PaidWalletError: LocalizedError {
    case unavailable, noTokens, conflict, corrupt, missingResult
    var errorDescription: String? {
        switch self {
        case .unavailable: "Paid Inside Help requires an available iCloud account and connection. Free retries still work offline."
        case .noTokens: "No paid Inside Help tokens remain."
        case .conflict: "Your token balance changed on another device. Refresh it and try again."
        case .corrupt: "The iCloud token record could not be read. Contact support before making another purchase."
        case .missingResult: "iCloud did not confirm the token update. Refresh the balance before trying again."
        }
    }
}

@MainActor final class PaidTokenWallet {
    private let container = CKContainer(identifier: "iCloud.com.revpointstudios.tensecondheist")
    private let recordID = CKRecord.ID(recordName: "paid-wallet-v1")
    private var database: CKDatabase { container.privateCloudDatabase }

    func refresh() async throws -> PaidWalletState {
        guard try await container.accountStatus() == .available else { throw PaidWalletError.unavailable }
        return try await fetch().state
    }

    func credit(transactionID: UInt64, count: Int) async throws -> PaidWalletState {
        try await modify { $0.credit(transactionID: transactionID, count: count) }
    }

    func revoke(transactionID: UInt64) async throws -> PaidWalletState {
        try await modify { $0.revoke(transactionID: transactionID) }
    }

    func spend(levelID: String, mode: AssistMode) async throws -> PaidWalletState {
        try await modify { state in
            guard state.spend(levelID: levelID, mode: mode) else { throw PaidWalletError.noTokens }
        }
    }

    private func fetch() async throws -> (record: CKRecord?, state: PaidWalletState) {
        do {
            let record = try await database.record(for: recordID)
            guard let data = record["payload"] as? Data else { throw PaidWalletError.corrupt }
            let state = try JSONDecoder().decode(PaidWalletState.self, from: data)
            guard state.version == 1 else { throw PaidWalletError.corrupt }
            return (record, state)
        } catch let error as CKError where error.code == .unknownItem {
            return (nil, PaidWalletState())
        }
    }

    private func modify(_ change: (inout PaidWalletState) throws -> Void) async throws -> PaidWalletState {
        guard try await container.accountStatus() == .available else { throw PaidWalletError.unavailable }
        for _ in 0..<6 {
            let (existing, old) = try await fetch()
            var updated = old
            try change(&updated)
            if updated == old { return old }
            let record = existing ?? CKRecord(recordType: "PaidWallet", recordID: recordID)
            record["payload"] = try JSONEncoder().encode(updated) as NSData
            do {
                let response = try await database.modifyRecords(saving: [record], deleting: [],
                    savePolicy: .ifServerRecordUnchanged, atomically: true)
                guard let result = response.saveResults[recordID] else { throw PaidWalletError.missingResult }
                switch result {
                case .success: return updated
                case .failure(let error):
                    if isConflict(error) { continue }
                    throw error
                }
            } catch {
                if isConflict(error) { continue }
                throw error
            }
        }
        throw PaidWalletError.conflict
    }

    private func isConflict(_ error: Error) -> Bool {
        guard let cloud = error as? CKError else { return false }
        if cloud.code == .serverRecordChanged { return true }
        if cloud.code == .partialFailure {
            return cloud.partialErrorsByItemID?.values.contains {
                ($0 as? CKError)?.code == .serverRecordChanged
            } ?? false
        }
        return false
    }
}
