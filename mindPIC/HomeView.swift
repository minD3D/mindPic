import Photos
import SwiftUI

struct HomeView: View {
    @State private var trashCount = 0
    @State private var seenCount = 0
    @State private var totalPhotos: Int?   // 사진 접근 권한이 있을 때만 값이 있다
    @State private var freedBytes: Int64 = 0
    @State private var showSettings = false
    @State private var showInfo = false
    @State private var authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                // 작은 화면(iPhone SE)이나 큰 글씨에서도 버튼이 잘리지 않게 스크롤을 허용한다.
                GeometryReader { geo in
                    ScrollView {
                        content(compact: geo.size.height < 700)
                            .frame(minHeight: geo.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .onAppear { refreshCounts() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshCounts()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings, onDismiss: refreshCounts) { SettingsSheet() }
            .sheet(isPresented: $showInfo) { InfoSheet() }
        }
    }

    private var hasPhotoAccess: Bool { authStatus == .authorized || authStatus == .limited }

    private func content(compact: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer()

                Button {
                    showSettings = true
                } label: {
                    AppIconButtonLabel(systemImage: "gearshape")
                }
                .accessibilityLabel("설정")
                .accessibilityIdentifier("home.settings")

                Button {
                    showInfo = true
                } label: {
                    AppIconButtonLabel(systemImage: "questionmark")
                }
                .accessibilityLabel("사용법")
                .accessibilityIdentifier("home.info")
            }
            .padding(.top, 8)

            Spacer(minLength: 12)

            // 로고는 배경과 같은 색이라 크게 둘 필요가 없다. 아래 내용에 자리를 준다.
            VStack(spacing: 6) {
                AppLogo(size: compact ? 110 : 140)

                Text("사진을 빠르게 정리")
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 16)

            if authStatus == .notDetermined {
                permissionCard
                    .padding(.bottom, 12)
            } else if !hasPhotoAccess {
                deniedNotice
                    .padding(.bottom, 12)
            }

            HStack(spacing: 12) {
                statTile(title: "본 사진",
                         count: hasPhotoAccess ? seenCount : nil,
                         total: totalPhotos,
                         systemImage: "eye")

                NavigationLink {
                    TrashView()
                } label: {
                    statTile(title: "휴지통", count: trashCount, systemImage: "trash", showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("휴지통을 열어 사진을 복원하거나 비웁니다")
                .accessibilityIdentifier("home.trash")
            }
            .padding(.bottom, freedBytes > 0 ? 10 : 16)

            if freedBytes > 0 {
                Label("지금까지 \(PhotoSize.formatted(freedBytes)) 확보했어요", systemImage: "internaldrive")
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.bottom, 14)
            }

            VStack(spacing: 10) {
                NavigationLink {
                    PhotoReviewView()
                } label: {
                    AppButtonLabel(
                        text: Text("사진 탐색 시작"),
                        systemImage: "rectangle.stack",
                        foreground: .white,
                        background: AppTheme.accentDark,
                        border: nil,
                        shadow: true
                    )
                }
                .accessibilityIdentifier("home.start")

                // 기기 안에서 분석해 정리할 사진을 골라 주는 기능들
                HStack(spacing: 10) {
                    NavigationLink {
                        SimilarPhotosView()
                    } label: {
                        AppButtonLabel(
                            text: Text("비슷한 사진"),
                            systemImage: "square.on.square",
                            foreground: AppTheme.textPrimary,
                            background: AppTheme.surface,
                            border: AppTheme.border,
                            shadow: false
                        )
                    }
                    .accessibilityIdentifier("home.similar")

                    NavigationLink {
                        CleanupSuggestionsView()
                    } label: {
                        AppButtonLabel(
                            text: Text("정리 추천"),
                            systemImage: "sparkles",
                            foreground: AppTheme.textPrimary,
                            background: AppTheme.surface,
                            border: AppTheme.border,
                            shadow: false
                        )
                    }
                    .accessibilityIdentifier("home.suggestions")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    // 아직 권한을 묻지 않았을 때: 시스템 팝업 전에 왜 필요한지 먼저 알려 준다.
    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.accentSoft, in: Circle())
                    .accessibilityHidden(true)
                Text("사진 접근을 허용해 주세요")
                    .font(AppFont.body.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            Text("사진을 넘겨 보며 정리하려면 사진 보관함에 접근해야 해요. 사진은 기기 안에서만 분석하고, 직접 휴지통을 비우기 전에는 지우지 않아요.")
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                requestPhotoAuth { _ in refreshCounts() }
            } label: {
                AppButtonLabel(
                    text: Text("사진 접근 허용"),
                    foreground: .white,
                    background: AppTheme.accentDark,
                    border: nil,
                    shadow: false
                )
            }
            .accessibilityIdentifier("home.allowPhotos")
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    // 거부된 경우 iOS가 다시 묻지 않으므로 설정 앱으로 안내한다.
    private var deniedNotice: some View {
        Button { openAppSettings() } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                Text("사진 접근이 꺼져 있어요")
                Spacer(minLength: 4)
                Text("설정 열기")
                    .fontWeight(.semibold)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .font(AppFont.buttonSmall)
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppTheme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.openSettings")
    }

    // count가 nil이면 권한이 없어 셀 수 없다는 뜻으로 '—'를 보여 준다.
    private func statTile(title: LocalizedStringKey, count: Int?, total: Int? = nil,
                          systemImage: String, showsChevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 36, height: 36)
                .background(AppTheme.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                // 전체 수는 작고 흐리게 붙여, 숫자가 커져도 카드에 들어가게 한다.
                Group {
                    if let count {
                        Text(count, format: .number)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        + Text(verbatim: total.map { " / \($0.formatted())" } ?? "")
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        Text(verbatim: "—")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .accessibilityLabel(Text("사진 접근을 허용하면 표시됩니다"))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            }
            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(AppTheme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func refreshCounts() {
        trashCount = ReviewStateStore.trashCount()
        seenCount = ReviewStateStore.seenCount()
        freedBytes = ReviewStateStore.freedBytes()

        // 전체 사진 수와, 본 사진 중 아직 사진첩에 남아 있는 수를 센다 (지운 사진까지 세면 전체보다 커질 수 있음).
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authStatus = status
        guard status == .authorized || status == .limited else {
            totalPhotos = nil
            return
        }
        let seenIDs = Array(ReviewStateStore().seenIDs)
        Task {
            let (seen, total) = await Task.detached(priority: .utility) {
                let total = PHAsset.fetchAssets(with: .image, options: nil).count
                let seen = seenIDs.isEmpty ? 0
                    : PHAsset.fetchAssets(withLocalIdentifiers: seenIDs, options: nil).count
                return (seen, total)
            }.value
            seenCount = seen
            totalPhotos = total
        }
    }
}
