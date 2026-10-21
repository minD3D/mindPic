import Foundation

// MARK: - 리뷰 상태 저장소 (본 사진 / 휴지통)
// UserDefaults 키는 기존 버전과 동일하게 유지해 이미 저장된 데이터가 그대로 이어진다.
final class ReviewStateStore {
    static let seenKey = "seen_photos"
    static let trashedKey = "trashed_photos"

    private let defaults: UserDefaults
    private(set) var seenIDs: Set<String>
    private(set) var trashedIDs: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        seenIDs = Self.loadIDs(forKey: Self.seenKey, from: defaults)
        trashedIDs = Self.loadIDs(forKey: Self.trashedKey, from: defaults)
    }

    static func trashCount(in defaults: UserDefaults = .standard) -> Int {
        loadIDs(forKey: trashedKey, from: defaults).count
    }

    static func seenCount(in defaults: UserDefaults = .standard) -> Int {
        loadIDs(forKey: seenKey, from: defaults).count
    }

    // "안 본 사진만 보기"를 처음부터 다시 쓰고 싶을 때
    func resetSeen() {
        seenIDs.removeAll()
        save(seenIDs, forKey: Self.seenKey)
    }

    func markSeen(_ id: String) {
        guard seenIDs.insert(id).inserted else { return }
        save(seenIDs, forKey: Self.seenKey)
    }

    func addToTrash(_ id: String) {
        guard trashedIDs.insert(id).inserted else { return }
        save(trashedIDs, forKey: Self.trashedKey)
    }

    func removeFromTrash(_ ids: Set<String>) {
        let before = trashedIDs.count
        trashedIDs.subtract(ids)
        guard trashedIDs.count != before else { return }
        save(trashedIDs, forKey: Self.trashedKey)
    }

    private func save(_ ids: Set<String>, forKey key: String) {
        defaults.set(Array(ids), forKey: key)
    }

    private static func loadIDs(forKey key: String, from defaults: UserDefaults) -> Set<String> {
        Set(defaults.array(forKey: key) as? [String] ?? [])
    }
}
