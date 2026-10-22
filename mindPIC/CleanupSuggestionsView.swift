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
    @State private var showFilterSheet = false
    @State private var confirmTrash = false

    // 지금 목록을 사진 탐색 화면으로 넘길 때
    @State private var exploreFilter: ExploreDestination?
    @State private var isExploring = false

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
                VStack(spacing: 10) {
                    exploreButton
                    trashButton
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
        .overlay(alignment: .bottom) {
            if showUndoToast && vm.canUndo {
                undoToast
                    .padding(.bottom, 156)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("정리 추천")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if hasAuth {
                ToolbarItem(placement: .topBarTrailing) { filterButton }
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            CleanupFilterSheet(filter: $vm.filter)
                .presentationDetents([.medium, .large])
        }
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
        .navigationDestination(item: $exploreFilter) { destination in
            PhotoReviewView(initialFilter: destination.filter)
        }
        .onAppear {
            // 사진 탐색에서 돌아온 경우
            guard isExploring else { return }
            isExploring = false
            withAnimation(.easeOut(duration: 0.2)) { vm.refreshFromStore() }
        }
        .onDisappear {
            // 사진 탐색으로 넘어갈 때는 분석을 계속한다.
            if !isExploring { vm.stop() }
        }
    }

    // MARK: - 본문
    private var content: some View {
        VStack(spacing: 12) {
            Picker("기간", selection: $vm.period) {
                ForEach(CleanupPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .onChange(of: vm.period) { vm.start() }

            if vm.period == .custom {
                customRangeRow
                    .padding(.horizontal, 20)
            }

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
            } else if vm.filteredSuggestions.isEmpty {
                filteredEmptyState
                    .frame(maxHeight: .infinity)
            } else {
                reasonChips

                ScrollView {
                    HStack {
                        Text("탭해서 지울 사진을 고르고, 길게 누르면 크게 볼 수 있어요.")
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
                           count: vm.filteredSuggestions.count, isSelected: vm.reasonFilter == nil) {
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

    // 지금 보이는 목록만 사진 탐색 화면에서 한 장씩 넘겨 보기
    private var exploreButton: some View {
        Button {
            isExploring = true
            exploreFilter = ExploreDestination(filter: vm.exploreFilter)
        } label: {
            AppButtonLabel(
                text: Text("\(vm.visibleSuggestions.count)장 탐색 시작하기"),
                systemImage: "rectangle.stack",
                foreground: AppTheme.textPrimary,
                background: AppTheme.cardStrong,
                border: AppTheme.border,
                shadow: false
            )
        }
        .accessibilityHint("지금 목록의 사진만 한 장씩 넘겨 보며 남기거나 지웁니다.")
        .accessibilityIdentifier("suggestions.explore")
    }

    // '직접 선택' 기간의 시작·끝 날짜
    private var customRangeRow: some View {
        HStack(spacing: 8) {
            DatePicker("시작", selection: $vm.customStart, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
            Text(verbatim: "~")
                .foregroundStyle(AppTheme.textSecondary)
            DatePicker("끝", selection: $vm.customEnd, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
            Spacer(minLength: 0)
        }
        .onChange(of: vm.customStart) { vm.start() }
        .onChange(of: vm.customEnd) { vm.start() }
    }

    private var filterButton: some View {
        let active = vm.filter.activeCount > 0 || vm.filter.sort != .newest
        return Button {
            showFilterSheet = true
        } label: {
            Image(systemName: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .foregroundStyle(AppTheme.accentDark)
        }
        .accessibilityLabel("필터")
        .accessibilityValue(active ? Text("켜짐") : Text("꺼짐"))
        .accessibilityIdentifier("suggestions.filter")
    }

    // 추천 사진은 있지만 필터 조건에 맞는 사진이 없을 때
    private var filteredEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 76, height: 76)
                .background(AppTheme.accentSoft, in: Circle())
            Text("조건에 맞는 사진이 없어요")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Button("필터 초기화") {
                withAnimation(.easeOut(duration: 0.2)) { vm.filter = CleanupFilter(sort: vm.filter.sort) }
            }
            .font(AppFont.buttonSmall.weight(.semibold))
            .foregroundStyle(AppTheme.accentDark)
        }
        .padding(.horizontal, 32)
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
                Group {
                    if vm.analyzedCount > 0 {
                        Text("사진 \(vm.analyzedCount)장을 확인했어요.")
                    } else {
                        Text("이 기간에는 사진이 없어요.")
                    }
                }
                .font(AppFont.subtitle)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)

                // 다음 행동: 더 넓은 기간에서 다시 찾기
                if let wider = vm.widerPeriod {
                    Button {
                        vm.period = wider
                    } label: {
                        Label("더 넓은 기간에서 찾기", systemImage: "calendar.badge.plus")
                    }
                    .font(AppFont.buttonSmall.weight(.semibold))
                    .foregroundStyle(AppTheme.accentDark)
                    .padding(.top, 4)
                    .accessibilityIdentifier("suggestions.widerPeriod")
                }
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - 사진 칸
    private func tile(_ suggestion: CleanupSuggestion) -> some View {
        let isSelected = vm.isSelected(suggestion.id)
        let reason = suggestion.reasons.first

        return PhotoThumbnailView(asset: suggestion.item.asset)
            // 삭제 예정: 반투명 + 빨간 테두리 + 휴지통 배지 / 남김: 원본 그대로
            .opacity(isSelected ? 0.5 : 1)
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
            .overlay(alignment: .topLeading) {
                // 용량순으로 볼 때는 얼마나 큰지 함께 보여준다
                if vm.filter.sort == .largest && suggestion.bytes > 0 {
                    Text(verbatim: PhotoSize.formatted(suggestion.bytes))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                // 비슷한 사진과 같은 배지: 남김 = 체크, 삭제 예정 = 휴지통
                Image(systemName: isSelected ? "trash.circle.fill" : "checkmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? AppTheme.danger : AppTheme.accentDark)
                    // 밝은 사진에서도 남김 배지가 보이도록
                    .shadow(color: .black.opacity(isSelected ? 0 : 0.6), radius: 2)
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
        let bytes = vm.selectedVisibleBytes
        let text = count == 0
            ? Text("지울 사진을 골라 주세요")
            : bytes > 0
                ? Text("\(count)장 휴지통으로") + Text(verbatim: " · \(PhotoSize.formatted(bytes))")
                : Text("\(count)장 휴지통으로")
        return Button {
            confirmTrash = true
        } label: {
            AppButtonLabel(
                text: text,
                systemImage: "trash",
                foreground: count > 0 ? .white : AppTheme.textSecondary,
                background: count > 0 ? AppTheme.danger : AppTheme.cardStrong,
                border: count > 0 ? nil : AppTheme.border,
                shadow: count > 0
            )
        }
        .disabled(count == 0)
        .accessibilityIdentifier("suggestions.trash")
        .confirmationDialog(
            "\(count)장을 휴지통으로 옮길까요?",
            isPresented: $confirmTrash,
            titleVisibility: .visible
        ) {
            Button("휴지통으로 옮기기", role: .destructive) { trashSelected() }
        } message: {
            Text("앱 휴지통을 비우기 전까지는 되돌릴 수 있어요.")
        }
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

// 사진 탐색 화면으로 넘길 목록 (navigationDestination용)
private struct ExploreDestination: Hashable, Identifiable {
    let id = UUID()
    let filter: PhotoFilterType

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
