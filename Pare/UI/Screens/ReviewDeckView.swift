// ReviewDeckView.swift - ProMotion 120 FPS Fluid Morphing Card Deck
import SwiftUI
import Photos

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct ReviewDeckView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var orchestrator = PareOrchestrator.shared
    @State private var dragOffset: CGSize = .zero
    @State private var cardScale: CGFloat = 1.0
    @State private var heroThumbnail: UIImage? = nil
    @State private var redundantThumbnails: [String: UIImage] = [:]
    @State private var showAutoCleanConfirm: Bool = false
    @State private var stagedTrashIDs: Set<String> = []
    @State private var stagedReclaimBytes: Int64 = 0
    @State private var isDeletingStaged: Bool = false
    @State private var inspectingPhoto: InspectingPhotoItem? = nil

    public init() {}

    private var currentCard: CuratedClusterCard? {
        guard !orchestrator.activeClusters.isEmpty,
              orchestrator.currentClusterIndex < orchestrator.activeClusters.count else {
            return nil
        }
        return orchestrator.activeClusters[orchestrator.currentClusterIndex]
    }

    public var body: some View {
        ZStack {
            ParePalette.canvasBackground
                .ignoresSafeArea()

            if let card = currentCard {
                VStack(spacing: 24) {
                    // Header Status Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.title)
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(ParePalette.textSecondary)
                                .tracking(1.4)

                            HStack(spacing: 6) {
                                Text(String(format: "Est. %.1f MB", Double(card.reclaimableBytes) / 1_048_576.0))
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(ParePalette.textPrimary)
                                Text("est. reclaimable")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(ParePalette.textSecondary)
                            }
                        }

                        Spacer()

                        // 1-Tap Auto-Clean All Button
                        Button {
                            showAutoCleanConfirm = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.yellow)
                                Text("Clean All")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .liquidGlassCard(cornerRadius: 12, interactive: true, tint: ParePalette.alertRed)
                        }
                        .buttonStyle(ScalePressStyle())

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(10)
                                .glassEffect(in: .circle)
                        }
                        .buttonStyle(ScalePressStyle())
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    Spacer()

                    // Swipeable Card Stack inside GlassEffectContainer
                    GlassEffectContainer(spacing: 0) {
                        ZStack {
                            // Background Card Layer (Concentric Geometry: r_outer = 28, scale = 0.94)
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(ParePalette.glassMaterial)
                                .frame(width: 310, height: 420)
                                .scaleEffect(0.94)
                                .offset(y: 18)
                                .glassEffect(in: .rect(cornerRadius: 28))
                                .opacity(0.6)

                            // Primary Hero Storytelling Pivot Card
                            VStack(spacing: 0) {
                                Button {
                                    openFullInspection(for: card.heroIdentifier)
                                } label: {
                                    ZStack(alignment: .bottomLeading) {
                                        // Image Viewport
                                        Rectangle()
                                            .fill(Color.black.opacity(0.2))
                                            .frame(width: 330, height: 280)
                                            .overlay {
                                                if let thumb = heroThumbnail {
                                                    #if canImport(UIKit)
                                                    Image(uiImage: thumb)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 330, height: 280)
                                                        .clipped()
                                                    #elseif canImport(AppKit)
                                                    Image(nsImage: thumb)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 330, height: 280)
                                                        .clipped()
                                                    #endif
                                                } else {
                                                    VStack(spacing: 8) {
                                                        Image(systemName: "photo.stack.fill")
                                                            .font(.system(size: 44))
                                                            .foregroundStyle(ParePalette.accent.opacity(0.4))
                                                        Text("Analyzing...")
                                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                            .padding(8)

                                    // Hero Tag (Bioluminescent Gold)
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(ParePalette.successGreen)
                                            .frame(width: 6, height: 6)
                                        Text("KEEP THIS ONE")
                                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                                            .tracking(0.8)
                                            .foregroundStyle(Color.black)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(ParePalette.heroGold)
                                    .clipShape(Capsule())
                                    .padding(18)
                                }
                            }
                            .buttonStyle(ScalePressStyle())

                                // Redundant Photos Preview Strip (Transparency: Shows what is deleted)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("EXTRAS TO CLEAR (\(card.redundantIdentifiers.count))")
                                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                                            .foregroundStyle(ParePalette.alertRed)
                                            .tracking(0.6)
                                        Spacer()
                                        Text("~\(String(format: "%.1f MB", Double(card.reclaimableBytes) / 1_048_576.0)) (Est.)")
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                            .foregroundStyle(ParePalette.textSecondary)
                                    }
                                    .padding(.horizontal, 16)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(card.redundantIdentifiers, id: \.self) { redId in
                                                Button {
                                                    openFullInspection(for: redId)
                                                } label: {
                                                    ZStack(alignment: .topTrailing) {
                                                        if let img = redundantThumbnails[redId] {
                                                            #if canImport(UIKit)
                                                            Image(uiImage: img)
                                                                .resizable()
                                                                .aspectRatio(contentMode: .fill)
                                                                .frame(width: 52, height: 52)
                                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                                .overlay(
                                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                                        .strokeBorder(ParePalette.alertRed.opacity(0.4), lineWidth: 1)
                                                                )
                                                            #elseif canImport(AppKit)
                                                            Image(nsImage: img)
                                                                .resizable()
                                                                .aspectRatio(contentMode: .fill)
                                                                .frame(width: 52, height: 52)
                                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                            #endif
                                                        } else {
                                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                                .fill(Color.white.opacity(0.08))
                                                                .frame(width: 52, height: 52)
                                                                .overlay {
                                                                    ProgressView().scaleEffect(0.5)
                                                                }
                                                        }

                                                        Image(systemName: "magnifyingglass.circle.fill")
                                                            .font(.system(size: 13))
                                                            .foregroundStyle(Color.white)
                                                            .background(Circle().fill(ParePalette.alertRed))
                                                            .padding(2)
                                                    }
                                                }
                                                .buttonStyle(ScalePressStyle())
                                                .contextMenu {
                                                    Button {
                                                        openFullInspection(for: redId)
                                                    } label: {
                                                        Label("Inspect Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                                                    }

                                                    Button {
                                                        swapHero(with: redId)
                                                    } label: {
                                                        Label("Keep This Instead (Make Hero)", systemImage: "arrow.triangle.2.circlepath")
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                }
                                .padding(.top, 4)

                                // Card Footer Controls
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Hero Selection")
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(ParePalette.textPrimary)
                                        Text("Best shot • \(Int(card.heroQuality * 100))% sharp")
                                            .font(.system(size: 11))
                                            .foregroundStyle(ParePalette.textSecondary)
                                    }

                                    Spacer()

                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(ParePalette.accent)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                            }
                            .frame(width: 346, height: 460)
                            .glassEffect(in: .rect(cornerRadius: 30), interactive: true)
                            .offset(x: dragOffset.width, y: dragOffset.height * 0.15)
                            .rotationEffect(.degrees(Double(dragOffset.width) / 18.0))
                            .scaleEffect(cardScale)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        dragOffset = value.translation
                                        cardScale = max(0.96, 1.0 - abs(value.translation.width) / 2000.0)
                                    }
                                    .onEnded { value in
                                        if value.translation.width > 120 {
                                            commitDecision(trashRedundant: true)
                                        } else if value.translation.width < -120 {
                                            commitDecision(trashRedundant: false)
                                        } else {
                                            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                                                dragOffset = .zero
                                                cardScale = 1.0
                                            }
                                        }
                                    }
                            )
                        }
                    }

                    Spacer()

                    // Live Staged Deletion Counter Pill
                    if !stagedTrashIDs.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(ParePalette.alertRed)
                            Text("\(stagedTrashIDs.count) photos marked to clear")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(ParePalette.textPrimary)
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text("~\(String(format: "%.1f MB", Double(stagedReclaimBytes) / 1_048_576.0))")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(ParePalette.accent)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .glassEffect(in: .capsule)
                        .padding(.bottom, 4)
                    }

                    // Tactile Glass Decision Buttons (Identically Sized 66x66 Circles)
                    HStack(spacing: 60) {
                        Button {
                            commitDecision(trashRedundant: false)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(ParePalette.textSecondary)
                                .frame(width: 66, height: 66)
                                .glassEffect(in: .circle, interactive: true)
                        }
                        .buttonStyle(ScalePressStyle())

                        Button {
                            commitDecision(trashRedundant: true)
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(ParePalette.alertRed)
                                .frame(width: 66, height: 66)
                                .glassEffect(in: .circle, interactive: true)
                        }
                        .buttonStyle(ScalePressStyle())
                    }
                    .padding(.bottom, 28)
                }
                .task(id: card.heroIdentifier) {
                    self.heroThumbnail = await ParePhotoScanner.shared.fetchThumbnail(for: card.heroIdentifier)
                    for id in card.redundantIdentifiers.prefix(8) {
                        if self.redundantThumbnails[id] == nil {
                            if let img = await ParePhotoScanner.shared.fetchThumbnail(for: id, targetSize: CGSize(width: 120, height: 120)) {
                                self.redundantThumbnails[id] = img
                            }
                        }
                    }
                }
            } else {
                // Completed State View (Single 1-Tap Batch Deletion with 1 iOS Dialog!)
                VStack(spacing: 24) {
                    Spacer()

                    if !stagedTrashIDs.isEmpty {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(ParePalette.alertRed)

                        Text("Review Complete")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(ParePalette.textPrimary)

                        Text("Ready to delete \(stagedTrashIDs.count) photos and save ~" + String(format: "%.1f MB", Double(stagedReclaimBytes) / 1_048_576.0) + ".")
                            .font(.system(size: 15))
                            .foregroundStyle(ParePalette.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Spacer()

                        Button {
                            Task {
                                isDeletingStaged = true
                                let count = (try? await PareTrashManager.shared.softDeleteAssets(localIdentifiers: Array(stagedTrashIDs))) ?? 0
                                if count > 0 {
                                    orchestrator.recordReclaimedBytes(stagedReclaimBytes, count: count)
                                }
                                isDeletingStaged = false
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isDeletingStaged {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "trash.fill")
                                    Text("Delete \(stagedTrashIDs.count) Photos")
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                        }
                        .destructiveActionButton(cornerRadius: 18)
                        .buttonStyle(ScalePressStyle())
                        .padding(.horizontal, 24)

                        Button("Cancel") {
                            dismiss()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 24)
                    } else {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(ParePalette.accent)

                        Text("All Photos Kept")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(ParePalette.textPrimary)

                        Text("No photos were marked for deletion.")
                            .font(.system(size: 15))
                            .foregroundStyle(ParePalette.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                        }
                        .primaryActionButton(cornerRadius: 18)
                        .buttonStyle(ScalePressStyle())
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                    }
                }
            }
        }
        .fullScreenCover(item: $inspectingPhoto) { item in
            PhotoViewerModal(asset: item.asset)
        }
        .confirmationDialog(
            "Auto-Clean All Remaining Clusters?",
            isPresented: $showAutoCleanConfirm,
            titleVisibility: .visible
        ) {
            Button("Auto-Clean (\(orchestrator.remainingRedundantPhotoCount) Photos)", role: .destructive) {
                Task {
                    await orchestrator.trashAllRemainingClusters()
                    if orchestrator.currentClusterIndex >= orchestrator.activeClusters.count {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pare keeps your best shots and moves \(orchestrator.remainingRedundantPhotoCount) extras to Recently Deleted. You can undo anything within 30 days.")
        }
    }

    private func openFullInspection(for assetId: String) {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        if let first = fetched.firstObject {
            self.inspectingPhoto = InspectingPhotoItem(id: assetId, asset: first)
        }
    }

    private func swapHero(with newHeroId: String) {
        guard let card = currentCard else { return }
        var newRedundants = card.redundantIdentifiers.filter { $0 != newHeroId }
        newRedundants.append(card.heroIdentifier)

        let updatedCard = CuratedClusterCard(
            id: card.id,
            heroIdentifier: newHeroId,
            redundantIdentifiers: newRedundants,
            reclaimableBytes: card.reclaimableBytes,
            title: card.title,
            candidateCount: card.candidateCount,
            heroQuality: card.heroQuality
        )
        orchestrator.activeClusters[orchestrator.currentClusterIndex] = updatedCard
        Task {
            self.heroThumbnail = await ParePhotoScanner.shared.fetchThumbnail(for: newHeroId)
            self.redundantThumbnails[card.heroIdentifier] = await ParePhotoScanner.shared.fetchThumbnail(for: card.heroIdentifier, targetSize: CGSize(width: 120, height: 120))
        }
    }

    private func commitDecision(trashRedundant: Bool) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: trashRedundant ? .medium : .light).impactOccurred()
        #endif

        if let card = currentCard, trashRedundant {
            for id in card.redundantIdentifiers {
                stagedTrashIDs.insert(id)
            }
            stagedReclaimBytes += Int64(card.reclaimableBytes)
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            dragOffset.width = trashRedundant ? 600 : -600
        }

        Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            orchestrator.advanceCluster()
            dragOffset = .zero
            cardScale = 1.0

            if orchestrator.currentClusterIndex >= orchestrator.activeClusters.count {
                // If user didn't stage anything, dismiss immediately
                if stagedTrashIDs.isEmpty {
                    dismiss()
                }
            }
        }
    }
}
