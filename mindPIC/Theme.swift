import SwiftUI

// MARK: - Clean Sand 테마
// 따뜻한 샌드 배경 위에 흰 카드와 짙은 에스프레소 버튼만 쓰는 깔끔한 톤.
enum AppTheme {
    // 로고 이미지(SplashIcon/AppIcon)의 배경색과 같은 샌드색. 로고가 배경에 자연스럽게 녹아들도록 맞춘다.
    static let background = Color(hex: 0xF2ECE0)
    static let surface = Color.white
    static let surfaceMuted = Color(hex: 0xEFE6DA)
    static let card = Color.white.opacity(0.85)
    static let cardStrong = Color.white
    static let accent = Color(hex: 0xC69C72)        // 샌드 캐러멜
    static let accentSoft = Color(hex: 0xF3E8DA)
    static let accentDark = Color(hex: 0x2F2925)    // 에스프레소 (주요 버튼)
    static let textPrimary = Color(hex: 0x2F2925)
    static let textSecondary = Color(hex: 0x8C7D70)
    static let border = Color(hex: 0x2F2925).opacity(0.08)
    static let shadow = Color(hex: 0x6B4E2E).opacity(0.10)
    static let like = Color(hex: 0xB98A5E)
    static let likeSoft = Color(hex: 0xF3E8DA)
    static let danger = Color(hex: 0xC4614E)
    static let dangerSoft = Color(hex: 0xF7E3DD)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// 시스템 글꼴을 써서 한글/영문 모두 고르게 보이고, Dynamic Type에 맞춰 커진다.
enum AppFont {
    static let title = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let subtitle = Font.system(.callout)
    static let button = Font.system(.headline)
    static let buttonSmall = Font.system(.subheadline).weight(.medium)
    static let body = Font.system(.body)
    static let caption = Font.system(.caption).weight(.medium)
}

struct AppBackground: View {
    var body: some View {
        AppTheme.background
            .ignoresSafeArea()
    }
}

struct AppButtonLabel: View {
    let text: Text
    var systemImage: String? = nil
    let foreground: Color
    let background: Color
    let border: Color?
    let shadow: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
            }
            text
        }
        .font(AppFont.button)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 17)
        .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(foreground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(border ?? Color.clear, lineWidth: 1)
        )
        .shadow(color: shadow ? AppTheme.shadow : .clear, radius: 14, x: 0, y: 6)
    }
}

struct AppChip: View {
    let text: Text
    let systemImage: String

    var body: some View {
        Label { text } icon: { Image(systemName: systemImage) }
            .font(AppFont.buttonSmall)
            .lineLimit(1)
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .background(AppTheme.surface, in: Capsule())
            .foregroundStyle(AppTheme.textPrimary)
            .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
    }
}

// 앱 로고 (이미지에 "mind PIC" 글자 포함)
// 이미지 가장자리를 부드럽게 흐려서 배경과 경계가 보이지 않게 한다.
struct AppLogo: View {
    var size: CGFloat = 200

    var body: some View {
        Image("SplashIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .mask(
                RadialGradient(colors: [.black, .black, .clear],
                               center: .center, startRadius: 0, endRadius: size * 0.5)
            )
            .accessibilityLabel(Text(verbatim: "mind PIC"))
    }
}

// 원형 아이콘 버튼 (홈 상단 설정/사용법 등)
struct AppIconButtonLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(width: 44, height: 44)
            .background(AppTheme.surface, in: Circle())
            .overlay(Circle().stroke(AppTheme.border, lineWidth: 1))
    }
}

// 누르는 동안 살짝 줄어드는 버튼 스타일
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// 시트(Form) 공통 배경
extension View {
    func appFormStyle() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppBackground())
    }
}

// MARK: - 사진 권한 안내
// 권한이 거부된 상태에서는 iOS가 다시 묻지 않으므로 설정 앱으로 안내한다.
struct PhotoPermissionView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 84, height: 84)
                .background(AppTheme.accentSoft, in: Circle())

            Text("사진 접근 권한이 필요해요")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("설정에서 mind PIC의 사진 접근을\n'전체 접근'으로 허용해 주세요.")
                .font(AppFont.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.textSecondary)

            Button { openAppSettings() } label: {
                AppButtonLabel(
                    text: Text("설정 열기"),
                    foreground: .white,
                    background: AppTheme.accentDark,
                    border: nil,
                    shadow: true
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
    }
}
