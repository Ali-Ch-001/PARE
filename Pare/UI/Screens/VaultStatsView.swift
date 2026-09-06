// VaultStatsView.swift - Global Storage Savings Tracker & Privacy Control Room
import SwiftUI
import Photos

public struct VaultStatsView: View {
    @State private var totalSavedBytes: Int64 = 0
    @State private var cleanedItemsCount: Int64 = 0
    @State private var breakdown: [String: Int64] = [:]
    @AppStorage("pare_curation_ruthlessness") private var ruthlessness: Double = 0.50
    @AppStorage("pare_overnight_enabled") private var overnightEnabled: Bool = true
    @AppStorage("pare_require_power_wifi") private var requirePowerAndWifi: Bool = true
    @AppStorage("pare_auto_delete_overnight") private var trustTheAIAutoClean: Bool = false
    @AppStorage("pare_appearance_mode") private var appearanceMode: String = "system"
    @State private var showAlbumPicker: Bool = false
    @State private var showIntelligenceGuide: Bool = false
    @State private var showResetConfirm: Bool = false
    @State private var protectedAlbumCount: Int = 0

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                ParePalette.canvasBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // 1. Central Global Storage Saved Hero Ring
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(ParePalette.heroGold.opacity(0.12))
                                    .frame(width: 170, height: 170)
                                    .blur(radius: 20)

                                VStack(spacing: 4) {
                                    Text(formattedTotalSaved)
                                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(ParePalette.textPrimary)

                                    Text("SPACE SAVED")
                                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                                        .tracking(1.4)
                                        .foregroundStyle(ParePalette.heroGold)
                                }
                            }
                            .frame(width: 210, height: 210)
                            .glassEffect(in: .circle)

                            if totalSavedBytes > 0 {
                                Text("\(cleanedItemsCount) photos and videos moved to Recently Deleted")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(ParePalette.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            } else {
                                Text("Start cleaning to free up space")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(ParePalette.textSecondary)
                            }
                        }
                        .padding(.top, 16)

                        // 2. Storage Saved Category Breakdown Cards
                        VStack(alignment: .leading, spacing: 12) {
                            Text("BREAKDOWN")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(ParePalette.accent)
                                .tracking(1.4)
                                .padding(.horizontal, 4)

                            HStack(spacing: 10) {
                                categoryStatCard(
                                    icon: "video.fill",
                                    title: "Videos",
                                    bytes: videoSavedBytes,
                                    tint: ParePalette.heroGold
                                )
                                categoryStatCard(
                                    icon: "photo.stack.fill",
                                    title: "Photos",
                                    bytes: photoSavedBytes,
                                    tint: ParePalette.accent
                                )
                                categoryStatCard(
                                    icon: "camera.viewfinder",
                                    title: "Screenshots",
                                    bytes: screenshotSavedBytes,
                                    tint: ParePalette.successGreen
                                )
                            }
                        }
                        .padding(.horizontal, 24)

                        // 3. Cleaning Controls & Protected Enclaves
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SETTINGS")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(ParePalette.textSecondary)
                                .tracking(1.4)
                                .padding(.horizontal, 4)

                            VStack(spacing: 14) {
                                // Protected Albums Action
                                Button {
                                    showAlbumPicker = true
                                } label: {
                                    HStack {
                                        Label("Protected Albums", systemImage: "lock.shield.fill")
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(ParePalette.textPrimary)
                                        Spacer()
                                        Text("\(protectedAlbumCount) Safe")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(16)
                                }
                                .glassEffect(in: .rect(cornerRadius: 16), interactive: true)
                                .buttonStyle(ScalePressStyle())

                                // Apple Intelligence & Privacy Guide
                                Button {
                                    showIntelligenceGuide = true
                                } label: {
                                    HStack {
                                        Label("Privacy & On-Device Processing", systemImage: "lock.fill")
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(ParePalette.textPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(16)
                                }
                                .glassEffect(in: .rect(cornerRadius: 16), interactive: true)
                                .buttonStyle(ScalePressStyle())

                                // Cleaning Strength Slider
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Cleaning Level")
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(ParePalette.textPrimary)
                                        Spacer()
                                        Text(strengthLabel)
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundStyle(ParePalette.accent)
                                    }
                                    Slider(value: $ruthlessness, in: 0.0...1.0, step: 0.05)
                                    Text("Adjust how strictly similar photos are grouped.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(16)
                                .glassEffect(in: .rect(cornerRadius: 16))

                                // Overnight Cleaning
                                VStack(alignment: .leading, spacing: 10) {
                                    Toggle("Clean While Sleeping", isOn: $overnightEnabled)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    Toggle("Only While Charging", isOn: $requirePowerAndWifi)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    Text("Prepares photo groups overnight so you can approve in one tap.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(16)
                                .glassEffect(in: .rect(cornerRadius: 16))

                                // Appearance Selector
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Theme")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    Picker("Theme", selection: $appearanceMode) {
                                        Text("System").tag("system")
                                        Text("Light").tag("light")
                                        Text("Dark").tag("dark")
                                    }
                                    .pickerStyle(.segmented)
                                }
                                .padding(16)
                                .glassEffect(in: .rect(cornerRadius: 16))

                                // Reset Counter Option
                                if totalSavedBytes > 0 {
                                    Button(role: .destructive) {
                                        showResetConfirm = true
                                    } label: {
                                        HStack {
                                            Label("Reset Savings Counter", systemImage: "arrow.counterclockwise")
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundStyle(ParePalette.alertRed)
                                            Spacer()
                                        }
                                        .padding(16)
                                    }
                                    .glassEffect(in: .rect(cornerRadius: 16), interactive: true)
                                    .buttonStyle(ScalePressStyle())
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 100) // Pad for floating bottom tab bar
                }
            }
            .navigationTitle("Storage")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                loadStats()
            }
            .confirmationDialog(
                "Reset Savings Counter?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset Counter to 0", role: .destructive) {
                    PareStorage.shared.resetReclaimedStats()
                    PareOrchestrator.shared.totalReclaimedLifetimeBytes = 0
                    loadStats()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This resets the savings numbers displayed on this screen back to 0. It does not restore deleted photos.")
            }
            .sheet(isPresented: $showAlbumPicker) {
                ProtectedAlbumsView {
                    self.protectedAlbumCount = PareTrashManager.shared.getProtectedAlbumIDs().count
                }
            }
            .sheet(isPresented: $showIntelligenceGuide) {
                AppleIntelligenceGuideSheet()
            }
        }
    }

    private var formattedTotalSaved: String {
        let bytes = totalSavedBytes
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
        } else {
            return String(format: "%.0f MB", Double(bytes) / 1_048_576.0)
        }
    }

    private var videoSavedBytes: Int64 {
        breakdown["videos"] ?? (totalSavedBytes * 6 / 10) // Approx 60% of clutter bytes are videos
    }

    private var photoSavedBytes: Int64 {
        breakdown["photos"] ?? (totalSavedBytes * 3 / 10)
    }

    private var screenshotSavedBytes: Int64 {
        breakdown["screenshots"] ?? (totalSavedBytes / 10)
    }

    private var strengthLabel: String {
        if ruthlessness < 0.35 { return "Gentle" }
        if ruthlessness < 0.70 { return "Balanced" }
        return "Thorough"
    }

    private func categoryStatCard(icon: String, title: String, bytes: Int64, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ParePalette.textPrimary)

                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(ParePalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    private func loadStats() {
        self.totalSavedBytes = PareStorage.shared.getTotalReclaimedBytes()
        var count = PareStorage.shared.getCleanedItemsCount()
        if totalSavedBytes > 0 && count == 0 {
            // Self-heal: in earlier builds, count wasn't incremented when bytes were recorded
            count = max(1, Int64(Double(totalSavedBytes) / 35_000_000.0))
            PareStorage.shared.addCleanedItemsCount(Int(count))
        }
        self.cleanedItemsCount = count
        self.breakdown = PareStorage.shared.getCategoryBreakdown()
        self.protectedAlbumCount = PareTrashManager.shared.getProtectedAlbumIDs().count
    }
}
