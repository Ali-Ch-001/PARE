// SettingsView.swift - Control Room for C++ Parameters & Privacy Enclaves
import SwiftUI
import Photos

public struct PhotoAlbumItem: Identifiable {
    public let id: String
    public let title: String
    public let count: Int
    public let isSmartAlbum: Bool
}

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pare_curation_ruthlessness") private var ruthlessness: Double = 0.50
    @AppStorage("pare_overnight_enabled") private var overnightEnabled: Bool = true
    @AppStorage("pare_require_power_wifi") private var requirePowerAndWifi: Bool = true
    @AppStorage("pare_auto_delete_overnight") private var trustTheAIAutoClean: Bool = false
    @AppStorage("pare_appearance_mode") private var appearanceMode: String = "system"
    @State private var showAlbumPicker: Bool = false
    @State private var showTrustAIConfirm: Bool = false
    @State private var showIntelligenceGuide: Bool = false
    @State private var protectedAlbumCount: Int = 0

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceMode) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    Text(appearanceMode == "light"
                         ? "Bright and clean."
                         : (appearanceMode == "dark"
                            ? "Deep and calm."
                            : "Follows your iPhone."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section("Cleaning Strength") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("How aggressive?")
                            Spacer()
                            Text(ruthlessnessLabel)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(ParePalette.accent)
                        }
                        Slider(value: $ruthlessness, in: 0.0...1.0, step: 0.05)
                        Text("Slide right to clear more. Slide left to be more careful.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Overnight Cleaning") {
                    Toggle("Clean While I Sleep", isOn: Binding(
                        get: { overnightEnabled },
                        set: { newVal in
                            overnightEnabled = newVal
                            if newVal {
                                Task {
                                    await PareDeepCleanTask.shared.requestNotificationPermission()
                                }
                            }
                        }
                    ))
                    Toggle("Only When Charging", isOn: $requirePowerAndWifi)
                    Toggle("Auto-stage Duplicates", isOn: $trustTheAIAutoClean)
                    Text("Finds duplicate shots overnight and gets them ready for you to approve in the morning.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Section("Apple Intelligence & On-Device Sovereignty") {
                    Button {
                        self.showIntelligenceGuide = true
                    } label: {
                        HStack {
                            Label("Apple Intelligence & Privacy Guide", systemImage: "sparkles")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(PareHardwareProfile.shared.isAppleIntelligenceHardwareSupported
                         ? "Your device supports Apple Intelligence. Tap for instructions to enable it in iOS Settings, plus on-device permission transparency."
                         : "Your device runs Pare's native neural pipeline on-device. Apple Intelligence system features require an iPhone 15 Pro or newer.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Section("Protected Albums") {
                    Button {
                        self.showAlbumPicker = true
                    } label: {
                        HStack {
                            Label("Choose Albums to Keep Safe", systemImage: "lock.shield.fill")
                            Spacer()
                            Text("\(protectedAlbumCount) Protected")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text("Photos in these albums are never touched. We won't suggest or delete anything in them.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Section("About This Device") {
                    HStack {
                        Text("On-Device Engine")
                        Spacer()
                        Text("Runs 100% on your iPhone")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(ParePalette.successGreen)
                    }
                    HStack {
                        Text("Graphics")
                        Spacer()
                        Text(PareHardwareProfile.shared.gpuArchitecture)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Memory")
                        Spacer()
                        Text(String(format: "%.1f GB", PareHardwareProfile.shared.physicalMemoryGB))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Processor")
                        Spacer()
                        Text("\(PareHardwareProfile.shared.coreCount) Cores")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("How It Works") {
                    HStack {
                        Text("Device")
                        Spacer()
                        Text(PareHardwareProfile.deviceModelName)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Memory Use")
                        Spacer()
                        Text("< 15 MB")
                            .foregroundStyle(ParePalette.successGreen)
                    }
                    HStack {
                        Text("Privacy")
                        Spacer()
                        Text("100% on-device • 0 uploads")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                self.protectedAlbumCount = PareTrashManager.shared.getProtectedAlbumIDs().count
            }
            .preferredColorScheme(appearanceScheme)
            .alert("Enable Overnight Auto-Clean?", isPresented: $showTrustAIConfirm) {
                Button("Enable Auto-Clean", role: .destructive) {
                    self.trustTheAIAutoClean = true
                }
                Button("Cancel", role: .cancel) {
                    self.trustTheAIAutoClean = false
                }
            } message: {
                Text("While charging overnight, Pare finds the clutter and gets it ready for you to approve in the morning. Nothing is deleted without your tap, and you can undo anything within 30 days.")
            }
            .sheet(isPresented: $showIntelligenceGuide) {
                AppleIntelligenceGuideSheet()
            }
            .sheet(isPresented: $showAlbumPicker) {
                ProtectedAlbumsView {
                    self.protectedAlbumCount = PareTrashManager.shared.getProtectedAlbumIDs().count
                }
            }
        }
    }

    private var ruthlessnessLabel: String {
        if ruthlessness < 0.3 { return "Gentle" }
        if ruthlessness < 0.7 { return "Balanced" }
        return "Thorough"
    }

    private var appearanceScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

public struct ProtectedAlbumsView: View {
    @Environment(\.dismiss) private var dismiss
    public let onDismiss: () -> Void
    @State private var albums: [PhotoAlbumItem] = []
    @State private var selectedAlbumIDs: Set<String> = []
    @State private var isLoading: Bool = true

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Select albums to protect from curation. All photos within checked albums will remain completely untouched by the compression engine.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Enumerating albums...")
                        Spacer()
                    }
                } else if albums.isEmpty {
                    Text("No user albums found in photo library.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(albums) { album in
                        Button {
                            toggleAlbum(album.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(album.title)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.primary)
                                    Text("\(album.count) photos")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedAlbumIDs.contains(album.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(ParePalette.accent)
                                        .font(.system(size: 20))
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.tertiary)
                                        .font(.system(size: 20))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Protected Albums")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        PareTrashManager.shared.setProtectedAlbums(selectedAlbumIDs)
                        onDismiss()
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadAlbums()
            }
        }
    }

    private func toggleAlbum(_ id: String) {
        if selectedAlbumIDs.contains(id) {
            selectedAlbumIDs.remove(id)
        } else {
            selectedAlbumIDs.insert(id)
        }
    }

    private func loadAlbums() {
        self.selectedAlbumIDs = PareTrashManager.shared.getProtectedAlbumIDs()
        DispatchQueue.global(qos: .userInitiated).async {
            var items: [PhotoAlbumItem] = []

            // User Albums
            let userCollections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            userCollections.enumerateObjects { collection, _, _ in
                let assets = PHAsset.fetchAssets(in: collection, options: nil)
                if assets.count > 0 {
                    items.append(PhotoAlbumItem(
                        id: collection.localIdentifier,
                        title: collection.localizedTitle ?? "Untitled Album",
                        count: assets.count,
                        isSmartAlbum: false
                    ))
                }
            }

            // Smart Albums (Favorites, etc.)
            let smartCollections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
            smartCollections.enumerateObjects { collection, _, _ in
                let assets = PHAsset.fetchAssets(in: collection, options: nil)
                if assets.count > 0 {
                    items.append(PhotoAlbumItem(
                        id: collection.localIdentifier,
                        title: collection.localizedTitle ?? "Smart Album",
                        count: assets.count,
                        isSmartAlbum: true
                    ))
                }
            }

            DispatchQueue.main.async {
                self.albums = items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                self.isLoading = false
            }
        }
    }
}

public struct AppleIntelligenceGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let isSupported = PareHardwareProfile.shared.isAppleIntelligenceHardwareSupported

    public var body: some View {
        NavigationStack {
            ZStack {
                ParePalette.canvasBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        // Symmetrical Center Crest
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(ParePalette.accent.opacity(0.12))
                                    .frame(width: 80, height: 80)
                                    .blur(radius: 12)

                                Image(systemName: "sparkles")
                                    .font(.system(size: 36, weight: .semibold))
                                    .foregroundStyle(ParePalette.accent)
                            }
                            .frame(width: 88, height: 88)
                            .glassEffect(in: .circle)

                            VStack(spacing: 4) {
                                Text("ON-DEVICE SOVEREIGNTY")
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    .foregroundStyle(ParePalette.accent)
                                    .tracking(1.4)

                                Text("Apple Intelligence & Privacy")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(ParePalette.textPrimary)

                                Text("All heuristics, neural feature prints, and curation execute strictly on your device silicon. Zero data ever leaves this iPhone.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(ParePalette.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(3)
                                    .padding(.horizontal, 16)
                            }

                            // Hardware Tier Status Pill
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(isSupported ? ParePalette.successGreen : ParePalette.heroGold)
                                    .frame(width: 6, height: 6)
                                Text(isSupported
                                     ? "Supported on this device (8GB+ RAM)"
                                     : "Runs native on-device neural engine")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(ParePalette.textPrimary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassEffect(in: .capsule)
                        }
                        .padding(.top, 10)

                        // 3 Balanced Privacy Pillars (Symmetric Even Padding)
                        VStack(spacing: 12) {
                            privacyPillarRow(
                                icon: "photo.stack",
                                title: "Local Thumbnails Only",
                                detail: "Only on-device 256px micro-thumbnails are read for feature prints. Zero full-resolution photos or libraries are transmitted anywhere."
                            )

                            privacyPillarRow(
                                icon: "arrow.uturn.backward.circle",
                                title: "30-Day Recovery Safety",
                                detail: "All deletions use Apple's native PhotoKit change requests. Files move to Recently Deleted, allowing complete restoration for 30 days."
                            )

                            privacyPillarRow(
                                icon: "bolt.badge.clock",
                                title: "Idle Charging Only",
                                detail: "Overnight background curation runs exclusively via Apple's BGProcessingTask when plugged in to protect battery longevity."
                            )
                        }
                        .padding(.horizontal, 24)

                        // Symmetrical Step-by-Step Enablement Guide
                        VStack(alignment: .leading, spacing: 14) {
                            Text("HOW TO ENABLE APPLE INTELLIGENCE IN IOS")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(ParePalette.accent)
                                .tracking(1.2)
                                .padding(.horizontal, 4)

                            if isSupported {
                                VStack(spacing: 10) {
                                    numberedStepCard(step: "1", title: "Open Settings", desc: "Open the Settings app on your iPhone home screen.")
                                    numberedStepCard(step: "2", title: "Apple Intelligence & Siri", desc: "Scroll down and tap the Apple Intelligence & Siri menu.")
                                    numberedStepCard(step: "3", title: "Turn On or Join Waitlist", desc: "Tap Turn On Apple Intelligence (or join the waitlist).")
                                    numberedStepCard(step: "4", title: "Keep Connected", desc: "Keep your iPhone connected to Wi-Fi and power while models download.")
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Apple Intelligence system features require an iPhone 15 Pro, iPhone 16+, or an M-series iPad/Mac.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(ParePalette.textSecondary)
                                        .lineSpacing(3)

                                    Text("Pare's on-device neural feature extraction and GPU clustering run natively on ALL iPhones without requiring Apple Intelligence.")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(ParePalette.accent)
                                }
                                .padding(16)
                                .glassEffect(in: .rect(cornerRadius: 16))
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                    }
                }
            }
            .navigationTitle("Privacy & Intelligence")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func privacyPillarRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ParePalette.accent)
                .frame(width: 32, height: 32)
                .glassEffect(in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(ParePalette.textPrimary)

                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(ParePalette.textSecondary)
                    .lineSpacing(2)
            }
            Spacer()
        }
        .padding(14)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    private func numberedStepCard(step: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(ParePalette.accent)
                .clipShape(Circle())
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(ParePalette.textPrimary)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(ParePalette.textSecondary)
                    .lineSpacing(2)
            }
            Spacer()
        }
        .padding(12)
        .glassEffect(in: .rect(cornerRadius: 14))
    }
}
