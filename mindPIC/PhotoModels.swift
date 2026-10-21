import Foundation
import Photos

// MARK: - 모델
// PHAsset은 불변 객체라 스레드 간 전달이 안전하다 (백그라운드 조회 결과를 메인으로 넘기기 위함)
struct PhotoItem: Identifiable, @unchecked Sendable {
    let id: String
    let asset: PHAsset
}

extension PhotoItem {
    init(asset: PHAsset) {
        self.init(id: asset.localIdentifier, asset: asset)
    }
}

// 필터 종류 (주 필터)
enum PhotoFilterType: Equatable {
    case random100
    case yearsAgo(Int)
    case monthRange(Date)
    case recentDays(Int)
    case peoplePortrait
    case nonFavorite
    case screenshot
    case burst
    case trash
}
