import SwiftUI
import Photos
import UIKit

// MARK: - 이미지 로더 (썸네일 + 고해상도)
struct AssetImageView: View {
    let asset: PHAsset
    @State private var thumbnailImage: UIImage?
    @State private var fullImage: UIImage?

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
            .onAppear { loadImages(asset: asset, containerSize: geo.size) }
        }
    }

    private func loadImages(asset: PHAsset, containerSize: CGSize) {
        let scale = UIScreen.main.scale

        let thumbSize = CGSize(
            width: min(400, containerSize.width * scale),
            height: min(400, containerSize.height * scale)
        )
        let fullSize = CGSize(
            width: containerSize.width * scale,
            height: containerSize.height * scale
        )

        let thumbOptions = PHImageRequestOptions()
        thumbOptions.isNetworkAccessAllowed = false
        thumbOptions.deliveryMode = .fastFormat
        thumbOptions.resizeMode = .fast

        sharedImageManager.requestImage(
            for: asset,
            targetSize: thumbSize,
            contentMode: .aspectFill,
            options: thumbOptions
        ) { img, _ in
            if let img = img { self.thumbnailImage = img }
        }

        let fullOptions = PHImageRequestOptions()
        fullOptions.isNetworkAccessAllowed = true
        fullOptions.deliveryMode = .highQualityFormat
        fullOptions.resizeMode = .fast

        sharedImageManager.requestImage(
            for: asset,
            targetSize: fullSize,
            contentMode: .aspectFill,
            options: fullOptions
        ) { img, _ in
            if let img = img { self.fullImage = img }
        }
    }
}
