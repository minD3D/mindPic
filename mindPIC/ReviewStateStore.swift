import Foundation
import Photos

// MARK: - 리뷰 상태 저장소 (본 사진 / 휴지통)
// UserDefaults 키는 기존 버전과 동일하게 유지해 이미 저장된 데이터가 그대로 이어진다.
final class ReviewStateStore {
    static let seenKey = "seen_photos"
    static let trashedKey = "trashed_photos"
    static let freedBytesKey = "freed_bytes"

    private let defaults: UserDefaults
    private(set) var seenIDs: Set<String>
    private(set) var trashedIDs: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        seenIDs = Self.loadIDs(forKey: Self.seenKey, from: defaults)
        trashedIDs = Self.loadIDs(forKey: Self.trashedKey, from: defaults)
    }

    // 다른 화면에서 바뀐 기록을 다시 읽는다.
    func reload() {
        seenIDs = Self.loadIDs(forKey: Self.seenKey, from: defaults)
        trashedIDs = Self.loadIDs(forKey: Self.trashedKey, from: defaults)
    }

    static func trashCount(in defaults: UserDefaults = .standard) -> Int {
        loadIDs(forKey: trashedKey, from: defaults).count
    }

    // UI 테스트(스크린샷)를 항상 같은 상태에서 시작하기 위함
    static func resetAll(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: seenKey)
        defaults.removeObject(forKey: trashedKey)
        defaults.removeObject(forKey: freedBytesKey)
    }

    // 휴지통을 비우며 지금까지 정리한 사진 용량 (바이트)
    static func freedBytes(in defaults: UserDefaults = .standard) -> Int64 {
        (defaults.object(forKey: freedBytesKey) as? NSNumber)?.int64Value ?? 0
    }

    func addFreedBytes(_ bytes: Int64) {
        guard bytes > 0 else { return }
        let total = Self.freedBytes(in: defaults) + bytes
        defaults.set(NSNumber(value: total), forKey: Self.freedBytesKey)
    }

    static func seenCount(in defaults: UserDefaults = .standard) -> Int {
        loadIDs(forKey: seenKey, from: defaults).count
    }

    // 본 사진 중 아직 사진첩에 남아 있는 수. 지운 사진의 ID도 기록에 남아 있어서
    // seenCount()만 쓰면 화면마다 숫자가 달라지므로, 사용자에게 보여줄 때는 이 값을 쓴다.
    static func existingSeenCount(in defaults: UserDefaults = .standard) async -> Int {
        let seenIDs = Array(loadIDs(forKey: seenKey, from: defaults))
        guard !seenIDs.isEmpty else { return 0 }
        return await Task.detached(priority: .utility) {
            PHAsset.fetchAssets(withLocalIdentifiers: seenIDs, options: nil).count
        }.value
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

    // 여러 장을 한 번에 넣을 때 (저장도 한 번만)
    func addAllToTrash(_ ids: Set<String>) {
        let before = trashedIDs.count
        trashedIDs.formUnion(ids)
        guard trashedIDs.count != before else { return }
        save(trashedIDs, forKey: Self.trashedKey)
    }

    func markAllSeen(_ ids: Set<String>) {
        let before = seenIDs.count
        seenIDs.formUnion(ids)
        guard seenIDs.count != before else { return }
        save(seenIDs, forKey: Self.seenKey)
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
