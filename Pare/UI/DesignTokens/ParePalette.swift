// ParePalette.swift - Calibrated Display P3 Anti-AI Luxury Color Space (Light & Dark Adaptive)
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum ParePalette {
    // MARK: - Light Mode (Alabaster Canvas & Pure Obsidian Typography)
    public enum Light {
        // Base canvas: Calibrated warm alabaster (never sterile #FFF)
        public static let canvasBackground = Color(.displayP3, red: 0.976, green: 0.976, blue: 0.980, opacity: 1.0)
        
        // Liquid Glass Base
        public static let glassMaterial = Color(.displayP3, red: 1.0, green: 1.0, blue: 1.0, opacity: 0.65)
        public static let glassSpecularBorder = Color(.displayP3, red: 1.0, green: 1.0, blue: 1.0, opacity: 0.85)
        public static let glassEdgeRefraction = Color(.displayP3, red: 0.0, green: 0.0, blue: 0.0, opacity: 0.06)

        // Typography (High legibility contrast)
        public static let textPrimary = Color(.displayP3, red: 0.06, green: 0.06, blue: 0.07, opacity: 1.0)
        public static let textSecondary = Color(.displayP3, red: 0.42, green: 0.43, blue: 0.46, opacity: 1.0)

        // Monochromatic Luxury Accent: Deep Imperial Ultramarine
        public static let accent = Color(.displayP3, red: 0.05, green: 0.26, blue: 0.82, opacity: 1.0)
        public static let accentSurface = Color(.displayP3, red: 0.05, green: 0.26, blue: 0.82, opacity: 0.08)
        public static let accentDeep = Color(.displayP3, red: 0.04, green: 0.20, blue: 0.70, opacity: 1.0)
    }

    // MARK: - Dark Mode (Volcanic Obsidian & Starlight Glass)
    public enum Dark {
        // Base canvas: Deep volcanic obsidian space (never muddy grey)
        public static let canvasBackground = Color(.displayP3, red: 0.035, green: 0.035, blue: 0.039, opacity: 1.0)

        // Liquid Glass Base
        public static let glassMaterial = Color(.displayP3, red: 0.10, green: 0.10, blue: 0.12, opacity: 0.55)
        public static let glassSpecularBorder = Color(.displayP3, red: 1.0, green: 1.0, blue: 1.0, opacity: 0.18)
        public static let glassEdgeRefraction = Color(.displayP3, red: 0.0, green: 0.0, blue: 0.0, opacity: 0.35)

        // Typography
        public static let textPrimary = Color(.displayP3, red: 0.98, green: 0.98, blue: 0.99, opacity: 1.0)
        public static let textSecondary = Color(.displayP3, red: 0.55, green: 0.56, blue: 0.60, opacity: 1.0)

        // Monochromatic Luxury Accent: Bioluminescent Cobalt
        public static let accent = Color(.displayP3, red: 0.15, green: 0.42, blue: 0.95, opacity: 1.0)
        public static let accentSurface = Color(.displayP3, red: 0.15, green: 0.42, blue: 0.95, opacity: 0.15)
        public static let accentDeep = Color(.displayP3, red: 0.12, green: 0.36, blue: 0.88, opacity: 1.0)
        
        // Status Badges
        public static let heroGold = Color(.displayP3, red: 0.92, green: 0.70, blue: 0.15, opacity: 1.0)
        public static let successGreen = Color(.displayP3, red: 0.16, green: 0.78, blue: 0.45, opacity: 1.0)
        public static let alertRed = Color(.displayP3, red: 0.92, green: 0.26, blue: 0.26, opacity: 1.0)
    }

    // MARK: - Dynamic Semantic Tokens (Auto-adapts to active ColorScheme)
    
    public static var canvasBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Dark.canvasBackground) : UIColor(Light.canvasBackground)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(Dark.canvasBackground) : NSColor(Light.canvasBackground)
        })
        #endif
    }

    public static var textPrimary: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Dark.textPrimary) : UIColor(Light.textPrimary)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(Dark.textPrimary) : NSColor(Light.textPrimary)
        })
        #endif
    }

    public static var textSecondary: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Dark.textSecondary) : UIColor(Light.textSecondary)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(Dark.textSecondary) : NSColor(Light.textSecondary)
        })
        #endif
    }

    public static var accent: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Dark.accent) : UIColor(Light.accent)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(Dark.accent) : NSColor(Light.accent)
        })
        #endif
    }

    public static var accentSurface: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Dark.accentSurface) : UIColor(Light.accentSurface)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(Dark.accentSurface) : NSColor(Light.accentSurface)
        })
        #endif
    }

    public static var accentDeep: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Dark.accentDeep) : UIColor(Light.accentDeep)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(Dark.accentDeep) : NSColor(Light.accentDeep)
        })
        #endif
    }

    public static var glassMaterial: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Dark.glassMaterial) : UIColor(Light.glassMaterial)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(Dark.glassMaterial) : NSColor(Light.glassMaterial)
        })
        #endif
    }

    public static var glassSpecularBorder: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Dark.glassSpecularBorder) : UIColor(Light.glassSpecularBorder)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(Dark.glassSpecularBorder) : NSColor(Light.glassSpecularBorder)
        })
        #endif
    }

    public static var glassEdgeRefraction: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Dark.glassEdgeRefraction) : UIColor(Light.glassEdgeRefraction)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(Dark.glassEdgeRefraction) : NSColor(Light.glassEdgeRefraction)
        })
        #endif
    }

    public static var heroGold: Color { Dark.heroGold }
    public static var successGreen: Color { Dark.successGreen }
    public static var alertRed: Color { Dark.alertRed }
}
