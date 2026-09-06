// ScalePressStyle.swift - 0.96 Tactile Scale + Brightness Dim on Press
import SwiftUI

// 0.96 Tactile Scale + Brightness Dim on Press (make-interfaces-feel-better Rule #12)
public struct ScalePressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
