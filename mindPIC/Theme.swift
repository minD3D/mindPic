import SwiftUI

enum AppTheme {
    static let bgTop = Color(red: 0.97, green: 0.94, blue: 0.90)
    static let bgBottom = Color(red: 0.92, green: 0.87, blue: 0.80)
    static let card = Color.white.opacity(0.78)
    static let cardStrong = Color.white.opacity(0.92)
    static let accent = Color(red: 0.78, green: 0.64, blue: 0.48)
    static let accentDark = Color(red: 0.52, green: 0.41, blue: 0.30)
    static let textPrimary = Color(red: 0.33, green: 0.27, blue: 0.22)
    static let textSecondary = Color(red: 0.52, green: 0.45, blue: 0.38)
    static let border = Color.black.opacity(0.10)
    static let shadow = Color.black.opacity(0.12)
    static let danger = Color(red: 0.70, green: 0.34, blue: 0.30)
}

enum AppFont {
    static let title = Font.custom("AvenirNext-DemiBold", size: 34)
    static let subtitle = Font.custom("AvenirNext-Regular", size: 16)
    static let button = Font.custom("AvenirNext-DemiBold", size: 17)
    static let buttonSmall = Font.custom("AvenirNext-Medium", size: 14)
    static let body = Font.custom("AvenirNext-Regular", size: 15)
    static let caption = Font.custom("AvenirNext-Regular", size: 12)
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.bgTop, AppTheme.bgBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(AppTheme.accent.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 18)
                .offset(x: 160, y: -140)

            RoundedRectangle(cornerRadius: 120)
                .fill(AppTheme.accent.opacity(0.08))
                .frame(width: 260, height: 180)
                .rotationEffect(.degrees(-18))
                .offset(x: -150, y: 220)
        }
    }
}

struct AppButtonLabel: View {
    let text: String
    let foreground: Color
    let background: Color
    let border: Color?
    let shadow: Bool

    var body: some View {
        Text(text)
            .font(AppFont.button)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(background)
            .foregroundColor(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(border ?? Color.clear, lineWidth: 1)
            )
            .cornerRadius(18)
            .shadow(color: shadow ? AppTheme.shadow : .clear, radius: 10, x: 0, y: 4)
    }
}

struct AppChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(AppFont.buttonSmall)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(AppTheme.card)
            .foregroundColor(AppTheme.textPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .cornerRadius(12)
    }
}
