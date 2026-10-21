import Foundation
import Photos
import UIKit

// 전역 캐시 매니저
let sharedImageManager = PHCachingImageManager()

// MARK: - 권한 요청 Helper
func requestPhotoAuth(completion: @escaping (Bool) -> Void) {
    PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
        DispatchQueue.main.async {
            completion(status == .authorized || status == .limited)
        }
    }
}

// MARK: - 리뷰 화면 이미지 요청 스펙
// PHCachingImageManager는 targetSize / contentMode / options가 같아야 캐시를 재사용한다.
// 프리히팅(ViewModel)과 실제 요청(AssetImageView)이 반드시 이 값을 같이 써야 캐시가 맞는다.
@MainActor
enum ReviewImageSpec {
    static let contentMode: PHImageContentMode = .aspectFill

    static var targetSize: CGSize {
        let screen = UIScreen.main
        return CGSize(width: screen.bounds.width * screen.scale,
                      height: screen.bounds.height * screen.scale)
    }

    static func makeOptions() -> PHImageRequestOptions {
        let opt = PHImageRequestOptions()
        opt.isNetworkAccessAllowed = true
        opt.deliveryMode = .highQualityFormat
        opt.resizeMode = .fast
        return opt
    }
}
