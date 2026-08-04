import AVKit
import Photos
import PhotosUI
import SwiftUI

struct PhotoCardView: View {
    let asset: PHAsset
    let storedRating: Int?
    let pass: Int
    let library: PhotoLibraryService
    let autoplayLivePhotos: Bool
    let cardBackgroundColor: Color

    @State private var image: UIImage?
    @State private var livePhoto: PHLivePhoto?
    @State private var player: AVPlayer?

    @GestureState private var pinchState = PinchState()

    private struct PinchState {
        var scale: CGFloat = 1
        var anchor: UnitPoint = .center
    }

    private var isVideo: Bool { asset.mediaType == .video }
    private var isLivePhoto: Bool { asset.mediaSubtypes.contains(.photoLive) }

    /// `MagnifyGesture` (not the older `MagnificationGesture`) so we get `startAnchor`
    /// — where the pinch actually began — and can zoom around that point instead of
    /// always the view's center.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($pinchState) { value, state, _ in
                state = PinchState(scale: value.magnification, anchor: value.startAnchor)
            }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(cardBackgroundColor)

                mediaContent(size: geometry.size)

                if isLivePhoto && livePhoto == nil {
                    Image(systemName: "livephoto")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.35), in: Circle())
                        .padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            .onAppear { loadPrimaryContent(size: geometry.size) }
        }
    }

    @ViewBuilder
    private func mediaContent(size: CGSize) -> some View {
        if isVideo {
            videoContent(size: size)
        } else if isLivePhoto {
            livePhotoContent(size: size)
        } else {
            staticImage(size: size)
        }
    }

    @ViewBuilder
    private func staticImage(size: CGSize) -> some View {
        // Full image, uncropped — letterboxed against the card background
        // rather than filled, so nothing gets cut off.
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
                .scaleEffect(pinchState.scale, anchor: pinchState.anchor)
                .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.7), value: pinchState.scale)
                .simultaneousGesture(magnifyGesture)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            ProgressView()
                .tint(.white)
                .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private func livePhotoContent(size: CGSize) -> some View {
        if let livePhoto {
            LivePhotoRepresentable(livePhoto: livePhoto)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            ZStack {
                staticImage(size: size)
                if !autoplayLivePhotos {
                    Button {
                        Task { await loadLivePhoto() }
                    } label: {
                        Image(systemName: "livephoto.play")
                            .font(.system(size: 56))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 10)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func videoContent(size: CGSize) -> some View {
        if let player {
            VideoPlayer(player: player)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .onAppear { player.play() }
        } else {
            ZStack {
                staticImage(size: size)
                Button {
                    Task { await loadVideoPlayer() }
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 10)
                }
            }
        }
    }

    private func loadPrimaryContent(size: CGSize) {
        // Always load the static image — it's the video poster frame, the live-photo
        // poster before playback, and the placeholder while a live photo loads.
        // Uses the same fixed target size the view model prefetches at — requesting
        // anything else here would make every prefetched card a cache miss.
        library.loadImage(for: asset, targetSize: PhotoLibraryService.cardTargetSize) { loaded in
            image = loaded
        }
        if isLivePhoto && autoplayLivePhotos {
            Task { await loadLivePhoto() }
        }
    }

    private func loadLivePhoto() async {
        livePhoto = await library.loadLivePhoto(for: asset, targetSize: PhotoLibraryService.cardTargetSize)
    }

    private func loadVideoPlayer() async {
        if let item = await library.loadPlayerItem(for: asset) {
            player = AVPlayer(playerItem: item)
        }
    }
}

private struct LivePhotoRepresentable: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.livePhoto = livePhoto
        view.contentMode = .scaleAspectFit
        // We trigger playback ourselves; disabling interaction stops this view's own
        // built-in gesture recognizers from swallowing the swipe-to-rate drag gesture.
        view.isUserInteractionEnabled = false
        view.startPlayback(with: .full)
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        if uiView.livePhoto !== livePhoto {
            uiView.livePhoto = livePhoto
            uiView.startPlayback(with: .full)
        }
    }
}
