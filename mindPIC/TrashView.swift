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
                } else {
                    ScrollView {
                        Text("사진을 탭하거나 길게 눌러 복원할 수 있어요")
                            .font(AppFont.caption)
                            .foregroundColor(AppTheme.textSecondary)
                            .padding(.top, 12)

                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(vm.photos) { item in
                                TrashThumbnailView(asset: item.asset)
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

private struct TrashThumbnailView: View {
    let asset: PHAsset
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    AppTheme.surfaceMuted
                    ProgressView()
                        .tint(AppTheme.accentDark)
                }
            }
            .clipped()
            .onAppear { loadThumbnail(containerSize: geo.size) }
            .onDisappear { cancelRequest() }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func loadThumbnail(containerSize: CGSize) {
        guard image == nil else { return }
        let targetSize = CGSize(width: containerSize.width * displayScale,
                                height: containerSize.height * displayScale)

        let opt = PHImageRequestOptions()
        opt.isNetworkAccessAllowed = true
        opt.deliveryMode = .opportunistic
        opt.resizeMode = .fast

        requestID = sharedImageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: opt
        ) { img, _ in
            if let img = img { image = img }
        }
    }

    private func cancelRequest() {
        if let id = requestID { sharedImageManager.cancelImageRequest(id) }
        requestID = nil
    }
}
