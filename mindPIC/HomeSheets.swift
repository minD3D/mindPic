import SwiftUI

// MARK: - 설정
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var seenCount = 0
    @State private var showResetAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("리뷰 기록"),
                        footer: Text("'안 본 사진만 보기' 필터는 이 기록을 기준으로 동작해요.")) {
                    HStack {
                        Text("본 사진")
                        Spacer()
                        Text("\(seenCount)장")
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    Button("본 사진 기록 초기화", role: .destructive) {
                        showResetAlert = true
                    }
                    .disabled(seenCount == 0)
                }

                Section(header: Text("권한")) {
                    Button("사진 접근 권한 변경") { openAppSettings() }
                }
            }
            .appFormStyle()
            .task { seenCount = await ReviewStateStore.existingSeenCount() }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                        .accessibilityIdentifier("sheet.close")
                }
            }
            .alert("본 사진 기록을 초기화할까요?", isPresented: $showResetAlert) {
                Button("초기화", role: .destructive) {
                    ReviewStateStore().resetSeen()
                    seenCount = 0
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("사진은 삭제되지 않으며, 모든 사진이 다시 '안 본 사진'으로 표시됩니다.")
            }
        }
        .tint(AppTheme.accentDark)
    }
}

// MARK: - 사용법 / 정보
struct InfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("사용법")) {
                    guideRow("hand.point.right", "오른쪽으로 밀기", "좋아요 (사진 앱 즐겨찾기에 추가)")
                    guideRow("hand.point.left", "왼쪽으로 밀기", "휴지통으로 이동 (바로 지워지지 않아요)")
                    guideRow("hand.tap", "탭 / 가운데 버튼", "보관하고 다음 사진으로")
                    guideRow("hand.point.up.left", "길게 누르기", "사진 전체를 화면 가득 보기 (손을 떼면 돌아와요)")
                    guideRow("arrow.uturn.backward", "실행 취소", "휴지통에 넣은 직후 토스트에서 되돌리기")
                }

                Section(header: Text("휴지통"),
                        footer: Text("휴지통을 비우면 사진 앱의 '최근 삭제된 항목'으로 이동하고, 30일 후 영구 삭제됩니다.")) {
                    guideRow("trash", "휴지통 비우기", "모아둔 사진을 한 번에 삭제")
                }

                Section {
                    HStack {
                        Text("버전")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
            }
            .appFormStyle()
            .navigationTitle("사용법")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                        .accessibilityIdentifier("sheet.close")
                }
            }
        }
        .tint(AppTheme.accentDark)
    }

    private func guideRow(_ systemImage: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)
                .background(AppTheme.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.body.weight(.semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(detail)
                    .font(AppFont.caption)
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}
