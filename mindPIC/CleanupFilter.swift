import Foundation
import Photos
import SwiftUI

// MARK: - 분석 기간 (정리 추천, 비슷한 사진 공통)
// 고정 기간 또는 직접 고른 날짜 범위
enum CleanupPeriod: Hashable, Identifiable {
    case scope(AnalysisScope)
    case custom

    static let allCases: [CleanupPeriod] = AnalysisScope.allCases.map { .scope($0) } + [.custom]

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .scope(let scope): return scope.title
        case .custom: return "직접 선택"
        }
    }

    // 분석할 날짜 범위. 직접 선택은 끝 날짜의 하루 전체를 포함한다.
    func dateRange(customStart: Date, customEnd: Date) -> (since: Date?, until: Date?) {
        switch self {
        case .scope(let scope):
            return (scope.since, nil)
        case .custom:
            let cal = Calendar.current
            let start = cal.startOfDay(for: min(customStart, customEnd))
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: max(customStart, customEnd)))
            return (start, end)
        }
    }

    // 결과가 없을 때 넓혀 볼 다음 기간. 이미 전체면 nil.
    var wider: CleanupPeriod? {
        switch self {
        case .scope(.month): return .scope(.year)
        case .scope(.year), .custom: return .scope(.all)
        case .scope(.all): return nil
        }
    }
}

// MARK: - 직접 선택 빠른 기간
// 날짜를 하나씩 고르지 않도록 연도·월·최근 N년 단위로 시작·끝 날짜를 채운다. 양 끝 날짜 포함.
enum QuickDateRange: Hashable {
    case recentMonths(Int)
    case recentYears(Int)
    case year(Int)
    case month(year: Int, month: Int)

    func range(now: Date = Date(), calendar cal: Calendar = .current) -> (start: Date, end: Date) {
        let today = cal.startOfDay(for: now)
        switch self {
        case .recentMonths(let n):
            return (cal.date(byAdding: .month, value: -n, to: today) ?? today, today)
        case .recentYears(let n):
            return (cal.date(byAdding: .year, value: -n, to: today) ?? today, today)
        case .year(let y):
            return clamped(cal.date(from: DateComponents(year: y, month: 1, day: 1)),
                           cal.date(from: DateComponents(year: y, month: 12, day: 31)), today: today)
        case .month(let y, let m):
            let start = cal.date(from: DateComponents(year: y, month: m, day: 1))
            let end = start.flatMap { cal.date(byAdding: DateComponents(month: 1, day: -1), to: $0) }
            return clamped(start, end, today: today)
        }
    }

    // 올해·이번 달처럼 아직 끝나지 않은 기간은 오늘까지로 자른다 (날짜 선택기가 미래를 허용하지 않음).
    private func clamped(_ start: Date?, _ end: Date?, today: Date) -> (start: Date, end: Date) {
        let s = min(start ?? today, today)
        return (s, min(end ?? today, today))
    }
}

// MARK: - 사진 종류
enum CleanupPhotoKind: String, CaseIterable, Identifiable, Sendable {
    case selfie, burst, live

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .selfie: return "셀카"
        case .burst: return "연사"
        case .live: return "라이브 포토"
        }
    }

    var systemImage: String {
        switch self {
        case .selfie: return "person.crop.square"
        case .burst: return "square.stack.3d.down.right"
        case .live: return "livephoto"
        }
    }
}

enum CleanupSort: String, CaseIterable, Identifiable {
    case newest, largest

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .newest: return "최신순"
        case .largest: return "용량 큰 순"
        }
    }
}

// 필터 판단에 필요한 사진 정보 (PhotoKit과 무관하게 테스트할 수 있도록 분리)
struct CleanupPhotoFacts: Equatable {
    var kinds: Set<CleanupPhotoKind> = []
    var categories: Set<PhotoCategory> = []   // 기기 분석으로 찾은 내용
    var isSeen = false
    var isInAlbum = false
}

// MARK: - 필터
struct CleanupFilter: Equatable {
    var kinds: Set<CleanupPhotoKind> = []   // 비어 있으면 모든 종류. 여러 개면 하나라도 해당하면 보여준다.
    var categories: Set<PhotoCategory> = [] // 내용 (기기 분석). 규칙은 종류와 같다.
    var unseenOnly = false
    var notInAlbumOnly = false
    var sort: CleanupSort = .newest

    // 정렬을 뺀 조건 수 (필터 버튼 배지용)
    var activeCount: Int {
        (kinds.isEmpty ? 0 : 1) + (categories.isEmpty ? 0 : 1) + (unseenOnly ? 1 : 0) + (notInAlbumOnly ? 1 : 0)
    }

    func matches(_ facts: CleanupPhotoFacts) -> Bool {
        if !kinds.isEmpty && kinds.isDisjoint(with: facts.kinds) { return false }
        if !categories.isEmpty && categories.isDisjoint(with: facts.categories) { return false }
        if unseenOnly && facts.isSeen { return false }
        if notInAlbumOnly && facts.isInAlbum { return false }
        return true
    }

    // 비슷한 사진 묶음: 조건에 맞는 사진이 한 장이라도 있으면 보여준다.
    func matchesAny(_ facts: [CleanupPhotoFacts]) -> Bool {
        facts.contains(where: matches)
    }
}

// MARK: - 앨범·셀카 소속
// 사진마다 앨범을 조회하면 느리므로, 분석을 시작할 때 한 번에 모아 둔다.
struct PhotoMembership: Sendable {
    var albumIDs: Set<String> = []
    var selfieIDs: Set<String> = []

    nonisolated static func load() -> PhotoMembership {
        PhotoMembership(
            albumIDs: assetIDs(in: PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)),
            selfieIDs: assetIDs(in: PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil))
        )
    }

    private nonisolated static func assetIDs(in collections: PHFetchResult<PHAssetCollection>) -> Set<String> {
        var ids: Set<String> = []
        collections.enumerateObjects { collection, _, _ in
            PHAsset.fetchAssets(in: collection, options: nil).enumerateObjects { asset, _, _ in
                ids.insert(asset.localIdentifier)
            }
        }
        return ids
    }

    func facts(for asset: PHAsset, seenIDs: Set<String>) -> CleanupPhotoFacts {
        let id = asset.localIdentifier
        var kinds: Set<CleanupPhotoKind> = []
        if selfieIDs.contains(id) { kinds.insert(.selfie) }
        if asset.representsBurst || asset.burstIdentifier != nil { kinds.insert(.burst) }
        if asset.mediaSubtypes.contains(.photoLive) { kinds.insert(.live) }
        return CleanupPhotoFacts(kinds: kinds, isSeen: seenIDs.contains(id), isInAlbum: albumIDs.contains(id))
    }
}
