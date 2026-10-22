import SwiftUI
import Photos
import UIKit

// MARK: - 메인 리뷰 View
struct PhotoReviewView: View {
    // 처음 보여줄 필터. nil이면 랜덤 100장.
    var initialFilter: PhotoFilterType? = nil

    @StateObject private var vm = PhotoReviewViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasAuth = false
    @State private var authChecked = false
    @State private var showFilterSheet = false

    @State private var showShareSheet = false
    @State private var shareImage: UIImage?

    @State private var tempYearsBack = 1
    @State private var pickerYear = Calendar.current.component(.year, from: Date())
    @State private var pickerMonth = Calendar.current.component(.month, from: Date())
    @State private var filterSheetDetent: PresentationDetent = .large

    @State private var dragOffset: CGSize = .zero

    // 좋아요/휴지통 후 하단 버튼에 잠깐 보여주는 피드백 (다음 사진 위에는 띄우지 않는다)
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
                            .padding(.top, 8)

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
                        // 실행 취소 토스트는 사진 영역 아래쪽에 띄워 이전/건너뛰기 줄과 버튼을 가리지 않는다.
                        .overlay(alignment: .bottom) {
                            undoToastIfNeeded
                                .padding(.bottom, 4)
                        }

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

                        HStack(alignment: .bottom, spacing: 36) {
                            actionButton(systemImage: "trash", title: "휴지통", size: 62,
                                         foreground: AppTheme.danger, background: AppTheme.surface,
                                         flashIcon: showDeleteOverlay ? "trash.fill" : nil) {
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
                                         foreground: AppTheme.like, background: AppTheme.surface,
                                         flashIcon: showLikeOverlay ? "heart.fill" : nil) {
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
                // 마지막 사진을 지워 카드 영역이 없어졌을 때만 화면 아래에 띄운다.
                if vm.currentPhoto == nil {
                    undoToastIfNeeded
                        .padding(.bottom, 40)
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
            if vm.totalCount < 100 {
                Text("랜덤 \(vm.totalCount)장을 모두 보셨습니다.")
            } else {
                Text("랜덤 100장을 모두 보셨습니다.")
            }
        }
        .sheet(isPresented: $showFilterSheet) { filterSheet }
        .sheet(isPresented: $showShareSheet) {
            if let img = shareImage { ActivityView(activityItems: [img]) }
        }
        .toolbar {
            ToolbarItem(placement: .principal) { filterButton }
            ToolbarItem(placement: .topBarTrailing) {
                Button { loadImageForShare() } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(AppTheme.accentDark)
                }
                .accessibilityLabel("공유")
                .disabled(vm.currentPhoto == nil)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
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
                        // 실행 취소 토스트가 같은 자리에 뜨는 동안에는 숨긴다.
                        .opacity(dragOffset == .zero && !isUndoToastVisible ? 1 : 0)
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

    // 상단 가운데 필터 버튼. 누르면 필터 시트를 연다.
    private var filterButton: some View {
        Button { showFilterSheet = true } label: {
            HStack(spacing: 4) {
                Text(verbatim: filterChipText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .font(AppFont.buttonSmall)
            .foregroundStyle(AppTheme.textPrimary)
        }
        .accessibilityHint("필터를 바꿉니다")
        .accessibilityIdentifier("review.filter")
    }

    private var filterChipText: String {
        var text = vm.filterType.title
        // 랜덤 100장인데 실제로 더 적게 불러왔으면 실제 장수를 보여준다.
        if vm.filterType == .random100 && !vm.isLoading && vm.totalCount > 0 && vm.totalCount < 100 {
            text = String(localized: "랜덤 \(vm.totalCount)장")
        }
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

        // 카드가 움직이는 반대쪽 모서리에 둬야 화면 밖으로 밀려나지 않는다.
        return ZStack(alignment: isLike ? Alignment.topLeading : Alignment.topTrailing) {
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

    // 진행 상황: 얇은 진행 막대 + "n / N". N은 처음 불러온 장수로 고정, 삭제해도 n은 늘어난다.
    private var progressHeader: some View {
        let total = max(vm.totalCount, 1)
        let position = vm.position
        let progress = Double(position) / Double(total)

        return HStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(AppTheme.accent)
                .animation(.easeOut(duration: 0.2), value: progress)
            Text(verbatim: "\(position) / \(vm.totalCount)")
                .font(AppFont.caption.monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(vm.totalCount)장 중 \(position)번째")
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

    private var isUndoToastVisible: Bool { showUndoToast && vm.canUndoDelete }

    @ViewBuilder
    private var undoToastIfNeeded: some View {
        if isUndoToastVisible {
            undoToast
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
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
                              foreground: Color, background: Color, flashIcon: String? = nil,
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
                    .scaleEffect(flashIcon == nil ? 1 : 1.12)
                    // 처리 직후 버튼 위로 작은 아이콘이 떠올랐다 사라진다.
                    .overlay(alignment: .top) {
                        if let flashIcon {
                            Image(systemName: flashIcon)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(foreground)
                                .offset(y: -28)
                                .transition(.offset(y: 12).combined(with: .opacity))
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    // 버튼 크기가 달라도 라벨 줄이 맞도록 원 영역 높이를 통일한다.
                    .frame(height: 76)
                Text(title)
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    // MARK: - 동작

    private func checkAuthAndLoad() {
        requestPhotoAuth { ok in
            let wasAuthorized = hasAuth
            hasAuth = ok
            authChecked = true
            if ok && !wasAuthorized {
                if let initialFilter { vm.select(initialFilter) } else { vm.selectRandom100() }
            }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
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

    // 위에서 고른 값으로 필터를 적용하는 행. 일반 선택 행과 달리 버튼처럼 보이게 한다.
    private func applyRow(_ title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            showFilterSheet = false
        } label: {
            HStack {
                Label(title, systemImage: "arrow.right.circle.fill")
                    .font(AppFont.buttonSmall.weight(.semibold))
                    .foregroundStyle(AppTheme.accentDark)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(AppTheme.accentDark)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("y")
        return f
    }()

    private func yearText(_ year: Int) -> String {
        guard let date = Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1)) else {
            return String(year)
        }
        return Self.yearFormatter.string(from: date)
    }

    // 최근 30년 (최신 연도부터)
    private var pickerYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array(stride(from: current, through: current - 29, by: -1))
    }

    // 년/월 선택값의 1일 0시
    private var pickerMonthStart: Date? {
        Calendar.current.date(from: DateComponents(year: pickerYear, month: pickerMonth, day: 1))
    }

    // 시트를 열 때 지금 필터에 맞춰 선택값을 채운다.
    private func syncFilterSheetSelection() {
        switch vm.filterType {
        case .yearsAgo(let years):
            tempYearsBack = years
        case .monthRange(let start) where !vm.isRandomMonth:
            let cal = Calendar.current
            pickerYear = cal.component(.year, from: start)
            pickerMonth = cal.component(.month, from: start)
        default:
            break
        }
    }

    private var isRandomMonthSelected: Bool {
        if case .monthRange = vm.filterType { return vm.isRandomMonth }
        return false
    }

    private var isPickedMonthSelected: Bool {
        guard !vm.isRandomMonth, let start = pickerMonthStart else { return false }
        return vm.filterType == .monthRange(start)
    }

    var filterSheet: some View {
        NavigationStack {
            Form {
                // 자주 쓰는 옵션이라 시트를 열자마자 보이도록 맨 위에 둔다.
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
                    filterRow("랜덤 1개월 (전체 기간)", isSelected: isRandomMonthSelected) {
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

                Section(header: Text("촬영 방식")) {
                    filterRow("스크린샷", isSelected: vm.filterType == .screenshot) {
                        vm.selectScreenshot()
                    }
                    filterRow("연사(버스트)", isSelected: vm.filterType == .burst) {
                        vm.selectBurst()
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

                Section(header: Text("N년 전 오늘 (±15일)")) {
                    Picker("몇 년 전", selection: $tempYearsBack) {
                        ForEach(1..<11) { Text("\($0)년 전").tag($0) }
                    }
                    applyRow("적용", isSelected: vm.filterType == .yearsAgo(tempYearsBack)) {
                        vm.selectYearsAgo(yearsBack: tempYearsBack)
                    }
                }

                Section(header: Text("기간 선택 (1개월)")) {
                    Picker("연도", selection: $pickerYear) {
                        ForEach(pickerYears, id: \.self) { Text(verbatim: yearText($0)).tag($0) }
                    }
                    Picker("월", selection: $pickerMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(verbatim: Calendar.current.standaloneMonthSymbols[month - 1]).tag(month)
                        }
                    }
                    applyRow("이 달부터 1개월 보기", isSelected: isPickedMonthSelected) {
                        if let start = pickerMonthStart {
                            vm.selectMonthRange(from: start)
                        }
                    }
                }

                Section(header: Text("내용 (기기 분석)"),
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
        .onAppear {
            filterSheetDetent = .large
            syncFilterSheetSelection()
        }
        // 섹션이 많아 처음부터 크게 연다. 끌어내려 절반 높이로 줄일 수 있다.
        .presentationDetents([.medium, .large], selection: $filterSheetDetent)
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
