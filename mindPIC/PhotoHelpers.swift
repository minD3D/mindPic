import Foundation
import Photos

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
