// PareApp.swift - SwiftUI Application Entry Point
import SwiftUI

@main
public struct PareApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @AppStorage("pare_appearance_mode") private var appearanceMode: String = "system"
    @AppStorage("pare_has_onboarded") private var hasOnboarded: Bool = false

    public init() {}

    private var selectedColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil // Automatically follows iOS system appearance
        }
    }

    public var body: some Scene {
        WindowGroup {
            if hasOnboarded {
                MainTabView()
                    .preferredColorScheme(selectedColorScheme)
            } else {
                OnboardingView {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        hasOnboarded = true
                    }
                }
                .preferredColorScheme(selectedColorScheme)
            }
        }
    }
}
