import Photos
import SwiftData
import SwiftUI

private enum DeckTheme {
    case dark, light

    var background: Color { self == .dark ? .black : .white }
    var foreground: Color { self == .dark ? .white : .black }
    var cardBackground: Color { self == .dark ? Color(white: 0.12) : Color(white: 0.92) }
    var icon: String { self == .dark ? "moon.fill" : "sun.max.fill" }

    mutating func toggle() {
        self = self == .dark ? .light : .dark
    }
}

struct SwipeDeckView: View {
    @Environment(\.modelContext) private var context
    @State private var viewModel: SwipeDeckViewModel

    @State private var dragOffset: CGSize = .zero
    @State private var showReview = false
    @State private var theme: DeckTheme = .dark
    @State private var autoplayLivePhotos = true
    @State private var showRatingPicker = false
    @State private var showUnlock = false
    @State private var entitlements = EntitlementStore.shared

    private let library = PhotoLibraryService.shared
    private let swipeThreshold: CGFloat = 120

    init(session: Session, allAssets: [PHAsset], context: ModelContext) {
        _viewModel = State(initialValue: SwipeDeckViewModel(session: session, allAssets: allAssets, library: .shared, context: context))
    }

    var body: some View {
        VStack(spacing: 16) {
            header

            ZStack {
                // Stable per-asset identity, ordered back-to-front, so a card never
                // inherits another photo's in-flight drag state — the next card is
                // always already sitting in place underneath, just revealed.
                ForEach(Array(stackAssets.enumerated().reversed()), id: \.element.localIdentifier) { position, asset in
                    cardView(for: asset, position: position)
                }
            }
            .padding(.horizontal, 20)

            controls
        }
        .padding(.bottom, 20)
        .background(theme.background.ignoresSafeArea())
        .background(SwipeBackGestureDisabler())
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    viewModel.undoLastSwipe()
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .disabled(!viewModel.canUndo)
                .opacity(viewModel.canUndo ? 1 : 0.3)
                .foregroundStyle(theme.foreground)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 18) {
                    Button {
                        autoplayLivePhotos.toggle()
                    } label: {
                        Image(systemName: autoplayLivePhotos ? "livephoto" : "livephoto.slash")
                    }

                    Button {
                        theme.toggle()
                    } label: {
                        Image(systemName: theme.icon)
                    }
                }
                .foregroundStyle(theme.foreground)
            }
        }
        .sheet(isPresented: $showUnlock) {
            UnlockView()
        }
        .onChange(of: viewModel.isPassComplete) { _, complete in
            if complete { showReview = true }
        }
        .onAppear {
            // Resuming a session where the pass was already finished (e.g. the app
            // was killed before the review screen navigation happened) — onChange
            // alone won't fire since isPassComplete hasn't *changed* since mount.
            if viewModel.isPassComplete { showReview = true }
        }
        .navigationDestination(isPresented: $showReview) {
            EndOfPassReviewView(viewModel: viewModel, context: context)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("Pass \(viewModel.pass) → \(viewModel.pass + 1)")
                .font(.headline)
                .foregroundStyle(theme.foreground)

            if let topAsset = viewModel.topAsset {
                RatingBadge(storedRating: viewModel.storedRating(topAsset.localIdentifier), pass: viewModel.pass)
                    .contentShape(Rectangle())
                    .onTapGesture { showRatingPicker = true }
                    .popover(isPresented: $showRatingPicker) {
                        ratingPicker(for: topAsset)
                            .presentationCompactAdaptation(.popover)
                    }
            }

            ProgressView(value: progressValue)
                .tint(theme.foreground)
                .padding(.horizontal, 20)
        }
        .padding(.top, 8)
    }

    private func ratingPicker(for asset: PHAsset) -> some View {
        HStack(spacing: 16) {
            Button("None") {
                setManualRating(0, on: asset)
                showRatingPicker = false
            }
            .font(.subheadline.weight(.semibold))

            ForEach(1...5, id: \.self) { star in
                starIcon(star, for: asset)
            }
        }
        .padding(20)
    }

    private func starIcon(_ star: Int, for asset: PHAsset) -> some View {
        let isLocked = star > EntitlementStore.freeStarCap && !entitlements.isUnlocked
        let isFilled = star <= (viewModel.storedRating(asset.localIdentifier) ?? 0)
        let symbolName: String = isLocked ? "lock.fill" : (isFilled ? "star.fill" : "star")
        let color: Color = isLocked ? .secondary : (isFilled ? .yellow : .secondary)
        return Image(systemName: symbolName)
            .font(.title3)
            .foregroundStyle(color)
            .onTapGesture {
                if isLocked {
                    showRatingPicker = false
                    showUnlock = true
                } else {
                    setManualRating(star, on: asset)
                    showRatingPicker = false
                }
            }
    }

    private var progressValue: Double {
        guard viewModel.totalInPass > 0 else { return 1 }
        let done = viewModel.totalInPass - viewModel.remainingCount
        return Double(done) / Double(viewModel.totalInPass)
    }

    private var stackAssets: [PHAsset] {
        Array(viewModel.queue.prefix(3))
    }

    @ViewBuilder
    private func cardView(for asset: PHAsset, position: Int) -> some View {
        let isTop = position == 0
        let depth = min(position, 2)

        let scale: CGFloat = isTop ? 1 : 1 - CGFloat(depth) * 0.04
        let offsetX: CGFloat = isTop ? dragOffset.width : 0
        let offsetY: CGFloat = isTop ? dragOffset.height : CGFloat(depth) * 10
        let rotationDegrees: Double = isTop ? Double(dragOffset.width / 20) : 0

        let card = PhotoCardView(
            asset: asset,
            storedRating: viewModel.storedRating(asset.localIdentifier),
            pass: viewModel.pass,
            library: library,
            autoplayLivePhotos: autoplayLivePhotos,
            cardBackgroundColor: theme.cardBackground
        )
            .scaleEffect(scale)
            .offset(x: offsetX, y: offsetY)
            .rotationEffect(.degrees(rotationDegrees))

        if isTop {
            // No `.animation()` here, deliberately — the top card's offset/rotation
            // are driven live by `dragOffset` during the drag, and any implicit
            // animation on that value lags a beat behind the finger instead of
            // tracking it 1:1. The settle-back and fly-out cases already wrap
            // themselves in explicit `withAnimation` at their call sites.
            card
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .overlay(alignment: .topLeading) { stampOverlay(direction: .keep) }
                .overlay(alignment: .topTrailing) { stampOverlay(direction: .pass) }
                .gesture(dragGesture(for: asset))
        } else {
            card
                .animation(.easeOut(duration: 0.2), value: depth)
                .allowsHitTesting(false)
        }
    }

    private var controls: some View {
        HStack(spacing: 20) {
            navButton(systemName: "arrow.left", enabled: viewModel.canNavigateBack) {
                viewModel.navigateBack()
            }

            Spacer(minLength: 8)

            Button {
                withAnimation { commit(.pass) }
            } label: {
                Image(systemName: "xmark")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(.red.opacity(0.85), in: Circle())
            }
            .disabled(viewModel.topAsset == nil)

            Button {
                withAnimation { commit(.keep) }
            } label: {
                Image(systemName: "checkmark")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(.green.opacity(0.85), in: Circle())
            }
            .disabled(viewModel.topAsset == nil)

            Spacer(minLength: 8)

            navButton(systemName: "arrow.right", enabled: viewModel.remainingCount > 1) {
                viewModel.skip()
            }
        }
        .padding(.horizontal, 24)
    }

    /// Pure browsing — moves through the deck without deciding anything. Distinct
    /// from undo (top-left, in the toolbar), which reverts an actual decision.
    private func navButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.foreground)
                .frame(width: 46, height: 46)
                .background(theme.foreground.opacity(0.12), in: Circle())
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }

    private func stampOverlay(direction: SwipeDirection) -> some View {
        let isKeep = direction == .keep
        let progress = min(abs(isKeep ? max(dragOffset.width, 0) : min(dragOffset.width, 0)) / swipeThreshold, 1)
        return Text(isKeep ? "KEEP" : "PASS")
            .font(.title.weight(.heavy))
            .foregroundStyle(isKeep ? .green : .red)
            .padding(10)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isKeep ? .green : .red, lineWidth: 4))
            .rotationEffect(.degrees(isKeep ? -20 : 20))
            .opacity(progress)
            .padding(24)
    }

    private func dragGesture(for asset: PHAsset) -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                if value.translation.width > swipeThreshold {
                    commit(.keep)
                } else if value.translation.width < -swipeThreshold {
                    commit(.pass)
                } else {
                    withAnimation(.spring()) { dragOffset = .zero }
                }
            }
    }

    /// Set from the rating badge's picker — a direct override, distinct from a
    /// swipe, so it gets its own scale/fade transition rather than a fly-out.
    private func setManualRating(_ rating: Int, on asset: PHAsset) {
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        withAnimation(.easeOut(duration: 0.25)) {
            viewModel.setManualRating(rating, for: asset)
        }
    }

    private func commit(_ direction: SwipeDirection) {
        guard let asset = viewModel.topAsset else { return }
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()

        let flyOutDuration = 0.25
        let flyOut: CGFloat = direction == .keep ? 600 : -600
        withAnimation(.easeOut(duration: flyOutDuration)) {
            dragOffset = CGSize(width: flyOut, height: dragOffset.height)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + flyOutDuration) {
            viewModel.commit(direction, on: asset)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragOffset = .zero
            }
        }
    }
}
