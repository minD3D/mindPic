import SwiftUI

struct HomeView: View {
    @State private var trashCount = 0
    @State private var seenCount = 0
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
                        statTile(title: "본 사진", count: seenCount, systemImage: "eye")
                        statTile(title: "휴지통", count: trashCount, systemImage: "trash")
                    }
                    .padding(.bottom, 16)

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

    private func statTile(title: LocalizedStringKey, count: Int, systemImage: String) -> some View {
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
                Text("\(count)장")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
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
    }
}
