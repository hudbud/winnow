import SwiftUI

/// Shows a card's current rating. When the card's rating is already above the
/// active pass, it renders dimmed to signal "locked — this swipe is decorative."
struct RatingBadge: View {
    let storedRating: Int?
    let pass: Int

    private var isLocked: Bool {
        (storedRating ?? 0) > pass
    }

    var body: some View {
        Group {
            if let storedRating {
                Label("\(storedRating)", systemImage: "star.fill")
            } else {
                Image(systemName: "star")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isLocked ? .white.opacity(0.45) : .white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(isLocked ? 0.25 : 0.45), in: Capsule())
        .overlay(
            Capsule().stroke(.white.opacity(isLocked ? 0.15 : 0.3), lineWidth: 1)
        )
    }
}
