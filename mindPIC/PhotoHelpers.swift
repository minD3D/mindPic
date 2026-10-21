import Foundation
import Network
import os
import Photos
import UIKit

// 전역 캐시 매니저
let sharedImageManager = PHCachingImageManager()

// 이미지 로딩 시간 측정용 로그. Mac의 '콘솔' 앱에서 기기를 고르고 subsystem으로 걸러 볼 수 있다.
let imageLoadLog = Logger(subsystem: "mind3d.mindPIC", category: "ImageLoading")

// MARK: - 기기에 있는 사진 기록
// 기기에 있다고 확인된 사진은 앱이 켜져 있는 동안 기억해, 필터를 바꿔도 다시 확인하지 않는다.
// (iCloud에 있다는 결과는 기억하지 않는다. 미리 받고 나면 기기에 생기기 때문)
@MainActor
enum LocalAvailabilityCache {
    static var knownLocal: Set<String> = []
}

// MARK: - 네트워크 상태
// 셀룰러나 저데이터 모드에서는 iCloud 사진을 미리 받지 않아 데이터를 아낀다.
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isExpensiveOrConstrained = false
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let limited = path.isExpensive || path.isConstrained
            Task { @MainActor in self?.isExpensiveOrConstrained = limited }
        }
        monitor.start(queue: DispatchQueue(label: "mind3d.mindPIC.network"))
    }
}

// MARK: - 권한 요청 Helper
func requestPhotoAuth(completion: @escaping (Bool) -> Void) {
    PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
        DispatchQueue.main.async {
            completion(status == .authorized || status == .limited)
        }
    }
}

// 권한이 한 번 거부되면 iOS는 다시 묻지 않으므로 설정 앱으로 보내야 한다.
@MainActor
func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
}

// MARK: - 리뷰 화면 이미지 요청 스펙
// PHCachingImageManager는 targetSize / contentMode / options가 같아야 캐시를 재사용한다.
// 프리히팅(ViewModel)과 실제 요청(AssetImageView)이 반드시 이 값을 같이 써야 캐시가 맞는다.
@MainActor
enum ReviewImageSpec {
    static let contentMode: PHImageContentMode = .aspectFill

    // 리뷰 카드 크기(화면 폭 90% × 높이 63%)만큼만 요청한다. 화면 전체 크기로 받으면
    // iCloud 다운로드와 디코딩이 그만큼 느려진다. 사진은 2배율이면 3배율과 눈으로 구분하기 어렵다.
    static var targetSize: CGSize {
        let screen = UIScreen.main
        let scale = min(screen.scale, 2)
        return CGSize(width: (screen.bounds.width * 0.9 * scale).rounded(),
                      height: (screen.bounds.height * 0.63 * scale).rounded())
    }

    // 고화질이 오기 전에 보여 줄 기기 안의 미리보기. 카드 절반 해상도면 흐려 보이지 않는다.
    static var previewSize: CGSize {
        CGSize(width: targetSize.width / 2, height: targetSize.height / 2)
    }

    static func makeOptions() -> PHImageRequestOptions {
        let opt = PHImageRequestOptions()
        opt.isNetworkAccessAllowed = true
        opt.deliveryMode = .highQualityFormat
        opt.resizeMode = .fast
        return opt
    }
}
