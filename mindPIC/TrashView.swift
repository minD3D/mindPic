import SwiftUI
import Photos

struct TrashView: View {
    @StateObject private var vm = PhotoReviewViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasAuth = false
    @State private var authChecked = false
    @State private var showEmptyAlert = false
    @State private var showRestoreAllAlert = false
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var peekItem: PhotoItem?   // 크게 보는 사진
    @State private var trashBytes: Int64?   // 비우면 정리될 용량 (계산 중이면 nil)

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
    private var isEmptyDisabled: Bool { vm.trashedPhotoIDs.isEmpty || !hasAuth }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                if !authChecked {
                    ProgressView("권한 확인 중…")
                        .tint(AppTheme.accentDark)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear { requestAccessAndLoad() }
                } else if !hasAuth {
                    PhotoPermissionView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.isLoading {
                    ProgressView("불러오는 중…")
                        .tint(AppTheme.accentDark)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.photos.isEmpty {
                    if let freed = vm.lastFreedBytes {
                        freedResultView(freed)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "trash")
                                .font(.system(size: 30, weight: .medium))
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 76, height: 76)
                                .background(AppTheme.accentSoft, in: Circle())
                            Text("휴지통이 비어 있습니다")
                                .font(AppFont.subtitle)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ScrollView {
                        if let trashBytes, trashBytes > 0 {
                            Label("비우면 약 \(PhotoSize.formatted(trashBytes)) 확보", systemImage: "internaldrive")
                                .font(AppFont.buttonSmall)
                                .foregroundStyle(AppTheme.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(AppTheme.accentSoft, in: Capsule())
                                .padding(.top, 12)
                        }

                        Text(isSelecting ? "복원할 사진을 골라 주세요" : "탭하면 크게 보고, 길게 누르거나 '선택'으로 복원할 수 있어요")
                            .font(AppFont.caption)
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, (trashBytes ?? 0) > 0 ? 6 : 12)

                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(vm.photos) { item in
                                thumbnail(item)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionBar
            } else {
                Button {
                    showEmptyAlert = true
                } label: {
                    AppButtonLabel(
                        text: Text("휴지통 비우기"),
                        systemImage: "trash",
                        foreground: isEmptyDisabled ? AppTheme.textSecondary : .white,
                        background: isEmptyDisabled ? AppTheme.cardStrong : AppTheme.danger,
                        border: isEmptyDisabled ? AppTheme.border : nil,
                        shadow: !isEmptyDisabled
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }
                .disabled(isEmptyDisabled)
            }
        }
        .toolbar {
            if hasAuth && !vm.photos.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? "완료" : "선택") {
                        isSelecting.toggle()
                        selectedIDs = []
                    }
                    .accessibilityIdentifier("trash.select")
                }
            }
        }
        .onChange(of: vm.photos.map(\.id)) { _, ids in
            // 복원으로 사라진 사진은 선택에서도 뺀다.
            selectedIDs.formIntersection(ids)
            if ids.isEmpty { isSelecting = false }
        }
        .fullScreenCover(item: $peekItem) { item in
            FullScreenPhotoView(asset: item.asset)
                .ignoresSafeArea()
                .onTapGesture { peekItem = nil }
                .accessibilityAction(named: Text("닫기")) { peekItem = nil }
        }
        .navigationTitle(vm.photos.isEmpty ? Text("휴지통") : Text("휴지통 (\(vm.photos.count))"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: vm.photos.map(\.id)) { await updateTrashBytes() }
        .toolbar(.visible, for: .navigationBar)
        .onChange(of: scenePhase) { _, phase in
            // 설정 앱에서 권한을 바꾸고 돌아온 경우 다시 확인
            if phase == .active && authChecked && !hasAuth {
                requestAccessAndLoad()
            }
        }
        .alert("휴지통을 비울까요?", isPresented: $showEmptyAlert) {
            Button("비우기", role: .destructive) { vm.emptyTrash() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("\(vm.photos.count)장이 사진 앱의 '최근 삭제된 항목'으로 이동하며, 30일 후 영구 삭제됩니다.")
        }
        .alert("모두 복원할까요?", isPresented: $showRestoreAllAlert) {
            Button("모두 복원") { restore(vm.photos.map(\.id)) }
            Button("취소", role: .cancel) {}
        } message: {
            Text("\(vm.photos.count)장을 휴지통에서 빼고 원래 라이브러리로 되돌립니다.")
        }
    }

    private func thumbnail(_ item: PhotoItem) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        return PhotoThumbnailView(asset: item.asset)
            .overlay {
                if isSelecting {
                    Rectangle()
                        .fill(Color.black.opacity(isSelected ? 0.25 : 0))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelecting {
                    ZStack {
                        Circle().fill(isSelected ? AppTheme.accent : Color.black.opacity(0.25))
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelecting {
                    if isSelected { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
                } else {
                    peekItem = item
                }
            }
            .contextMenu {
                Button {
                    peekItem = item
                } label: {
                    Label("크게 보기", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                Button {
                    vm.restore(photoID: item.id)
                } label: {
                    Label("복원", systemImage: "arrow.uturn.backward")
                }
            }
            .accessibilityElement()
            .accessibilityLabel("휴지통 사진")
            .accessibilityAddTraits(isSelecting && isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(isSelecting ? Text("탭하면 선택하거나 해제합니다") : Text("탭하면 크게 봅니다"))
            .accessibilityAction(named: Text("복원")) { vm.restore(photoID: item.id) }
    }

    // 선택 모드 하단: 고른 사진 복원 / 모두 복원
    private var selectionBar: some View {
        HStack(spacing: 10) {
            Button {
                showRestoreAllAlert = true
            } label: {
                AppButtonLabel(
                    text: Text("모두 복원"),
                    foreground: AppTheme.textPrimary,
                    background: AppTheme.surface,
                    border: AppTheme.border,
                    shadow: false
                )
            }
            .accessibilityIdentifier("trash.restoreAll")

            Button {
                restore(Array(selectedIDs))
            } label: {
                AppButtonLabel(
                    text: Text("복원 (\(selectedIDs.count))"),
                    systemImage: "arrow.uturn.backward",
                    foreground: selectedIDs.isEmpty ? AppTheme.textSecondary : .white,
                    background: selectedIDs.isEmpty ? AppTheme.cardStrong : AppTheme.accentDark,
                    border: selectedIDs.isEmpty ? AppTheme.border : nil,
                    shadow: !selectedIDs.isEmpty
                )
            }
            .disabled(selectedIDs.isEmpty)
            .accessibilityIdentifier("trash.restoreSelected")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    // 뷰모델의 한 장 복원을 반복해 여러 장을 되돌린다.
    private func restore(_ ids: [String]) {
        for id in ids { vm.restore(photoID: id) }
        selectedIDs = []
        isSelecting = false
    }

    // 방금 비운 결과: 이번에 정리한 용량과 지금까지의 합계
    private func freedResultView(_ freed: Int64) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(AppTheme.accent, in: Circle())
            Text("방금 \(PhotoSize.formatted(freed)) 확보했어요")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("지금까지 \(PhotoSize.formatted(ReviewStateStore.freedBytes())) 확보했어요")
                .font(AppFont.subtitle)
                .foregroundStyle(AppTheme.textSecondary)
            Text("'최근 삭제된 항목'을 비우면 바로, 아니면 30일 뒤에 실제 공간이 비워져요.")
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(.horizontal, 32)
    }

    private func updateTrashBytes() async {
        let items = vm.photos
        trashBytes = nil
        guard !items.isEmpty else { return }
        let bytes = await Task.detached(priority: .utility) { PhotoSize.bytes(of: items) }.value
        guard !Task.isCancelled else { return }
        trashBytes = bytes
    }

    private func requestAccessAndLoad() {
        requestPhotoAuth { ok in
            hasAuth = ok
            authChecked = true
            if ok {
                vm.selectTrash()
            }
        }
    }
}
