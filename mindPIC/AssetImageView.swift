import SwiftUI
import Photos
import UIKit

// MARK: - 이미지 로더 (미리보기 + 고해상도)
struct AssetImageView: View {
    let asset: PHAsset
    @State private var thumbnailImage: UIImage?
    @State private var fullImage: UIImage?
    @State private var requestIDs: [PHImageRequestID] = []
    @State private var isActive = false
    @State private var downloadProgress: Double?   // iCloud에서 받는 중일 때만 값이 있다
    @State private var didDownload = false
    @State private var loadFailed = false

    // 고화질이 이 시간 안에 오면(이미 미리 받아 둔 경우) 흐린 미리보기 요청을 건너뛴다.
    private static let previewDelay: TimeInterval = 0.06

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
                    if !loadFailed {
                        ProgressView()
                            .tint(AppTheme.accentDark)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                // iCloud에서 원본을 받는 중이면 흐린 이유를 알 수 있게 진행률을 보여 준다.
                if fullImage == nil, !loadFailed, let progress = downloadProgress {
                    DownloadProgressRing(progress: progress)
                        .padding(14)
                }
            }
            .overlay {
                if loadFailed && fullImage == nil {
                    loadFailedView
                }
            }
            .onAppear {
                isActive = true
                loadImages()
            }
            .onDisappear {
                isActive = false
                cancelRequests()
            }
        }
    }

    private var loadFailedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 26, weight: .medium))
            Text("iCloud에서 불러오지 못했어요")
                .font(AppFont.buttonSmall)
            Button {
                loadFailed = false
                loadImages()
            } label: {
                Label("다시 시도", systemImage: "arrow.clockwise")
                    .font(AppFont.buttonSmall.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white, in: Capsule())
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func loadImages() {
        guard fullImage == nil else { return }
        let startedAt = Date()
        let assetID = asset.localIdentifier

        // ViewModel 프리히팅과 같은 스펙으로 요청해야 캐시가 적중한다.
        let fullOptions = ReviewImageSpec.makeOptions()
        fullOptions.progressHandler = { progress, _, _, _ in
            DispatchQueue.main.async {
                guard fullImage == nil else { return }
                downloadProgress = progress
                didDownload = true
            }
        }
        let fullID = sharedImageManager.requestImage(
            for: asset,
            targetSize: ReviewImageSpec.targetSize,
            contentMode: ReviewImageSpec.contentMode,
            options: fullOptions
        ) { img, info in
            guard let img else {
                // 화면을 떠나 취소된 경우가 아니면 실패로 보고 다시 시도할 수 있게 한다.
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                if !cancelled {
                    loadFailed = true
                    downloadProgress = nil
                    imageLoadLog.notice("full image failed (iCloud download: \(didDownload, privacy: .public))")
                }
                return
            }
            // 화면에 처음 그릴 때 메인 스레드에서 압축을 푸느라 끊기지 않도록 미리 풀어 둔다.
            Task {
                let prepared = await img.byPreparingForDisplay() ?? img
                fullImage = prepared
                downloadProgress = nil
                LocalAvailabilityCache.knownLocal.insert(assetID)

                let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
                imageLoadLog.notice("full image ready in \(ms, privacy: .public)ms (iCloud download: \(didDownload, privacy: .public))")
            }
        }
        requestIDs = [fullID]

        // 기기 안에 있는 것 중 가장 좋은 미리보기 (네트워크 없이).
        // opportunistic은 아주 작은 이미지를 먼저 주고, 더 나은 로컬 이미지가 있으면 한 번 더 준다.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.previewDelay) {
            guard isActive, fullImage == nil, thumbnailImage == nil else { return }

            let previewOptions = PHImageRequestOptions()
            previewOptions.isNetworkAccessAllowed = false
            previewOptions.deliveryMode = .opportunistic
            previewOptions.resizeMode = .fast

            let previewID = sharedImageManager.requestImage(
                for: asset,
                targetSize: ReviewImageSpec.previewSize,
                contentMode: ReviewImageSpec.contentMode,
                options: previewOptions
            ) { img, _ in
                if let img, fullImage == nil { thumbnailImage = img }
            }
            requestIDs.append(previewID)
        }
    }

    private func cancelRequests() {
        requestIDs.forEach { sharedImageManager.cancelImageRequest($0) }
        requestIDs = []
    }
}

// iCloud 다운로드 진행률 (0~1)
private struct DownloadProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.3), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.03, progress))
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: progress)
        }
        .frame(width: 20, height: 20)
        .padding(8)
        .background(.black.opacity(0.35), in: Circle())
        .accessibilityElement()
        .accessibilityLabel(Text("iCloud에서 받는 중"))
        .accessibilityValue(Text(verbatim: "\(Int(progress * 100))%"))
    }
}

// MARK: - 전체 화면 보기 (길게 누르는 동안)
// 카드는 꽉 채우려고 사진을 잘라 보여주므로, 여기서는 화면 전체에 사진 전체가 보이게 한다.
struct FullScreenPhotoView: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear { load() }
        .onDisappear {
            if let requestID { sharedImageManager.cancelImageRequest(requestID) }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("사진"))
    }

    private func load() {
        let screen = UIScreen.main
        let size = CGSize(width: screen.bounds.width * screen.scale,
                          height: screen.bounds.height * screen.scale)

        // opportunistic: 기기에 있는 미리보기를 바로 보여주고, 고화질이 오면 바꾼다.
        let opt = PHImageRequestOptions()
        opt.isNetworkAccessAllowed = true
        opt.deliveryMode = .opportunistic
        opt.resizeMode = .fast

        requestID = sharedImageManager.requestImage(
            for: asset, targetSize: size, contentMode: .aspectFit, options: opt
        ) { img, _ in
            if let img { image = img }
        }
    }
}
