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
    case category(PhotoCategory)   // 기기 안에서 분류한 사진 종류
    case trash
}

extension PhotoFilterType {
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMMMM")
        return f
    }()

    // 리뷰 화면 상단 칩에 현재 필터를 보여주기 위한 이름
    var title: String {
        switch self {
        case .random100: return String(localized: "랜덤 100장")
        case .yearsAgo(let years): return String(localized: "\(years)년 전 오늘")
        case .monthRange(let start): return Self.monthFormatter.string(from: start)
        case .recentDays(let days): return String(localized: "최근 \(days)일")
        case .peoplePortrait: return String(localized: "인물 사진")
        case .nonFavorite: return String(localized: "즐겨찾기 안 된 사진")
        case .screenshot: return String(localized: "스크린샷")
        case .burst: return String(localized: "연사")
        case .category(let category): return category.title
        case .trash: return String(localized: "휴지통")
        }
    }
}
