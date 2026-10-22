import SwiftUI
import Photos
import UIKit

// MARK: - 메인 리뷰 View
struct PhotoReviewView: View {
    @StateObject private var vm = PhotoReviewViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasAuth = false
    @State private var authChecked = false
    @State private var showFilterSheet = false

    @State private var showShareSheet = false
    @State private var shareImage: UIImage?

    @State private var tempYearsBack = 1
    @State private var monthPickerDate = Date()

    @State private var dragOffset: CGSize = .zero

    @State private var showLikeOverlay = false
    @State private var showDeleteOverlay = false

    // ✅ 랜덤100 끝났을 때 알럿
    @State private var showEndOfRandomAlert = false

    // 스와이프로 카드가 날아가는 중에는 다른 입력을 막아 엉뚱한 사진이 처리되지 않게 한다.
    @State private var isCommittingSwipe = false

    // 삭제 후 잠시 보여주는 "실행 취소" 토스트
    @State private var showUndoToast = false
    @State private var undoToastToken = 0

    // 햅틱 트리거
    @State private var likeFeedback = 0
    @State private var deleteFeedback = 0

    // 사진을 길게 누르는 동안 전체 화면으로 보기.
    // GestureState는 손을 떼거나 제스처가 취소되면 자동으로 false로 돌아가 화면이 남아 있지 않는다.
    @GestureState private var isPressingToPeek = false
    // VoiceOver에서는 길게 누르기가 어려워 동작(action)으로 열고 닫는다.
    @State private var isAccessibilityPeek = false
    private var isPeeking: Bool { isPressingToPeek || isAccessibilityPeek }
    // 이번 터치에서 전체 화면을 열었는지. 손을 떼는 순간 isPressingToPeek가 먼저 풀려도
    // 같은 터치의 스와이프가 사진을 넘기지 않도록 잠깐 더 기억한다.
    @State private var didPeekThisTouch = false

    private let swipeThreshold: CGFloat = 120

    private var isPastSwipeThreshold: Bool { abs(dragOffset.width) > swipeThreshold }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AppBackground()

                VStack(spacing: 12) {
                    HStack {
                        Button { showFilterSheet = true } label: {
                            AppChip(text: Text(verbatim: filterChipText), systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityHint("필터를 바꿉니다")
                        .accessibilityIdentifier("review.filter")

                        Spacer()

                        Button { loadImageForShare() } label: {
                            AppIconButtonLabel(systemImage: "square.and.arrow.up")
                        }
                        .accessibilityLabel("공유")
                        .disabled(vm.currentPhoto == nil)
                        .opacity(vm.currentPhoto == nil ? 0.5 : 1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    if !authChecked {
                        ProgressView("권한 확인 중…")
                            .tint(AppTheme.accentDark)
                            .frame(maxHeight: .infinity)
                            .onAppear { checkAuthAndLoad() }

                    } else if !hasAuth {
                        PhotoPermissionView()
                            .frame(maxHeight: .infinity)

                    } else if vm.isLoading {
                        if let scan = vm.categoryScan {
                            categoryScanProgress(scan)
                                .frame(maxHeight: .infinity)
                        } else {
                            ProgressView("사진 불러오는 중…")
                                .tint(AppTheme.accentDark)
                                .frame(maxHeight: .infinity)
                        }

                    } else if let current = vm.currentPhoto {
                        progressHeader
                            .padding(.horizontal, 24)
                            .padding(.top, 2)

                        // 다음 사진을 현재 카드 뒤에 미리 그려 둔다. 넘기는 순간 이미 불러온 카드가 앞으로 나온다.
                        // ForEach의 id로 카드가 같은 뷰로 유지되어야 이미지를 다시 불러오지 않는다.
                        ZStack {
                            ForEach(cardStack(current: current), id: \.id) { item in
                                photoCard(item, isTop: item.id == current.id,
                                          size: CGSize(width: geo.size.width * 0.9,
                                                       height: geo.size.height * 0.63))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: geo.size.height * 0.68)
                        .padding(.top, 6)

                        Spacer(minLength: 8)

                        HStack {
                            navButton("이전", systemImage: "chevron.backward") { vm.previous() }
                                .disabled(vm.currentIndex == 0)
                                .opacity(vm.currentIndex == 0 ? 0.4 : 1)

                            Spacer()

                            navButton("5장 건너뛰기", systemImage: "forward") { vm.next5() }
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 4)

                        HStack(alignment: .top, spacing: 36) {
                            actionButton(systemImage: "trash", title: "휴지통", size: 62,
                                         foreground: AppTheme.danger, background: AppTheme.surface) {
                                performDelete()
                            }
                            .accessibilityLabel("휴지통으로 이동")
                            .accessibilityIdentifier("review.delete")

                            actionButton(systemImage: "arrow.right", title: "보관", size: 76,
                                         foreground: .white, background: AppTheme.accentDark) {
                                vm.keep()
                            }
                            .accessibilityLabel("보관하고 다음 사진")
                            .accessibilityIdentifier("review.keep")

                            actionButton(systemImage: "heart.fill", title: "좋아요", size: 62,
                                         foreground: AppTheme.like, background: AppTheme.surface) {
                                performLike()
                            }
                            .accessibilityLabel("좋아요")
                            .accessibilityIdentifier("review.like")
                        }
                        .padding(.bottom, 20)

                    } else {
                        emptyState
                            .frame(maxHeight: .infinity)
                    }
                }
                .allowsHitTesting(!isCommittingSwipe)

                if showLikeOverlay {
                    overlaySystemIcon(systemName: "heart.fill", color: AppTheme.like)
                }
                if showDeleteOverlay {
                    overlaySystemIcon(systemName: "trash.fill", color: AppTheme.danger)
                }

                // 누르고 있는 손가락의 제스처는 카드가 계속 받으므로 이 화면은 터치를 받지 않는다.
                if isPeeking, let current = vm.currentPhoto {
                    FullScreenPhotoView(asset: current.asset)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .allowsHitTesting(isAccessibilityPeek)
                        .accessibilityAction(named: Text("닫기")) { isAccessibilityPeek = false }
                        .zIndex(10)
                }
            }
            .overlay(alignment: .bottom) {
                if showUndoToast && vm.canUndoDelete {
                    undoToast
                        .padding(.bottom, 150)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sensoryFeedback(.selection, trigger: isPastSwipeThreshold) { wasPast, isPast in
            !wasPast && isPast
        }
        .sensoryFeedback(.success, trigger: likeFeedback)
        .sensoryFeedback(.impact(weight: .light), trigger: isPeeking) { _, peeking in peeking }
        .onChange(of: isPressingToPeek) { _, pressing in
            if pressing {
                didPeekThisTouch = true
            } else {
                // 같은 터치의 스와이프 onEnded가 확인할 시간을 준 뒤 해제한다.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { didPeekThisTouch = false }
            }
        }
        .statusBarHidden(isPeeking)
        .sensoryFeedback(.impact(weight: .medium), trigger: deleteFeedback)
        .onChange(of: vm.shouldAskForNewRandom) {
            if vm.shouldAskForNewRandom {
                showEndOfRandomAlert = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // 설정 앱에서 권한을 바꾸고 돌아온 경우 다시 확인
            if phase == .active && authChecked && !hasAuth {
                checkAuthAndLoad()
            }
        }
        .alert("새로운 사진을 보시겠습니까?", isPresented: $showEndOfRandomAlert) {
            Button("새로 불러오기") {
                vm.shouldAskForNewRandom = false
                vm.selectRandom100()
            }
            Button("그만 보기", role: .cancel) {
                vm.shouldAskForNewRandom = false
            }
        } message: {
            Text("랜덤 100장을 모두 보셨습니다.")
        }
        .sheet(isPresented: $showFilterSheet) { filterSheet }
        .sheet(isPresented: $showShareSheet) {
            if let img = shareImage { ActivityView(activityItems: [img]) }
        }
        .toolbar(isPeeking ? .hidden : .visible, for: .navigationBar)
        .onDisappear { vm.stopCaching() }
    }

    // 뒤 카드(다음 사진) → 앞 카드(현재 사진) 순서. ZStack은 나중 것이 위에 그려진다.
    private func cardStack(current: PhotoItem) -> [PhotoItem] {
        [vm.nextPhoto, current].compactMap { $0 }
    }

    // 앞/뒤 카드가 같은 뷰 구조를 쓰게 해서, 뒤 카드가 앞으로 올 때 불러온 이미지가 유지되게 한다.
    private func photoCard(_ item: PhotoItem, isTop: Bool, size: CGSize) -> some View {
        AssetImageView(asset: item.asset)
            .frame(width: size.width, height: size.height)
            .background(AppTheme.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                if isTop { swipeHint }
            }
            .overlay(alignment: .topLeading) {
                // 이미 좋아요(즐겨찾기)한 사진 표시. 스와이프 중에는 좋아요/휴지통 힌트와 겹치지 않게 숨긴다.
                if vm.isLiked(item) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.like, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                        .padding(14)
                        .opacity(isTop && dragOffset != .zero ? 0 : 1)
                        .allowsHitTesting(false)
                        .accessibilityLabel(Text("좋아요한 사진"))
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isTop, let date = vm.currentDateString {
                    Label(date, systemImage: "calendar")
                        .font(AppFont.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.35), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(14)
                        .opacity(dragOffset == .zero ? 1 : 0)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: AppTheme.shadow, radius: isTop ? 20 : 8, x: 0, y: isTop ? 10 : 4)
            .offset(isTop ? dragOffset : CGSize(width: 0, height: 10))
            .rotationEffect(.degrees(isTop ? Double(dragOffset.width / 15) : 0))
            .scaleEffect(isTop ? (dragOffset == .zero ? 1.0 : 0.98) : 0.94)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: dragOffset)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isTop)
            .contentShape(Rectangle())
            .gesture(cardDragGesture, including: isTop ? .all : .none)
            .onTapGesture {
                if isTop { vm.keep() }
            }
            // 길게 누르면 전체 화면, 손을 떼면 돌아온다. 끌기 시작하면(12pt 이상) 스와이프로 넘어간다.
            .simultaneousGesture(peekGesture, including: isTop ? .all : .none)
            .accessibilityAction(named: Text("전체 화면으로 보기")) {
                guard isTop else { return }
                isAccessibilityPeek.toggle()
            }
            .allowsHitTesting(isTop)
            .accessibilityHidden(!isTop)
            .accessibilityLabel("사진")
            .accessibilityHint("오른쪽으로 밀면 좋아요, 왼쪽으로 밀면 휴지통, 탭하면 보관 후 다음 사진")
    }

    // 길게 누른 뒤(.second) 손을 떼기 전까지 isPressingToPeek가 true
    private var peekGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($isPressingToPeek) { value, state, transaction in
                if case .second(true, _) = value, dragOffset == .zero {
                    transaction.animation = .easeOut(duration: 0.15)
                    state = true
                }
            }
    }

    private var cardDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // 전체 화면으로 보는 중에는 손가락이 움직여도 뒤의 카드를 넘기지 않는다.
                guard !isPeeking && !didPeekThisTouch else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                if isPeeking || didPeekThisTouch {
                    dragOffset = .zero
                    return
                }
                if value.translation.width > swipeThreshold {
                    commitSwipe(toRight: true, action: performLike)
                } else if value.translation.width < -swipeThreshold {
                    commitSwipe(toRight: false, action: performDelete)
                } else {
                    withAnimation(.spring()) { dragOffset = .zero }
                }
            }
    }

    // 종류 필터: 처음에는 사진을 분류하느라 시간이 걸리므로 진행 상황을 보여준다.
    private func categoryScanProgress(_ scan: (done: Int, total: Int)) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AppTheme.accentDark)
            Text(verbatim: String(localized: "\(vm.filterType.title) 사진 찾는 중…"))
                .font(AppFont.buttonSmall)
                .foregroundStyle(AppTheme.textPrimary)
            if scan.total > 0 {
                Text("\(scan.done) / \(scan.total)장 확인")
                    .font(AppFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Text("처음 한 번만 분석하고, 다음부터는 바로 보여드려요.")
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 32)
    }

    private var filterChipText: String {
        var text = vm.filterType.title
        if vm.onlyUnseen { text = String(localized: "\(text) · 안 본 사진") }
        if vm.onlyLocal { text = String(localized: "\(text) · 기기 사진") }
        return text
    }

    // MARK: - 하위 View

    // 드래그 방향에 따라 좋아요/휴지통 표시가 점점 진해진다.
    private var swipeHint: some View {
        let progress = min(abs(dragOffset.width) / swipeThreshold, 1)
        let isLike = dragOffset.width > 0
        let color = isLike ? AppTheme.like : AppTheme.danger

        return ZStack(alignment: isLike ? Alignment.topTrailing : Alignment.topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(color.opacity(0.22 * progress))

            Label(isLike ? LocalizedStringKey("좋아요") : LocalizedStringKey("휴지통"),
                  systemImage: isLike ? "heart.fill" : "trash.fill")
                .font(AppFont.button)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(color))
                .padding(20)
                .opacity(progress)
        }
        .allowsHitTesting(false)
    }

    // 진행 상황: 얇은 진행 막대 + "n / N"
    private var progressHeader: some View {
        let total = max(vm.photos.count, 1)
        let progress = Double(vm.currentIndex + 1) / Double(total)

        return HStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(AppTheme.accent)
                .animation(.easeOut(duration: 0.2), value: progress)
            Text(verbatim: "\(vm.currentIndex+1) / \(vm.photos.count)")
                .font(AppFont.caption.monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(vm.photos.count)장 중 \(vm.currentIndex+1)번째")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 76, height: 76)
                .background(AppTheme.accentSoft, in: Circle())
            Text(vm.onlyUnseen ? LocalizedStringKey("이 필터에 아직 안 본 사진이 없어요")
                               : LocalizedStringKey("이 필터에 해당하는 사진이 없어요"))
                .font(AppFont.subtitle)
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Button("다른 필터 선택") { showFilterSheet = true }
                Button("다시 불러오기") { vm.reloadByFilter() }
            }
            .font(AppFont.buttonSmall)
            .foregroundColor(AppTheme.accentDark)
        }
        .padding(.horizontal, 24)
    }

    private var undoToast: some View {
        HStack(spacing: 16) {
            Text("휴지통으로 옮겼어요")
                .font(AppFont.buttonSmall)
                .foregroundColor(.white)
            Button("실행 취소") {
                withAnimation(.easeOut(duration: 0.2)) {
                    vm.undoDelete()
                    showUndoToast = false
                }
            }
            .font(AppFont.buttonSmall.weight(.bold))
            .accessibilityIdentifier("review.undo")
            .foregroundStyle(AppTheme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(Capsule().fill(AppTheme.accentDark))
        .shadow(color: AppTheme.shadow, radius: 12, x: 0, y: 6)
    }

    private func navButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(AppFont.buttonSmall)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
    }

    private func actionButton(systemImage: String, title: LocalizedStringKey, size: CGFloat,
                              foreground: Color, background: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(foreground)
                    .frame(width: size, height: size)
                    .background(background, in: Circle())
                    .overlay(Circle().stroke(AppTheme.border, lineWidth: background == AppTheme.surface ? 1 : 0))
                    .shadow(color: AppTheme.shadow, radius: 12, x: 0, y: 6)
                Text(title)
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    private func overlaySystemIcon(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .frame(width: 100, height: 100)
            .foregroundColor(color)
            .shadow(color: AppTheme.shadow, radius: 10, x: 0, y: 6)
            .transition(.scale.combined(with: .opacity))
            .allowsHitTesting(false)
    }

    // MARK: - 동작

    private func checkAuthAndLoad() {
        requestPhotoAuth { ok in
            let wasAuthorized = hasAuth
            hasAuth = ok
            authChecked = true
            if ok && !wasAuthorized { vm.selectRandom100() }
        }
    }

    private func commitSwipe(toRight: Bool, action: @escaping () -> Void) {
        isCommittingSwipe = true
        withAnimation(.spring()) {
            dragOffset = CGSize(width: toRight ? 1000 : -1000, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // 다음 사진이 옆에서 날아 들어오지 않도록 애니메이션 없이 제자리로
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { dragOffset = .zero }
            action()
            isCommittingSwipe = false
        }
    }

    // 오버레이는 withAnimation으로 토글해야 transition이 실제로 적용된다.
    private func flashOverlay(_ flag: Binding<Bool>) {
        withAnimation(.easeOut(duration: 0.2)) { flag.wrappedValue = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.2)) { flag.wrappedValue = false }
        }
    }

    private func performLike() {
        guard vm.currentPhoto != nil else { return }
        flashOverlay($showLikeOverlay)
        likeFeedback += 1
        vm.like()
    }

    private func performDelete() {
        guard vm.currentPhoto != nil else { return }
        flashOverlay($showDeleteOverlay)
        deleteFeedback += 1
        vm.delete()

        undoToastToken += 1
        let token = undoToastToken
        withAnimation(.easeOut(duration: 0.2)) { showUndoToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard token == undoToastToken else { return }
            withAnimation(.easeOut(duration: 0.2)) { showUndoToast = false }
        }
    }

    // MARK: - 필터 시트

    private func filterRow(_ title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            showFilterSheet = false
        } label: {
            HStack {
                Text(title)
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(AppTheme.accentDark)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    var filterSheet: some View {
        NavigationStack {
            Form {
                // 자주 쓰는 옵션이라 시트를 열자마자(절반 높이) 보이도록 맨 위에 둔다.
                Section(header: Text("리뷰 상태"),
                        footer: Text("한 번 넘긴 사진은 다시 나오지 않아요. 기록은 홈 > 설정에서 초기화할 수 있어요.")) {
                    Toggle("안 본 사진만 보기", isOn: $vm.onlyUnseen)
                        .onChange(of: vm.onlyUnseen) {
                            vm.reloadByFilter()
                        }
                }

                Section(header: Text("랜덤")) {
                    filterRow("랜덤 100장", isSelected: vm.filterType == .random100) {
                        vm.selectRandom100()
                    }
                    filterRow("랜덤 1개월 (전체 기간)", isSelected: false) {
                        vm.selectRandomMonthFromLibrary()
                    }
                }

                Section(header: Text("최근")) {
                    filterRow("최근 7일", isSelected: vm.filterType == .recentDays(7)) {
                        vm.selectRecent(days: 7)
                    }
                    filterRow("최근 30일", isSelected: vm.filterType == .recentDays(30)) {
                        vm.selectRecent(days: 30)
                    }
                }

                Section(header: Text("N년 전 오늘 (±15일)")) {
                    Picker("몇 년 전", selection: $tempYearsBack) {
                        ForEach(1..<11) { Text("\($0)년 전").tag($0) }
                    }
                    filterRow("적용", isSelected: vm.filterType == .yearsAgo(tempYearsBack)) {
                        vm.selectYearsAgo(yearsBack: tempYearsBack)
                    }
                }

                Section(header: Text("기간 선택 (1개월)")) {
                    DatePicker("시작 월 선택", selection: $monthPickerDate, displayedComponents: [.date])
                    filterRow("이 달부터 1개월 보기", isSelected: false) {
                        let cal = Calendar.current
                        var comp = cal.dateComponents([.year, .month], from: monthPickerDate)
                        comp.day = 1
                        if let firstDay = cal.date(from: comp) {
                            vm.selectMonthRange(from: firstDay)
                        }
                    }
                }

                Section(header: Text("사람 / 즐겨찾기")) {
                    filterRow("사람이 있는 사진(Portrait)", isSelected: vm.filterType == .peoplePortrait) {
                        vm.selectPeoplePortrait()
                    }
                    filterRow("즐겨찾기 안 된 사진", isSelected: vm.filterType == .nonFavorite) {
                        vm.selectNonFavorite()
                    }
                }

                Section(header: Text("유형별")) {
                    filterRow("스크린샷", isSelected: vm.filterType == .screenshot) {
                        vm.selectScreenshot()
                    }
                    filterRow("연사(버스트)", isSelected: vm.filterType == .burst) {
                        vm.selectBurst()
                    }
                }

                Section(header: Text("종류별"),
                        footer: Text("기기 안에서 사진을 분석해 최근 사진부터 최대 100장을 찾아요. 처음에는 시간이 걸리지만 결과를 저장해 다음부터는 빨라요.")) {
                    ForEach(PhotoCategory.allCases) { category in
                        filterRow(LocalizedStringKey(category.title),
                                  isSelected: vm.filterType == .category(category)) {
                            vm.selectCategory(category)
                        }
                    }
                }

                Section(header: Text("iCloud 사진"),
                        footer: Text("iCloud에서 받아야 하는 사진은 건너뛰어 기다림 없이 볼 수 있어요.")) {
                    Toggle("기기에 있는 사진만 보기", isOn: $vm.onlyLocal)
                        .onChange(of: vm.onlyLocal) {
                            vm.reloadByFilter()
                        }
                }

            }
            .appFormStyle()
            .navigationTitle("필터 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { showFilterSheet = false }
                        .accessibilityIdentifier("sheet.close")
                }
            }
        }
        .tint(AppTheme.accentDark)
        .presentationDetents([.medium, .large])
    }

    private func loadImageForShare() {
        guard let asset = vm.currentPhoto?.asset else { return }

        let opt = PHImageRequestOptions()
        opt.deliveryMode = .highQualityFormat
        opt.isNetworkAccessAllowed = true

        sharedImageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 2000, height: 2000),
            contentMode: .aspectFit,
            options: opt
        ) { img, _ in
            if let img = img {
                self.shareImage = img
                self.showShareSheet = true
            }
        }
    }
}
