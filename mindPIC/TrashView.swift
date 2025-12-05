import SwiftUI
import Photos

struct TrashView: View {
    @StateObject private var vm = PhotoReviewViewModel()
    @State private var hasAuth = false
    @State private var authChecked = false
    @State private var showEmptyAlert = false
    @State private var showRestoreAlert = false
    @State private var selectedPhotoID: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
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
                    VStack(spacing: 12) {
                        Text("사진 접근 권한이 필요합니다.")
                            .font(AppFont.body)
                            .foregroundColor(AppTheme.textPrimary)
                        Button("다시 요청") {
                            requestAccessAndLoad()
                        }
                        .font(AppFont.buttonSmall)
                        .foregroundColor(AppTheme.accentDark)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.isLoading {
                    ProgressView("불러오는 중…")
                        .tint(AppTheme.accentDark)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.photos.isEmpty {
                    Text("휴지통이 비어\n있습니다")
                        .font(AppFont.subtitle)
                        .multilineTextAlignment(.center)
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(vm.photos) { item in
                                TrashThumbnailView(asset: item.asset)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedPhotoID = item.id
                                        showRestoreAlert = true
                                    }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
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
                    text: "휴지통 비우기",
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
        .navigationTitle("휴지통")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .alert("휴지통을 비울까요?", isPresented: $showEmptyAlert) {
            Button("비우기", role: .destructive) { vm.emptyTrash() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("휴지통의 사진이 영구적으로 삭제됩니다.")
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
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    AppTheme.card
                    ProgressView()
                        .tint(AppTheme.accentDark)
                }
            }
            .clipped()
            .onAppear { loadThumbnail(containerSize: geo.size) }
        }
        .aspectRatio(1, contentMode: .fit)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .shadow(color: AppTheme.shadow, radius: 6, x: 0, y: 3)
    }

    private func loadThumbnail(containerSize: CGSize) {
        guard image == nil else { return }
        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: containerSize.width * scale, height: containerSize.height * scale)

        let opt = PHImageRequestOptions()
        opt.isNetworkAccessAllowed = true
        opt.deliveryMode = .opportunistic
        opt.resizeMode = .fast

        sharedImageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: opt
        ) { img, _ in
            if let img = img { image = img }
        }
    }
}
