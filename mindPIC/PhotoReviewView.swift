import SwiftUI
import Photos
import UIKit

// MARK: - 메인 리뷰 View
struct PhotoReviewView: View {
    @StateObject private var vm = PhotoReviewViewModel()
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

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AppBackground()

                VStack(spacing: 12) {
                    HStack {
                        Button { showFilterSheet = true } label: {
                            AppChip(text: "필터", systemImage: "line.3.horizontal.decrease.circle")
                        }

                        Spacer()

                        Button { loadImageForShare() } label: {
                            AppChip(text: "공유", systemImage: "square.and.arrow.up")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    if !authChecked {
                        ProgressView("권한 확인 중…")
                            .tint(AppTheme.accentDark)
                            .onAppear {
                                requestPhotoAuth { ok in
                                    hasAuth = ok
                                    authChecked = true
                                    if ok { vm.selectRandom100() }
                                }
                            }

                    } else if !hasAuth {
                        VStack(spacing: 12) {
                            Text("사진 접근 권한이 필요합니다.")
                                .font(AppFont.body)
                                .foregroundColor(AppTheme.textPrimary)
                            Button("다시 요청") {
                                requestPhotoAuth { ok in
                                    hasAuth = ok
                                    if ok { vm.selectRandom100() }
                                }
                            }
                            .font(AppFont.buttonSmall)
                            .foregroundColor(AppTheme.accentDark)
                        }

                    } else if vm.isLoading {
                        ProgressView("사진 불러오는 중…")
                            .tint(AppTheme.accentDark)

                    } else if let current = vm.currentPhoto {
                        Text("\(vm.currentIndex+1) / \(vm.photos.count)")
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

                        ZStack(alignment: .topLeading) {
                            AssetImageView(asset: current.asset)
                                .id(current.id)
                                .frame(width: geo.size.width * 0.9,
                                       height: geo.size.height * 0.65)
                                .background(AppTheme.cardStrong)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
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
                                            let threshold: CGFloat = 120
                                            if value.translation.width > threshold {
                                                commitSwipe(toRight: true, action: performLike)
                                            } else if value.translation.width < -threshold {
                                                commitSwipe(toRight: false, action: performDelete)
                                            } else {
                                                withAnimation(.spring()) { dragOffset = .zero }
                                            }
                                        }
                                )
                                .onTapGesture {
                                    vm.keep()
                                }

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
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: geo.size.height * 0.7)
                        .padding(.top, 8)

                        Spacer()

                        HStack(spacing: 20) {
                            Button("←") { vm.previous() }
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

                            Button("→") { vm.next5() }
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
                        .padding(.bottom, 6)

                        HStack(spacing: 32) {
                            Button { performDelete() } label: {
                                ZStack {
                                    Circle()
                                        .fill(AppTheme.cardStrong)
                                        .shadow(color: AppTheme.shadow, radius: 8, x: 0, y: 4)
                                        .frame(width: 64, height: 64)
                                    Image("icon_trash_3d")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36, height: 36)
                                }
                            }

                            Button { vm.keep() } label: {
                                ZStack {
                                    Circle()
                                        .fill(AppTheme.cardStrong)
                                        .shadow(color: AppTheme.shadow, radius: 8, x: 0, y: 4)
                                        .frame(width: 72, height: 72)
                                    Image("icon_next_3d")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 42, height: 42)
                                }
                            }

                            Button { performLike() } label: {
                                ZStack {
                                    Circle()
                                        .fill(AppTheme.cardStrong)
                                        .shadow(color: AppTheme.shadow, radius: 8, x: 0, y: 4)
                                        .frame(width: 64, height: 64)
                                    Image("icon_heart_3d")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36, height: 36)
                                }
                            }
                        }
                        .padding(.bottom, 28)

                    } else {
                        VStack(spacing: 10) {
                            Text("리뷰할 사진 없음")
                                .font(AppFont.subtitle)
                                .foregroundColor(AppTheme.textSecondary)
                            Button("다시 불러오기") { vm.reloadByFilter() }
                                .font(AppFont.buttonSmall)
                                .foregroundColor(AppTheme.accentDark)
                        }
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
        }
        .onChange(of: vm.shouldAskForNewRandom) {
            if vm.shouldAskForNewRandom {
                showEndOfRandomAlert = true
            }
        }
        .alert("새로운 사진을 보시겠습니까?", isPresented: $showEndOfRandomAlert) {
            Button("Yes") {
                vm.shouldAskForNewRandom = false
                vm.selectRandom100()
            }
            Button("No", role: .cancel) {
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

    private func commitSwipe(toRight: Bool, action: @escaping () -> Void) {
        isCommittingSwipe = true
        withAnimation(.spring()) {
            dragOffset = CGSize(width: toRight ? 1000 : -1000, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            dragOffset = .zero
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
        flashOverlay($showLikeOverlay)
        vm.like()
    }

    private func performDelete() {
        flashOverlay($showDeleteOverlay)
        vm.delete()
    }

    var filterSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("랜덤")) {
                    Button("랜덤 100장") {
                        vm.selectRandom100()
                        showFilterSheet = false
                    }
                    Button("랜덤 1개월 (전체 기간)") {
                        vm.selectRandomMonthFromLibrary()
                        showFilterSheet = false
                    }
                }

                Section(header: Text("최근")) {
                    Button("최근 7일") { vm.selectRecent(days: 7); showFilterSheet = false }
                    Button("최근 30일") { vm.selectRecent(days: 30); showFilterSheet = false }
                }

                Section(header: Text("N년 전 오늘 (±15일)")) {
                    Picker("몇 년 전", selection: $tempYearsBack) {
                        ForEach(1..<11) { Text("\($0)년 전").tag($0) }
                    }
                    Button("적용") {
                        vm.selectYearsAgo(yearsBack: tempYearsBack)
                        showFilterSheet = false
                    }
                }

                Section(header: Text("기간 선택 (1개월)")) {
                    DatePicker("시작 월 선택", selection: $monthPickerDate, displayedComponents: [.date])
                    Button("이 달부터 1개월 보기") {
                        let cal = Calendar.current
                        var comp = cal.dateComponents([.year, .month], from: monthPickerDate)
                        comp.day = 1
                        if let firstDay = cal.date(from: comp) {
                            vm.selectMonthRange(from: firstDay)
                        }
                        showFilterSheet = false
                    }
                }

                Section(header: Text("사람 / 즐겨찾기")) {
                    Button("사람이 있는 사진(Portrait)") { vm.selectPeoplePortrait(); showFilterSheet = false }
                    Button("즐겨찾기 안 된 사진") { vm.selectNonFavorite(); showFilterSheet = false }
                }

                Section(header: Text("유형별")) {
                    Button("스크린샷") { vm.selectScreenshot(); showFilterSheet = false }
                    Button("연사(버스트)") { vm.selectBurst(); showFilterSheet = false }
                }

                Section(header: Text("리뷰 상태")) {
                    Toggle("안 본 사진만 보기", isOn: $vm.onlyUnseen)
                        .onChange(of: vm.onlyUnseen) {
                            vm.reloadByFilter()
                        }
                }

            }
            .navigationTitle("필터 선택")
        }
        .tint(AppTheme.accentDark)
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
