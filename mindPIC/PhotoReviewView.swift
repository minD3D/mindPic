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

                        Spacer()

                        Button { loadImageForShare() } label: {
                            AppChip(text: Text("공유"), systemImage: "square.and.arrow.up")
                        }
                        .disabled(vm.currentPhoto == nil)
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
                        ProgressView("사진 불러오는 중…")
                            .tint(AppTheme.accentDark)
                            .frame(maxHeight: .infinity)

                    } else if let current = vm.currentPhoto {
                        Text(verbatim: "\(vm.currentIndex+1) / \(vm.photos.count)")
                            .font(AppFont.buttonSmall)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.card)
                            .foregroundColor(AppTheme.textSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            )
                            .cornerRadius(10)
                            .padding(.top, 4)
                            .accessibilityLabel("\(vm.photos.count)장 중 \(vm.currentIndex+1)번째")

                        ZStack(alignment: .topLeading) {
                            AssetImageView(asset: current.asset)
                                .id(current.id)
                                .frame(width: geo.size.width * 0.9,
                                       height: geo.size.height * 0.65)
                                .background(AppTheme.cardStrong)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                                .overlay { swipeHint }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(AppTheme.border, lineWidth: 1)
                                )
                                .shadow(color: AppTheme.shadow, radius: 12, x: 0, y: 6)
                                .offset(dragOffset)
                                .rotationEffect(.degrees(Double(dragOffset.width / 15)))
                                .scaleEffect(dragOffset == .zero ? 1.0 : 0.98)
                                .animation(.spring(response: 0.25, dampingFraction: 0.8),
                                           value: dragOffset)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            dragOffset = value.translation
                                        }
                                        .onEnded { value in
                                            if value.translation.width > swipeThreshold {
                                                commitSwipe(toRight: true, action: performLike)
                                            } else if value.translation.width < -swipeThreshold {
                                                commitSwipe(toRight: false, action: performDelete)
                                            } else {
                                                withAnimation(.spring()) { dragOffset = .zero }
                                            }
                                        }
                                )
                                .onTapGesture {
                                    vm.keep()
                                }
                                .accessibilityLabel("사진")
                                .accessibilityHint("오른쪽으로 밀면 좋아요, 왼쪽으로 밀면 휴지통, 탭하면 보관 후 다음 사진")

                            if let date = vm.currentDateString {
                                Text(date)
                                    .font(AppFont.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(AppTheme.cardStrong)
                                    .foregroundColor(AppTheme.textPrimary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(AppTheme.border, lineWidth: 1)
                                    )
                                    .cornerRadius(10)
                                    .padding(.top, 16)
                                    .padding(.leading, 32)
                                    .opacity(dragOffset == .zero ? 1 : 0)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: geo.size.height * 0.7)
                        .padding(.top, 8)

                        Spacer()

                        HStack(spacing: 20) {
                            navButton("이전", systemImage: "chevron.backward") { vm.previous() }
                                .disabled(vm.currentIndex == 0)
                                .opacity(vm.currentIndex == 0 ? 0.5 : 1)

                            navButton("5장 건너뛰기", systemImage: "forward.fill") { vm.next5() }
                        }
                        .padding(.bottom, 6)

                        HStack(spacing: 32) {
                            actionButton(image: "icon_trash_3d", title: "휴지통", size: 64) {
                                performDelete()
                            }
                            .accessibilityLabel("휴지통으로 이동")

                            actionButton(image: "icon_next_3d", title: "보관", size: 72) {
                                vm.keep()
                            }
                            .accessibilityLabel("보관하고 다음 사진")

                            actionButton(image: "icon_heart_3d", title: "좋아요", size: 64) {
                                performLike()
                            }
                            .accessibilityLabel("좋아요")
                        }
                        .padding(.bottom, 20)

                    } else {
                        emptyState
                            .frame(maxHeight: .infinity)
                    }
                }
                .allowsHitTesting(!isCommittingSwipe)

                if showLikeOverlay {
                    overlaySystemIcon(systemName: "heart.fill", color: AppTheme.accentDark)
                }
                if showDeleteOverlay {
                    overlaySystemIcon(systemName: "trash.fill", color: AppTheme.danger)
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
        .toolbar(.visible, for: .navigationBar)
        .onDisappear { vm.stopCaching() }
    }

    private var filterChipText: String {
        vm.onlyUnseen ? String(localized: "\(vm.filterType.title) · 안 본 사진") : vm.filterType.title
    }

    // MARK: - 하위 View

    // 드래그 방향에 따라 좋아요/휴지통 표시가 점점 진해진다.
    private var swipeHint: some View {
        let progress = min(abs(dragOffset.width) / swipeThreshold, 1)
        let isLike = dragOffset.width > 0
        let color = isLike ? AppTheme.accentDark : AppTheme.danger

        return ZStack(alignment: isLike ? .topTrailing : .topLeading) {
            RoundedRectangle(cornerRadius: 24)
                .fill(color.opacity(0.18 * progress))

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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundColor(AppTheme.textSecondary)
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
            .foregroundColor(AppTheme.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Capsule().fill(AppTheme.textPrimary.opacity(0.92)))
        .shadow(color: AppTheme.shadow, radius: 8, x: 0, y: 4)
    }

    private func navButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(AppFont.buttonSmall)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.cardStrong)
                .foregroundColor(AppTheme.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
                .cornerRadius(14)
        }
    }

    private func actionButton(image: String, title: LocalizedStringKey, size: CGFloat,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(AppTheme.cardStrong)
                        .shadow(color: AppTheme.shadow, radius: 8, x: 0, y: 4)
                        .frame(width: size, height: size)
                    Image(image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.57, height: size * 0.57)
                }
                Text(title)
                    .font(AppFont.caption)
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    var filterSheet: some View {
        NavigationStack {
            Form {
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

                Section(header: Text("리뷰 상태"),
                        footer: Text("한 번 넘긴 사진은 다시 나오지 않아요. 기록은 홈 > 설정에서 초기화할 수 있어요.")) {
                    Toggle("안 본 사진만 보기", isOn: $vm.onlyUnseen)
                        .onChange(of: vm.onlyUnseen) {
                            vm.reloadByFilter()
                        }
                }

            }
            .navigationTitle("필터 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { showFilterSheet = false }
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
