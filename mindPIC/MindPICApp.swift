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
        }
    }
}
