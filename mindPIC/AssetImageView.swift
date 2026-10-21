import SwiftUI
import Photos
import UIKit

// MARK: - 이미지 로더 (썸네일 + 고해상도)
struct AssetImageView: View {
    let asset: PHAsset
    @State private var thumbnailImage: UIImage?
    @State private var fullImage: UIImage?
    @State private var requestIDs: [PHImageRequestID] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = fullImage ?? thumbnailImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    AppTheme.card
                    ProgressView()
                        .tint(AppTheme.accentDark)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .onAppear { loadImages() }
            .onDisappear { cancelRequests() }
        }
    }

    private func loadImages() {
        guard fullImage == nil else { return }

        let thumbOptions = PHImageRequestOptions()
        thumbOptions.isNetworkAccessAllowed = false
        thumbOptions.deliveryMode = .fastFormat
        thumbOptions.resizeMode = .fast

        let thumbID = sharedImageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 400, height: 400),
            contentMode: .aspectFill,
            options: thumbOptions
        ) { img, _ in
            if let img = img, fullImage == nil { thumbnailImage = img }
        }

        // ViewModel 프리히팅과 같은 스펙으로 요청해야 캐시가 적중한다.
        let fullID = sharedImageManager.requestImage(
            for: asset,
            targetSize: ReviewImageSpec.targetSize,
            contentMode: ReviewImageSpec.contentMode,
            options: ReviewImageSpec.makeOptions()
        ) { img, _ in
            if let img = img { fullImage = img }
        }

        requestIDs = [thumbID, fullID]
    }

    private func cancelRequests() {
        requestIDs.forEach { sharedImageManager.cancelImageRequest($0) }
        requestIDs = []
    }
}
