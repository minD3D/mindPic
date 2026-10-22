import Photos
import SwiftUI

// MARK: - 정사각형 썸네일 (휴지통, 비슷한 사진)
struct PhotoThumbnailView: View {
    let asset: PHAsset
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    AppTheme.surfaceMuted
                    ProgressView()
                        .tint(AppTheme.accentDark)
                }
            }
            .clipped()
            .onAppear { loadThumbnail(containerSize: geo.size) }
            .onDisappear { cancelRequest() }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func loadThumbnail(containerSize: CGSize) {
        guard image == nil else { return }
        let targetSize = CGSize(width: containerSize.width * displayScale,
                                height: containerSize.height * displayScale)

        let opt = PHImageRequestOptions()
        opt.isNetworkAccessAllowed = true
        opt.deliveryMode = .opportunistic
        opt.resizeMode = .fast

        requestID = sharedImageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: opt
        ) { img, _ in
            if let img = img { image = img }
        }
    }

    private func cancelRequest() {
        if let id = requestID { sharedImageManager.cancelImageRequest(id) }
        requestID = nil
    }
}
