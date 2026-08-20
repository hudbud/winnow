import Foundation
import StoreKit

/// Tracks whether ★4/★5 sorting is unlocked, via either path:
/// - a one-time StoreKit purchase, or
/// - both soft-asks completed (feedback sent + review self-confirmed).
///
/// The review step can't actually be verified — Apple provides no API for that, and
/// guideline 3.1.1 forbids gating functionality behind a required rating/review — so
/// this is a self-reported honor-system checkbox after showing the native prompt,
/// never a hard requirement on its own.
@Observable
@MainActor
final class EntitlementStore {
    static let shared = EntitlementStore()

    static let unlockProductID = "com.hudsonpaine.ImageSort.unlockExtendedRatings"
    /// Highest star rating reachable without unlocking.
    static let freeStarCap = 3

    private(set) var hasPurchasedUnlock = false

    var feedbackSubmitted: Bool {
        didSet { UserDefaults.standard.set(feedbackSubmitted, forKey: Keys.feedbackSubmitted) }
    }
    var reviewAcknowledged: Bool {
        didSet { UserDefaults.standard.set(reviewAcknowledged, forKey: Keys.reviewAcknowledged) }
    }

    private(set) var product: Product?
    private(set) var isLoadingProduct = false
    private(set) var purchaseError: String?

    private var transactionListenerTask: Task<Void, Never>?

    private enum Keys {
        static let feedbackSubmitted = "entitlement.feedbackSubmitted"
        static let reviewAcknowledged = "entitlement.reviewAcknowledged"
    }

    var isUnlocked: Bool {
        hasPurchasedUnlock || (feedbackSubmitted && reviewAcknowledged)
    }

    private init() {
        feedbackSubmitted = UserDefaults.standard.bool(forKey: Keys.feedbackSubmitted)
        reviewAcknowledged = UserDefaults.standard.bool(forKey: Keys.reviewAcknowledged)

        transactionListenerTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { [weak self] in await self?.refreshEntitlements() }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    func loadProduct() async {
        guard product == nil else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            let products = try await Product.products(for: [Self.unlockProductID])
            product = products.first
        } catch {
            purchaseError = "Couldn't load product: \(error.localizedDescription)"
        }
    }

    func purchase() async {
        guard let product else { return }
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            await handle(result)
        }
    }

    private func handle(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else { return }
        if transaction.productID == Self.unlockProductID {
            hasPurchasedUnlock = true
        }
        await transaction.finish()
    }
}
