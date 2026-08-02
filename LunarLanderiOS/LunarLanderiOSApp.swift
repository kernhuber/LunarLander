//
//  LunarLanderiOSApp.swift
//  LunarLanderiOS
//
//  SwiftUI app entry point for iOS
//

import SwiftUI

@main
struct LunarLanderiOSApp: App {
    var body: some Scene {
        WindowGroup {
            GameViewControllerRepresentable()
                .ignoresSafeArea()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}

/// Wraps the UIKit iOSGameViewController for use in SwiftUI
struct GameViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> iOSGameViewController {
        return iOSGameViewController()
    }

    func updateUIViewController(_ uiViewController: iOSGameViewController, context: Context) {
        // No updates needed
    }
}
