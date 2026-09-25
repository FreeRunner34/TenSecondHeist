import Foundation
import StoreKit

@MainActor final class PurchaseManager: ObservableObject {
    static let campaignID = "com.revpointstudios.tensecondheist.campaign"
    static let fiveTokenID = "com.revpointstudios.tensecondheist.help5"
    static let twelveTokenID = "com.revpointstudios.tensecondheist.help12"

    // An atomic cross-device wallet needs a recovery service. Paid tokens stay disabled until one exists.
    static let paidTokensEnabled = false

    @Published private(set) var campaignUnlocked = false
    @Published private(set) var campaignProduct: Product?
    @Published private(set) var message: String?
    @Published private(set) var busy = false
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.process(result)
            }
        }
        Task { await load() }
    }

    deinit { updatesTask?.cancel() }

    func load() async {
        do {
            campaignProduct = try await Product.products(for: [Self.campaignID]).first
            if campaignProduct == nil { message = "Campaign purchase is not configured in this store." }
        } catch { message = "Store unavailable: \(error.localizedDescription)" }
        await refreshEntitlement()
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

    func restore() async {
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            message = campaignUnlocked ? "Full Campaign restored." : "No Full Campaign purchase was found for this Apple Account."
        } catch { message = "Restore failed: \(error.localizedDescription)" }
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
            } else {
                // No paid token product is sold. Keep unexpected consumables unfinished for recovery.
                message = "An unsupported purchase needs assistance. Contact support from Settings."
            }
        }
    }
}
