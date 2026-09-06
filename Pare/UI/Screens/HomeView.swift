// HomeView.swift - High-Agency Display P3 Luxury Bento Dashboard
import SwiftUI
import Photos
#if canImport(UIKit)
import UIKit
#endif

public struct HomeView: View {
    @State private var orchestrator = PareOrchestrator.shared
    @State private var showProcessing: Bool = false
    @State private var showSettings: Bool = false
    @State private var showCategoryFilters: Bool = false
    @State private var selectedFilterCategory: PhotoClutterCategory = .screenshots
    @State private var estimatedClutterBytes: Int64? = nil
    @State private var totalLibraryItems: Int = 0
    @State private var isLibraryLimited: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            ParePalette.canvasBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Clean, Soulful App Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pare")
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .foregroundStyle(ParePalette.textPrimary)

                            if totalLibraryItems > 0 {
                                Text("\(totalLibraryItems) photos in library")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(ParePalette.textSecondary)
                            }
                        }

                        Spacer()

                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(ParePalette.textPrimary)
                                .padding(10)
                                .glassEffect(in: .circle)
                        }
                        .buttonStyle(ScalePressStyle())
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                    // Limited Library Access Warning Banner
                    if isLibraryLimited {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Limited Photo Access")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("Please allow Full Access in Settings to find duplicates.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Settings") {
                                #if canImport(UIKit)
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                                #endif
                            }
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.yellow.opacity(0.2))
                            .foregroundStyle(.yellow)
                            .clipShape(Capsule())
                        }
                        .padding(14)
                        .glassEffect(in: .rect(cornerRadius: 16))
                        .padding(.horizontal, 24)
                    }

                    // Central Hero Storage Unit (Centered, Balanced & Human)
                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(ParePalette.accent.opacity(0.06))
                                .frame(width: 216, height: 216)

                            Circle()
                                .strokeBorder(ParePalette.accent.opacity(0.12), lineWidth: 1)
                                .frame(width: 200, height: 200)

                            VStack(spacing: 4) {
                                Text(storageDisplayString)
                                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(ParePalette.textPrimary)

                                Text(storageRingSubtitle)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(ParePalette.textSecondary)
                                    .padding(.horizontal, 20)
                            }
                        }
                        .frame(width: 216, height: 216)

                        // Lifetime Space Saved Pill
                        if orchestrator.totalReclaimedLifetimeBytes > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(ParePalette.heroGold)
                                Text(String(format: "%.1f GB", Double(orchestrator.totalReclaimedLifetimeBytes) / 1_073_741_824.0) + " saved so far")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(ParePalette.textPrimary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .glassEffect(in: .capsule)
                        }

                        // Primary Action Button
                        Button {
                            showProcessing = true
                            Task {
                                await orchestrator.startDeepCleanPipeline()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Clean Up")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                            }
                            .frame(maxWidth: 260)
                            .frame(height: 52)
                        }
                        .primaryActionButton(cornerRadius: 26)
                        .buttonStyle(ScalePressStyle())
                    }
                    .padding(.vertical, 4)

                    // Quick Clean Bento Cards
                    VStack(spacing: 12) {
                        // Bento Row 1: Videos & Screenshots
                        HStack(spacing: 12) {
                            Button {
                                selectedFilterCategory = .largeVideos
                                showCategoryFilters = true
                            } label: {
                                bentoSmallCard(
                                    icon: "video.fill",
                                    title: "Videos",
                                    detail: "Large takes & clips",
                                    tint: ParePalette.heroGold
                                )
                            }
                            .buttonStyle(ScalePressStyle())

                            Button {
                                selectedFilterCategory = .screenshots
                                showCategoryFilters = true
                            } label: {
                                bentoSmallCard(
                                    icon: "camera.viewfinder",
                                    title: "Screenshots",
                                    detail: "Receipts & notes",
                                    tint: ParePalette.accent
                                )
                            }
                            .buttonStyle(ScalePressStyle())
                        }

                        // Bento Row 2: Burst Shots & Similar Photos
                        HStack(spacing: 12) {
                            Button {
                                selectedFilterCategory = .bursts
                                showCategoryFilters = true
                            } label: {
                                bentoSmallCard(
                                    icon: "square.stack.3d.down.right.fill",
                                    title: "Burst Shots",
                                    detail: "Repeated photos",
                                    tint: ParePalette.successGreen
                                )
                            }
                            .buttonStyle(ScalePressStyle())

                            Button {
                                selectedFilterCategory = .duplicateTimestamps
                                showCategoryFilters = true
                            } label: {
                                bentoSmallCard(
                                    icon: "clock.arrow.2.circlepath",
                                    title: "Similar Photos",
                                    detail: "Nearby takes",
                                    tint: ParePalette.alertRed
                                )
                            }
                            .buttonStyle(ScalePressStyle())
                        }

                        // Reassuring Privacy Card
                        HStack(spacing: 14) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(ParePalette.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("100% Private")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(ParePalette.textPrimary)
                                Text("All scanning happens on your phone. Nothing is ever uploaded.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(ParePalette.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .glassEffect(in: .rect(cornerRadius: 16))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 96) // Ample clearance for floating bottom bar
                }
            }
        }
        .task {
            let auth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            self.isLibraryLimited = (auth == .limited)
            self.totalLibraryItems = await ParePhotoScanner.shared.fetchLibraryPhotoCount()
            let clutter = await ParePhotoScanner.shared.estimateLibraryClutter()
            if clutter.totalBytes > 0 {
                self.estimatedClutterBytes = clutter.totalBytes
                UserDefaults.standard.set(Double(clutter.totalBytes) / 1_073_741_824.0, forKey: "pare_last_estimated_clutter_gb")
                UserDefaults.standard.set(clutter.count, forKey: "pare_last_estimated_clutter_count")
            }
        }
        .sheet(isPresented: $showProcessing) {
            ProcessingView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showCategoryFilters) {
            CategoryFilterView(initialCategory: selectedFilterCategory, isPresentedAsSheet: true)
        }
    }

    private func bentoSmallCard(icon: String, title: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(tint)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(ParePalette.textPrimary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(ParePalette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(in: .rect(cornerRadius: 18), interactive: true)
    }

    private var storageDisplayString: String {
        if let bytes = estimatedClutterBytes, bytes > 10_000_000 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
        } else {
            return "0.0 GB"
        }
    }

    private var storageRingSubtitle: String {
        if let bytes = estimatedClutterBytes, bytes > 10_000_000 {
            return "Ready to clear"
        } else {
            return "Camera roll is clean!"
        }
    }
}
