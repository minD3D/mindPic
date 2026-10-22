import SwiftUI
import Photos

struct TrashView: View {
    @StateObject private var vm = PhotoReviewViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasAuth = false
    @State private var authChecked = false
    @State private var showEmptyAlert = false
    @State private var showRestoreAlert = false
    @State private var selectedPhotoID: String?
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

                        Text("사진을 탭하거나 길게 눌러 복원할 수 있어요")
                            .font(AppFont.caption)
                            .foregroundColor(AppTheme.textSecondary)
                            .padding(.top, (trashBytes ?? 0) > 0 ? 6 : 12)

                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(vm.photos) { item in
                                PhotoThumbnailView(asset: item.asset)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedPhotoID = item.id
                                        showRestoreAlert = true
                                    }
                                    .contextMenu {
                                        Button {
                                            vm.restore(photoID: item.id)
                                        } label: {
                                            Label("복원", systemImage: "arrow.uturn.backward")
                                        }
                                    }
                                    .accessibilityLabel("휴지통 사진")
                                    .accessibilityHint("탭하면 복원할 수 있습니다")
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
        .alert("사진을 복원할까요?", isPresented: $showRestoreAlert) {
            Button("복원") {
                if let id = selectedPhotoID {
                    vm.restore(photoID: id)
                }
                selectedPhotoID = nil
            }
            Button("취소", role: .cancel) {
                selectedPhotoID = nil
            }
        } message: {
            Text("휴지통에서 제거하고 원래 라이브러리로 되돌립니다.")
        }
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
