import Photos
import SwiftUI

struct RootView: View {
    @State private var status: PHAuthorizationStatus = PhotoLibraryService.shared.currentAuthorizationStatus

    var body: some View {
        Group {
            switch status {
            case .authorized, .limited:
                AlbumPickerView()
            case .notDetermined:
                PermissionRequestView(status: $status)
            case .denied, .restricted:
                PermissionDeniedView()
            @unknown default:
                PermissionDeniedView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct PermissionRequestView: View {
    @Binding var status: PHAuthorizationStatus
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white)
            Text("ImageSort needs access to your photos")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Pick an album, then swipe through it in passes to find your best shots.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                isRequesting = true
                Task {
                    let newStatus = await PhotoLibraryService.shared.requestAuthorization()
                    await MainActor.run {
                        status = newStatus
                        isRequesting = false
                    }
                }
            } label: {
                if isRequesting {
                    ProgressView()
                } else {
                    Text("Allow Access")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
    }
}

private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
            Text("Photo Access Denied")
                .font(.title3.weight(.semibold))
            Text("Enable photo access in Settings to use ImageSort.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
    }
}
