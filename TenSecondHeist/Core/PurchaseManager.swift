import Foundation
import StoreKit

@MainActor final class PurchaseManager: ObservableObject {
    static let campaignID = "com.revpointstudios.tensecondheist.campaign"
    static let fiveTokenID = "com.revpointstudios.tensecondheist.help5"
    static let twelveTokenID = "com.revpointstudios.tensecondheist.help12"

    @Published private(set) var campaignUnlocked = false
    @Published private(set) var campaignProduct: Product?
    @Published private(set) var tokenProducts: [String: Product] = [:]
    @Published private(set) var paidBalance = 0
    @Published private(set) var walletReady = false
    @Published private(set) var message: String?
    @Published private(set) var busy = false
    private let wallet = PaidTokenWallet()
    private weak var progress: ProgressStore?
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates { await self?.process(result) }
        }
    }

    deinit { updatesTask?.cancel() }

    func start(progress: ProgressStore) async {
        self.progress = progress
        await load()
        // A purchase is finished only after the iCloud credit commits. Recover
        // transactions interrupted between Apple's charge and that commit.
        for await result in Transaction.unfinished { await process(result) }
        // Finished consumables are not replayed as credits. Revoked purchases
        // may still be reported in history and must be removed from the ledger.
        for await result in Transaction.all {
            if case .verified(let transaction) = result,
               tokenCount(for: transaction.productID) != nil,
               transaction.revocationDate != nil { await process(result) }
        }
    }

    func load() async {
        do {
            let products = try await Product.products(for: [Self.campaignID, Self.fiveTokenID, Self.twelveTokenID])
            campaignProduct = products.first { $0.id == Self.campaignID }
            tokenProducts = Dictionary(uniqueKeysWithValues: products.filter {
                $0.id == Self.fiveTokenID || $0.id == Self.twelveTokenID
            }.map { ($0.id, $0) })
            if campaignProduct == nil { message = "Campaign purchase is not configured in this store." }
        } catch { message = "Store unavailable: \(error.localizedDescription)" }
        await refreshEntitlement()
        await refreshWallet()
    }

    func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.campaignID, transaction.revocationDate == nil {
                entitled = true
            }
        }
        campaignUnlocked = entitled
    }

    func refreshWallet() async {
        do {
            let state = try await wallet.refresh()
            guard apply(state) else { walletReady = false; return }
            walletReady = true
        } catch {
            walletReady = false
            message = error.localizedDescription
        }
    }

    func buyCampaign() async {
        guard let campaignProduct, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            switch try await campaignProduct.purchase() {
            case .success(let result): await process(result)
            case .pending: message = "Purchase pending approval. The campaign will unlock when approved."
            case .userCancelled: message = "Purchase cancelled."
            @unknown default: message = "The store returned an unknown result."
            }
        } catch { message = "Purchase failed: \(error.localizedDescription)" }
    }

    func buyTokens(_ productID: String) async {
        guard let product = tokenProducts[productID], !busy, walletReady else { return }
        busy = true
        defer { busy = false }
        do {
            // Refuse to start a paid transaction if the recovery ledger cannot
            // currently be reached. An outage after purchase leaves it unfinished.
            guard apply(try await wallet.refresh()) else { return }
            switch try await product.purchase() {
            case .success(let result): await process(result)
            case .pending: message = "Token purchase pending approval. No tokens have been added yet."
            case .userCancelled: message = "Token purchase cancelled."
            @unknown default: message = "The store returned an unknown result."
            }
        } catch {
            walletReady = false
            message = "Token purchase unavailable: \(error.localizedDescription)"
        }
    }

    @discardableResult func activatePaid(_ mode: AssistMode, level: LevelDefinition) async -> Bool {
        guard walletReady, !busy, let progress else { return false }
        busy = true
        defer { busy = false }
        do {
            let state = try await wallet.spend(levelID: level.id, mode: mode)
            guard apply(state) else { return false }
            guard progress.activate(mode, level: level) else {
                message = "Help was saved to iCloud, but local progress could not be saved. Reopen the level after fixing the save error."
                return false
            }
            message = nil
            return true
        } catch {
            message = "Help was not spent: \(error.localizedDescription)"
            await refreshWallet()
            return false
        }
    }

    func restore() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            await refreshWallet()
            if walletReady {
                message = campaignUnlocked ? "Full Campaign restored. Paid Inside Help synced from iCloud."
                    : "No Full Campaign purchase was found. Paid Inside Help synced from iCloud."
            }
        } catch { message = "Restore failed: \(error.localizedDescription)" }
    }

    @discardableResult private func apply(_ state: PaidWalletState) -> Bool {
        paidBalance = state.balance
        if let progress, !progress.mergePaidUnlocks(state.unlocks) {
            message = "Paid help is safe in iCloud, but local progress could not be saved."
            return false
        }
        return true
    }

    private func process(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .unverified(_, let error):
            message = "Purchase could not be verified: \(error.localizedDescription)"
        case .verified(let transaction):
            if transaction.productID == Self.campaignID {
                await refreshEntitlement()
                if transaction.revocationDate == nil {
                    campaignUnlocked = true
                    message = "Full Campaign unlocked."
                } else { message = "Full Campaign purchase was revoked." }
                await transaction.finish()
            } else if let count = tokenCount(for: transaction.productID) {
                guard progress != nil else { return } // Startup will scan unfinished transactions.
                do {
                    let state: PaidWalletState
                    if transaction.revocationDate != nil {
                        state = try await wallet.revoke(transactionID: transaction.id)
                    } else {
                        state = try await wallet.credit(transactionID: transaction.id,
                            count: count * max(1, transaction.purchasedQuantity))
                    }
                    guard apply(state) else { return }
                    walletReady = true
                    message = transaction.revocationDate == nil ? "Paid Inside Help tokens added to your iCloud wallet."
                        : "A refunded token purchase was removed from your balance."
                    await transaction.finish()
                } catch {
                    walletReady = false
                    message = "Apple recorded the purchase, but iCloud delivery is pending. Reconnect to the same iCloud account; the transaction remains unfinished. \(error.localizedDescription)"
                }
            }
        }
    }

    private func tokenCount(for productID: String) -> Int? {
        switch productID {
        case Self.fiveTokenID: 5
        case Self.twelveTokenID: 12
        default: nil
        }
    }
}
