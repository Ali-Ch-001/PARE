// StagePill.swift - Stage Indicator Pill Component
import SwiftUI

public struct StagePill: View {
    let title: String
    let active: Bool

    public init(title: String, active: Bool) {
        self.title = title
        self.active = active
    }

    public var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(active ? Color.primary : Color.secondary.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(in: .rect(cornerRadius: 12))
            .opacity(active ? 1.0 : 0.4)
    }
}
