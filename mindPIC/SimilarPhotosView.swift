import Photos
import SwiftUI

// MARK: - 비슷한 사진 정리
// 비슷한 사진끼리 묶어 보여주고, 추천 사진만 남기고 나머지를 휴지통으로 옮긴다.
struct SimilarPhotosView: View {
    @StateObject private var vm = SimilarPhotosViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasAuth = false
    @State private var authChecked = false

    // 길게 눌러 크게 보기
    @State private var peekItem: PhotoItem?

    @State private var showUndoToast = false
    @State private var undoToastToken = 0
    @State private var cleanFeedback = 0

    private let thumbnailSize: CGFloat = 112

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                if !authChecked {
                    ProgressView("권한 확인 중…")
                        .tint(AppTheme.accentDark)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear { checkAuthAndStart() }
                } else if !hasAuth {
                    PhotoPermissionView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showUndoToast && vm.canUndo {
                undoToast
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("비슷한 사진")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .fullScreenCover(item: $peekItem) { item in
            FullScreenPhotoView(asset: item.asset)
                .ignoresSafeArea()
                .onTapGesture { peekItem = nil }
                .accessibilityAction(named: Text("닫기")) { peekItem = nil }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: cleanFeedback)
        .onChange(of: scenePhase) { _, phase in
            // 설정 앱에서 권한을 바꾸고 돌아온 경우 다시 확인
            if phase == .active && authChecked && !hasAuth {
                checkAuthAndStart()
            }
        }
        .onDisappear { vm.stop() }
    }

    // MARK: - 본문
    private var content: some View {
        VStack(spacing: 12) {
            Picker("기간", selection: $vm.scope) {
                ForEach(AnalysisScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .onChange(of: vm.scope) { vm.start() }

            if vm.isAnalyzing {
                analysisProgress
                    .padding(.horizontal, 20)
            }

            if vm.groups.isEmpty {
                if vm.isAnalyzing {
                    Spacer()
                } else {
                    emptyState
                        .frame(maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        Text("추천 사진만 남기고 정리해 보세요. 사진을 탭하면 남길지 바꿀 수 있어요.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(vm.groups) { group in
                            groupCard(group)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 90)
                }
            }
        }
    }

    private var analysisProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(AppTheme.accentDark)
                Text("비슷한 사진 찾는 중…")
                    .font(AppFont.buttonSmall)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if vm.totalCount > 0 {
                    Text(verbatim: "\(vm.analyzedCount) / \(vm.totalCount)")
                        .font(AppFont.caption)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            ProgressView(value: Double(vm.analyzedCount), total: Double(max(vm.totalCount, 1)))
                .tint(AppTheme.accent)
        }
        .padding(14)
        .background(AppTheme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: vm.trashedCount > 0 ? "checkmark" : "square.on.square")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(vm.trashedCount > 0 ? Color.white : AppTheme.accent)
                .frame(width: 76, height: 76)
                .background(vm.trashedCount > 0 ? AppTheme.accent : AppTheme.accentSoft, in: Circle())

            if vm.trashedCount > 0 {
                Text("비슷한 사진을 모두 정리했어요")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("\(vm.trashedCount)장을 휴지통에 넣었어요. 휴지통을 비우면 공간이 확보돼요.")
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("비슷한 사진이 없어요")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("다른 기간을 선택해 보세요.")
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - 묶음 카드
    private func groupCard(_ group: SimilarGroup) -> some View {
        let trashCount = vm.trashCount(in: group)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let date = group.items.first?.asset.creationDate {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Text("\(group.items.count)장")
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.items) { item in
                        thumbnail(item, in: group)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { vm.skip(group) }
                } label: {
                    Text("건너뛰기")
                        .font(AppFont.buttonSmall)
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(AppTheme.surfaceMuted, in: Capsule())
                }

                Button {
                    clean(group)
                } label: {
                    Label("\(trashCount)장 휴지통으로", systemImage: "trash")
                        .font(AppFont.buttonSmall.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(trashCount > 0 ? AppTheme.danger : AppTheme.textSecondary, in: Capsule())
                        .opacity(trashCount > 0 ? 1 : 0.4)
                }
                .disabled(trashCount == 0)
                .accessibilityIdentifier("similar.clean")
            }
            .buttonStyle(PressScaleButtonStyle())
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    private func thumbnail(_ item: PhotoItem, in group: SimilarGroup) -> some View {
        let isKept = vm.isKept(item.id, in: group)
        let isBest = item.id == group.bestID

        return PhotoThumbnailView(asset: item.asset)
            .frame(width: thumbnailSize, height: thumbnailSize)
            .opacity(isKept ? 1 : 0.5)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isKept ? AppTheme.accentDark : Color.clear, lineWidth: 3)
            )
            .overlay(alignment: .topLeading) {
                if isBest {
                    Label("추천", systemImage: "star.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent, in: Capsule())
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: isKept ? "checkmark.circle.fill" : "trash.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isKept ? AppTheme.accentDark : AppTheme.danger)
                    .padding(6)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) { vm.toggleKeep(item.id, in: group) }
            }
            .onLongPressGesture { peekItem = item }
            .accessibilityElement()
            .accessibilityLabel(isBest ? Text("추천 사진") : Text("사진"))
            .accessibilityValue(isKept ? Text("남김") : Text("휴지통으로 이동 예정"))
            .accessibilityHint("탭하면 남길지 바꿉니다. 길게 누르면 크게 봅니다.")
            .accessibilityAction(named: Text("크게 보기")) { peekItem = item }
    }

    private var undoToast: some View {
        HStack(spacing: 16) {
            Text("\(vm.lastTrashedCount)장을 휴지통으로 옮겼어요")
                .font(AppFont.buttonSmall)
                .foregroundColor(.white)
            Button("실행 취소") {
                withAnimation(.easeOut(duration: 0.25)) {
                    vm.undo()
                    showUndoToast = false
                }
            }
            .font(AppFont.buttonSmall.weight(.bold))
            .foregroundStyle(AppTheme.accent)
            .accessibilityIdentifier("similar.undo")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(Capsule().fill(AppTheme.accentDark))
        .shadow(color: AppTheme.shadow, radius: 12, x: 0, y: 6)
    }

    // MARK: - 동작
    private func clean(_ group: SimilarGroup) {
        withAnimation(.easeOut(duration: 0.25)) { vm.cleanUp(group) }
        cleanFeedback += 1

        undoToastToken += 1
        let token = undoToastToken
        withAnimation(.easeOut(duration: 0.2)) { showUndoToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard token == undoToastToken else { return }
            withAnimation(.easeOut(duration: 0.2)) { showUndoToast = false }
            vm.clearUndo()
        }
    }

    private func checkAuthAndStart() {
        requestPhotoAuth { ok in
            let wasAuthorized = hasAuth
            hasAuth = ok
            authChecked = true
            if ok && !wasAuthorized { vm.start() }
        }
    }
}
