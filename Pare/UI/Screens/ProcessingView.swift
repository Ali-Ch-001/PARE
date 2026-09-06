// ProcessingView.swift - Apple-Grade Neural Scan HUD & Telemetry Viewport
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct ProcessingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var orchestrator = PareOrchestrator.shared
    @State private var showReviewDeck: Bool = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var auraRotation: Double = 0.0

    public init() {}

    private var progressFraction: Double {
        guard orchestrator.totalCount > 0 else { return 0.0 }
        return min(1.0, Double(orchestrator.processedCount) / Double(orchestrator.totalCount))
    }

    public var body: some View {
        ZStack {
            ParePalette.canvasBackground
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Top Dismiss Bar
                HStack {
                    Spacer()
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

                // Live Stage Name & Telemetry Counters
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(orchestrator.isProcessing ? ParePalette.accent : ParePalette.successGreen)
                            .frame(width: 7, height: 7)
                            .scaleEffect(pulseScale)

                        Text(orchestrator.currentStageName.uppercased())
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(ParePalette.accent)
                            .tracking(1.4)
                    }

                    // Percentage Readout (Tabular numbers)
                    Text(String(format: "%.0f%%", progressFraction * 100))
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ParePalette.textPrimary)

                    Text("\(orchestrator.processedCount) of \(orchestrator.totalCount) photos analyzed")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(ParePalette.textSecondary)
                }
                .padding(.top, 8)

                Spacer()

                // Apple-Grade Neural Scanner Core (Concentric Glass Rings & Fluid Luminescent Pulse)
                ZStack {
                    // Ambient Chromatic Outer Aura
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [ParePalette.accent, ParePalette.heroGold, ParePalette.successGreen, ParePalette.accent],
                                center: .center
                            )
                        )
                        .frame(width: 190, height: 190)
                        .blur(radius: 28)
                        .opacity(orchestrator.isProcessing ? 0.35 : 0.15)
                        .rotationEffect(.degrees(auraRotation))

                    // Concentric Outer Glass Orbit Ring
                    Circle()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1.5)
                        .frame(width: 176, height: 176)
                        .scaleEffect(pulseScale)

                    // Inner Physical Liquid Glass Core
                    ZStack {
                        Circle()
                            .fill(Color(.displayP3, red: 0.10, green: 0.10, blue: 0.14, opacity: 0.85))
                            .background(.ultraThinMaterial, in: Circle())

                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.6), Color.white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )

                        Image(systemName: orchestrator.isProcessing ? "sparkles" : "checkmark.seal.fill")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(orchestrator.isProcessing ? ParePalette.accent : ParePalette.successGreen)
                            .scaleEffect(pulseScale)
                    }
                    .frame(width: 128, height: 128)
                    .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)
                }
                .frame(height: 220)

                Spacer()

                // Razor-Sharp Glowing Telemetry Progress Bar
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.10))
                                .frame(height: 6)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [ParePalette.accent, ParePalette.successGreen],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(8, geo.size.width * CGFloat(progressFraction)), height: 6)
                                .shadow(color: ParePalette.accent.opacity(0.7), radius: 6)
                        }
                    }
                    .frame(height: 6)
                    .padding(.horizontal, 32)
                }
                .padding(.bottom, 6)

                // Action Buttons When Complete
                if !orchestrator.isProcessing {
                    if orchestrator.isPermissionDenied || orchestrator.currentStageName == "Photo access needed" {
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(ParePalette.alertRed)
                                .font(.system(size: 38))
                            Text("Photo Access Required")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(ParePalette.textPrimary)
                            Text("Pare needs access to your photo library to clear clutter. Please allow Full Access in iOS Settings.")
                                .font(.system(size: 13))
                                .foregroundStyle(ParePalette.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            #if os(iOS)
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "gear")
                                    Text("Open iOS Settings")
                                }
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                            }
                            .primaryActionButton(cornerRadius: 16)
                            .buttonStyle(ScalePressStyle())
                            .padding(.top, 4)
                            #endif
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    } else if !orchestrator.activeClusters.isEmpty {
                        VStack(spacing: 12) {
                            Button {
                                Task {
                                    await orchestrator.trashAllRemainingClusters()
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 15, weight: .bold))
                                    let reclaimBytes = orchestrator.effectiveAutoCleanReclaimableBytes
                                    Text("Clean Duplicates (\(String(format: "%.1f MB", Double(reclaimBytes) / 1_048_576.0)))")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                            }
                            .destructiveActionButton(cornerRadius: 18)
                            .buttonStyle(ScalePressStyle())

                            Button {
                                showReviewDeck = true
                            } label: {
                                Text("Review Each (\(orchestrator.activeClusters.count) groups)")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(ParePalette.textSecondary)
                            }
                            .buttonStyle(ScalePressStyle())
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    } else {
                        VStack(spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(ParePalette.successGreen)
                                    .font(.system(size: 18))
                                Text("All Clean")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(ParePalette.textPrimary)
                            }
                            Text("No duplicate photos found.")
                                .font(.system(size: 13))
                                .foregroundStyle(ParePalette.textSecondary)

                            Button {
                                dismiss()
                            } label: {
                                Text("Done")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                            }
                            .primaryActionButton(cornerRadius: 16)
                            .buttonStyle(ScalePressStyle())
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulseScale = 1.05
            }
            withAnimation(.linear(duration: 12.0).repeatForever(autoreverses: false)) {
                auraRotation = 360.0
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showReviewDeck) {
            ReviewDeckView()
        }
        #else
        .sheet(isPresented: $showReviewDeck) {
            ReviewDeckView()
        }
        #endif
    }
}
