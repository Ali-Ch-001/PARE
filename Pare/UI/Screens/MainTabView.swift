// MainTabView.swift - Tactile Liquid Glass Bottom Navigation Bar
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public enum AppTab: Int, CaseIterable, Identifiable {
    case clean = 0
    case albums = 1
    case smartClean = 2
    case vault = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .clean: return "Clean"
        case .albums: return "Albums"
        case .smartClean: return "Categories"
        case .vault: return "Storage"
        }
    }

    public var icon: String {
        switch self {
        case .clean: return "sparkles"
        case .albums: return "rectangle.stack.fill"
        case .smartClean: return "square.grid.2x2.fill"
        case .vault: return "chart.pie.fill"
        }
    }
}

public struct MainTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var tabNamespace
    @State private var selectedTab: AppTab = .clean

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Active Tab Viewport
            Group {
                switch selectedTab {
                case .clean:
                    HomeView()
                case .albums:
                    AlbumsView()
                case .smartClean:
                    CategoryFilterView()
                case .vault:
                    VaultStatsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Tactile Island Bottom Navigation Bar
            floatingTabBar
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .ignoresSafeArea(.keyboard)
    }

    private var floatingTabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = selectedTab == tab

                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: isSelected ? 18 : 17, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? ParePalette.accent : ParePalette.textSecondary)

                        Text(tab.title)
                            .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                            .foregroundStyle(isSelected ? ParePalette.accent : ParePalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(ParePalette.accent.opacity(colorScheme == .dark ? 0.16 : 0.10))
                                .matchedGeometryEffect(id: "active_tab_pill", in: tabNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(ScalePressStyle())
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            ZStack {
                Capsule()
                    .fill(
                        colorScheme == .dark
                            ? Color(.displayP3, red: 0.11, green: 0.11, blue: 0.14, opacity: 0.82)
                            : Color.white.opacity(0.90)
                    )
                    .background(.ultraThinMaterial, in: Capsule())

                Capsule()
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.12)
                            : Color.black.opacity(0.06),
                        lineWidth: 0.75
                    )
            }
        )
        .shadow(
            color: colorScheme == .dark
                ? Color.black.opacity(0.35)
                : Color.black.opacity(0.06),
            radius: 16,
            x: 0,
            y: 6
        )
    }
}
