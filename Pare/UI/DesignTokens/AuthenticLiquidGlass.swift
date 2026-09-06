// AuthenticLiquidGlass.swift - Apple-Grade Tactile Materials & Refined Optical System
import SwiftUI

// MARK: - Layered Physical Optics Modifier
public struct AuthenticLiquidGlass: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat
    var isInteractive: Bool
    var tintColor: Color?

    public init(cornerRadius: CGFloat = 20.0, isInteractive: Bool = false, tintColor: Color? = nil) {
        self.cornerRadius = cornerRadius
        self.isInteractive = isInteractive
        self.tintColor = tintColor
    }

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        tintColor?.opacity(colorScheme == .dark ? 0.14 : 0.08) ?? (
                            colorScheme == .dark
                                ? Color(.displayP3, red: 0.10, green: 0.10, blue: 0.13, opacity: 0.72)
                                : Color.white.opacity(0.88)
                        )
                    )
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.09)
                            : Color.black.opacity(0.06),
                        lineWidth: 0.75
                    )
            }
            .shadow(
                color: colorScheme == .dark ? Color.black.opacity(0.32) : Color.black.opacity(0.04),
                radius: colorScheme == .dark ? 12 : 8,
                x: 0,
                y: colorScheme == .dark ? 5 : 2
            )
    }
}

// MARK: - Structural Glass Container
public struct GlassEffectContainer<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    public init(spacing: CGFloat = 16.0, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        VStack(spacing: spacing) {
            content()
        }
    }
}

// MARK: - View Extensions & Semantic Modifiers
public extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 20, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(AuthenticLiquidGlass(cornerRadius: cornerRadius, isInteractive: interactive, tintColor: tint))
    }

    /// Solid primary CTA button with deep accent background
    func primaryActionButton(cornerRadius: CGFloat = 24) -> some View {
        self
            .foregroundStyle(Color.white)
            .background(
                ParePalette.accentDeep,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .shadow(color: ParePalette.accentDeep.opacity(0.30), radius: 8, x: 0, y: 4)
    }

    /// Solid destructive CTA button (red background, white text, press-reactive)
    func destructiveActionButton(cornerRadius: CGFloat = 20) -> some View {
        self
            .foregroundStyle(Color.white)
            .background(
                ParePalette.alertRed,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .shadow(color: ParePalette.alertRed.opacity(0.30), radius: 8, x: 0, y: 4)
    }

    /// Native-style iOS semantic glassEffect modifier
    func glassEffect(in shape: GlassShape = .rect(cornerRadius: 20), interactive: Bool = false, tint: Color? = nil) -> some View {
        self.modifier(AdaptiveGlassShapeModifier(shape: shape, interactive: interactive, tint: tint))
    }
}

public struct AdaptiveGlassShapeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let shape: GlassShape
    let interactive: Bool
    let tint: Color?

    public func body(content: Content) -> some View {
        switch shape {
        case .circle:
            content
                .background(
                    Circle()
                        .fill(
                            tint?.opacity(colorScheme == .dark ? 0.14 : 0.08) ?? (
                                colorScheme == .dark
                                    ? Color(.displayP3, red: 0.10, green: 0.10, blue: 0.13, opacity: 0.72)
                                    : Color.white.opacity(0.88)
                            )
                        )
                        .background(.ultraThinMaterial, in: Circle())
                )
                .overlay(
                    Circle().strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06),
                        lineWidth: 0.75
                    )
                )
                .shadow(
                    color: colorScheme == .dark ? Color.black.opacity(0.30) : Color.black.opacity(0.04),
                    radius: colorScheme == .dark ? 10 : 6,
                    x: 0,
                    y: colorScheme == .dark ? 4 : 2
                )
        case .capsule:
            content
                .background(
                    Capsule()
                        .fill(
                            tint?.opacity(colorScheme == .dark ? 0.14 : 0.08) ?? (
                                colorScheme == .dark
                                    ? Color(.displayP3, red: 0.10, green: 0.10, blue: 0.13, opacity: 0.72)
                                    : Color.white.opacity(0.88)
                            )
                        )
                        .background(.ultraThinMaterial, in: Capsule())
                )
                .overlay(
                    Capsule().strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06),
                        lineWidth: 0.75
                    )
                )
                .shadow(
                    color: colorScheme == .dark ? Color.black.opacity(0.30) : Color.black.opacity(0.04),
                    radius: colorScheme == .dark ? 10 : 6,
                    x: 0,
                    y: colorScheme == .dark ? 4 : 2
                )
        case .rect(let radius):
            content.modifier(AuthenticLiquidGlass(cornerRadius: radius, isInteractive: interactive, tintColor: tint))
        }
    }
}

public enum GlassShape {
    case circle
    case capsule
    case rect(cornerRadius: CGFloat)
}
