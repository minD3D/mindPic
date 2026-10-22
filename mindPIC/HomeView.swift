import Photos
import SwiftUI

struct HomeView: View {
    @State private var trashCount = 0
    @State private var seenCount = 0
    @State private var totalPhotos: Int?   // 사진 접근 권한이 있을 때만 값이 있다
    @State private var freedBytes: Int64 = 0
    @State private var showSettings = false
    @State private var showInfo = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

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

                    Spacer()

                    VStack(spacing: 10) {
                        AppLogo(size: 220)

                        Text("사진을 빠르게 정리")
                            .font(AppFont.subtitle)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        statTile(title: "본 사진", count: seenCount, total: totalPhotos, systemImage: "eye")
                        statTile(title: "휴지통", count: trashCount, systemImage: "trash")
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

                        NavigationLink {
                            SimilarPhotosView()
                        } label: {
                            AppButtonLabel(
                                text: Text("비슷한 사진 정리"),
                                systemImage: "square.on.square",
                                foreground: AppTheme.textPrimary,
                                background: AppTheme.surface,
                                border: AppTheme.border,
                                shadow: false
                            )
                        }
                        .accessibilityIdentifier("home.similar")

                        NavigationLink {
                            TrashView()
                        } label: {
                            AppButtonLabel(
                                text: Text("휴지통 보기"),
                                foreground: AppTheme.textPrimary,
                                background: AppTheme.surface,
                                border: AppTheme.border,
                                shadow: false
                            )
                        }
                        .accessibilityIdentifier("home.trash")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
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

    private func statTile(title: LocalizedStringKey, count: Int, total: Int? = nil, systemImage: String) -> some View {
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
                (Text(count, format: .number)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                 + Text(verbatim: total.map { " / \($0.formatted())" } ?? "")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(AppTheme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private func refreshCounts() {
        trashCount = ReviewStateStore.trashCount()
        seenCount = ReviewStateStore.seenCount()
        freedBytes = ReviewStateStore.freedBytes()

        // 전체 사진 수와, 본 사진 중 아직 사진첩에 남아 있는 수를 센다 (지운 사진까지 세면 전체보다 커질 수 있음).
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
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
