import SwiftUI

struct ContentView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            HomeView()
                .opacity(showSplash ? 0 : 1)

            if showSplash {
                ZStack {
                    AppBackground()
                    VStack {
                        AppLogo(size: 220)
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
    }
}
