import Foundation
import Photos

let trashedPhotosKey = "trashed_photos"

// MARK: - 모델
struct PhotoItem: Identifiable {
    let id: String
    let asset: PHAsset
}

// 필터 종류 (주 필터)
enum PhotoFilterType {
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
