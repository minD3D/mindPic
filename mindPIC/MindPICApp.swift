//
//  mindPICApp.swift
//  mindPIC
//
//  Created by Mindy on 12/5/25.
//

import SwiftUI

@main
struct mindPICApp: App {
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestResetState") {
            ReviewStateStore.resetAll()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(AppTheme.accentDark)
                // 테마 색이 라이트 톤으로 고정되어 있어 다크 모드에서도 같은 모습을 유지한다.
                .preferredColorScheme(.light)
        }
    }
}
