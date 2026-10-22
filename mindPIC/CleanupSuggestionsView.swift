import Photos
import SwiftUI

// MARK: - 정리 추천
// 흐리거나 어둡거나 기록용으로 찍은 사진처럼 지울 만한 사진을 골라 보여준다.
struct CleanupSuggestionsView: View {
    @StateObject private var vm = CleanupSuggestionsViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasAuth = false
    @State private var authChecked = false

    // 길게 눌러 크게 보기
    @State private var peekItem: PhotoItem?

    @State private var showUndoToast = false
    @State private var undoToastToken = 0
    @State private var trashFeedback = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

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
        .safeAreaInset(edge: .bottom) {
            if hasAuth && !vm.visibleSuggestions.isEmpty {
                trashButton
            }
        }
        .overlay(alignment: .bottom) {
            if showUndoToast && vm.canUndo {
                undoToast
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("정리 추천")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .fullScreenCover(item: $peekItem) { item in
            FullScreenPhotoView(asset: item.asset)
                .ignoresSafeArea()
                .onTapGesture { peekItem = nil }
                .accessibilityAction(named: Text("닫기")) { peekItem = nil }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: trashFeedback)
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

            if vm.suggestions.isEmpty {
                if vm.isAnalyzing {
                    Spacer()
                } else {
                    emptyState
                        .frame(maxHeight: .infinity)
                }
            } else {
                reasonChips

                ScrollView {
                    HStack {
                        Text("탭해서 남길 사진을 빼고, 길게 누르면 크게 볼 수 있어요.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer(minLength: 8)
                        Button(vm.allVisibleSelected ? LocalizedStringKey("모두 해제") : LocalizedStringKey("모두 선택")) {
                            vm.setAllVisible(selected: !vm.allVisibleSelected)
                        }
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accentDark)
                    }
                    .padding(.horizontal, 16)

                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(vm.visibleSuggestions) { suggestion in
                            tile(suggestion)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
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
                Text("정리할 사진 찾는 중…")
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

    private var reasonChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                reasonChip(title: Text("전체"), systemImage: "square.grid.2x2",
                           count: vm.suggestions.count, isSelected: vm.reasonFilter == nil) {
                    vm.reasonFilter = nil
                }
                ForEach(vm.availableReasons) { reason in
                    reasonChip(title: Text(reason.title), systemImage: reason.systemImage,
                               count: vm.count(for: reason), isSelected: vm.reasonFilter == reason) {
                        vm.reasonFilter = reason
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func reasonChip(title: Text, systemImage: String, count: Int, isSelected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                title
                Text(count, format: .number)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : AppTheme.textSecondary)
            }
            .font(AppFont.buttonSmall)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : AppTheme.textPrimary)
            .background(isSelected ? AppTheme.accentDark : AppTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(AppTheme.border, lineWidth: isSelected ? 0 : 1))
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: vm.trashedCount > 0 ? "checkmark" : "sparkles")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(vm.trashedCount > 0 ? Color.white : AppTheme.accent)
                .frame(width: 76, height: 76)
                .background(vm.trashedCount > 0 ? AppTheme.accent : AppTheme.accentSoft, in: Circle())

            if vm.trashedCount > 0 {
                Text("추천 사진을 모두 정리했어요")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("\(vm.trashedCount)장을 휴지통에 넣었어요. 휴지통을 비우면 공간이 확보돼요.")
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("정리할 만한 사진이 없어요")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("다른 기간을 선택해 보세요.")
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - 사진 칸
    private func tile(_ suggestion: CleanupSuggestion) -> some View {
        let isSelected = vm.isSelected(suggestion.id)
        let reason = suggestion.reasons.first

        return PhotoThumbnailView(asset: suggestion.item.asset)
            .opacity(isSelected ? 1 : 0.5)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? AppTheme.danger : Color.clear, lineWidth: 3)
            )
            .overlay(alignment: .bottomLeading) {
                if let reason {
                    Label(reason.title, systemImage: reason.systemImage)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "trash.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? AppTheme.danger : Color.black.opacity(0.25))
                    .padding(5)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) { vm.toggle(suggestion.id) }
            }
            .onLongPressGesture { peekItem = suggestion.item }
            .accessibilityElement()
            .accessibilityLabel(reason.map { Text($0.title) } ?? Text("사진"))
            .accessibilityValue(isSelected ? Text("휴지통으로 이동 예정") : Text("남김"))
            .accessibilityHint("탭하면 휴지통에 넣을지 바꿉니다. 길게 누르면 크게 봅니다.")
            .accessibilityAction(named: Text("크게 보기")) { peekItem = suggestion.item }
    }

    // MARK: - 하단 버튼 / 토스트
    private var trashButton: some View {
        let count = vm.selectedVisibleCount
        return Button {
            trashSelected()
        } label: {
            AppButtonLabel(
                text: Text("\(count)장 휴지통으로"),
                systemImage: "trash",
                foreground: count > 0 ? .white : AppTheme.textSecondary,
                background: count > 0 ? AppTheme.danger : AppTheme.cardStrong,
                border: count > 0 ? nil : AppTheme.border,
                shadow: count > 0
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .disabled(count == 0)
        .accessibilityIdentifier("suggestions.trash")
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
            .accessibilityIdentifier("suggestions.undo")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(Capsule().fill(AppTheme.accentDark))
        .shadow(color: AppTheme.shadow, radius: 12, x: 0, y: 6)
    }

    // MARK: - 동작
    private func trashSelected() {
        withAnimation(.easeOut(duration: 0.25)) { vm.trashSelected() }
        trashFeedback += 1

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
