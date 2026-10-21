import SwiftUI

struct HomeView: View {
    @State private var trashCount = 0
    @State private var showSettings = false
    @State private var showInfo = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 22) {
                    Spacer().frame(height: 24)

                    VStack(spacing: 6) {
                        Text("mind PIC")
                            .font(AppFont.title)
                            .foregroundColor(AppTheme.textPrimary)

                        Text("사진을 빠르게 정리")
                            .font(AppFont.subtitle)
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    Spacer().frame(height: 18)

                    VStack(spacing: 12) {
                        NavigationLink {
                            PhotoReviewView()
                        } label: {
                            AppButtonLabel(
                                text: "사진 탐색 시작",
                                foreground: .white,
                                background: AppTheme.accentDark,
                                border: nil,
                                shadow: true
                            )
                        }

                        NavigationLink {
                            TrashView()
                        } label: {
                            AppButtonLabel(
                                text: trashCount > 0 ? "휴지통 보기 (\(trashCount))" : "휴지통 보기",
                                foreground: AppTheme.textPrimary,
                                background: AppTheme.cardStrong,
                                border: AppTheme.border,
                                shadow: false
                            )
                        }
                    }

                    Spacer()

                    HStack {
                        Button {
                            showSettings = true
                        } label: {
                            Label("설정", systemImage: "gear")
                        }

                        Spacer()

                        Button {
                            showInfo = true
                        } label: {
                            Label("사용법", systemImage: "info.circle")
                        }
                    }
                    .font(AppFont.buttonSmall)
                    .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .onAppear { refreshTrashCount() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshTrashCount()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsSheet() }
            .sheet(isPresented: $showInfo) { InfoSheet() }
        }
    }

    private func refreshTrashCount() {
        trashCount = ReviewStateStore.trashCount()
    }
}
