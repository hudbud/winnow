import StoreKit
import SwiftUI

struct UnlockView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var entitlements = EntitlementStore.shared
    @State private var showFeedbackForm = false
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.yellow)
                        Text("Go Beyond ★3")
                            .font(.title2.weight(.bold))
                        Text("The free version sorts up to ★\(EntitlementStore.freeStarCap). Unlock ★4 and ★5 to fully refine your picks.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    purchaseSection

                    HStack {
                        Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                        Text("or").font(.caption).foregroundStyle(.secondary)
                        Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                    }

                    freeUnlockSection
                }
                .padding(20)
            }
            .navigationTitle("Unlock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await entitlements.loadProduct() }
        .sheet(isPresented: $showFeedbackForm) {
            FeedbackFormView()
        }
        .onChange(of: entitlements.isUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: 10) {
            if let product = entitlements.product {
                Button {
                    isPurchasing = true
                    Task {
                        await entitlements.purchase()
                        isPurchasing = false
                    }
                } label: {
                    Group {
                        if isPurchasing {
                            ProgressView()
                        } else {
                            Text("Unlock for \(product.displayPrice)")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPurchasing)
            } else if entitlements.isLoadingProduct {
                ProgressView()
            } else {
                Text("Purchase unavailable right now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Restore Purchase") {
                Task { await entitlements.restorePurchases() }
            }
            .font(.footnote)

            if let error = entitlements.purchaseError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var freeUnlockSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unlock it for free")
                .font(.headline)
            Text("Complete both of these:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            checklistRow(
                done: entitlements.feedbackSubmitted,
                title: "Send feedback",
                subtitle: "Tell me what's working or what's not."
            ) {
                showFeedbackForm = true
            }

            VStack(alignment: .leading, spacing: 8) {
                checklistRow(
                    done: entitlements.reviewAcknowledged,
                    title: "Leave an App Store review",
                    subtitle: "Every review genuinely helps."
                ) {
                    requestReview()
                }

                if !entitlements.reviewAcknowledged {
                    Button("I left a review") {
                        entitlements.reviewAcknowledged = true
                    }
                    .font(.footnote)
                    .padding(.leading, 40)
                }
            }
        }
    }

    private func checklistRow(done: Bool, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? .green : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !done {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .disabled(done)
        .buttonStyle(.plain)
    }
}
