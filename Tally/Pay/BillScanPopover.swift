import SwiftUI
import PhotosUI
import VisionKit

/// Compact liquid-glass capsule — same height as the tab bar.
struct BillScanPopover: View {
    @Bindable var viewModel: PayFlowViewModel
    let onDismiss: () -> Void
    let onScanComplete: () -> Void

    @State private var showScanner = false
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        HStack(spacing: TallySpacing.xl) {
            if viewModel.isScanning {
                ProgressView()
                    .tint(TallyColors.ink)
                    .frame(width: 50, height: 50)
            } else {
                // Camera
                Button { showScanner = true } label: {
                    Image(systemName: "camera.fill")
                        .font(TallyIcon.md)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(TallyColors.ink)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Photos
                PhotosPicker(
                    selection: $selectedPhoto,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Image(systemName: "photo.fill")
                        .font(TallyIcon.md)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(TallyColors.ink)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, TallySpacing.md)
        .padding(.vertical, TallySpacing.md)
        .glassEffect(.regular, in: Capsule())
        .sheet(isPresented: $showScanner) {
            DocumentScannerView(
                onScan: { images in
                    showScanner = false
                    if let first = images.first {
                        Task {
                            await viewModel.processReceiptImage(first)
                            if viewModel.receipt != nil { onScanComplete() }
                        }
                    }
                },
                onCancel: { showScanner = false }
            )
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let item = newValue else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await viewModel.processReceiptImage(image)
                    if viewModel.receipt != nil { onScanComplete() }
                }
                selectedPhoto = nil
            }
        }
    }
}
