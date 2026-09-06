// OnboardingView.swift - 4-Step High-Converting Funnel & Permission Priming
import SwiftUI
import Photos
#if canImport(UIKit)
import UIKit
#endif

public struct OnboardingView: View {
    public let onComplete: () -> Void
    @State private var currentStep: Int = 0
    @State private var isScanning: Bool = false
    @State private var scannedPhotoCount: Int = 0
    @State private var isPermissionDenied: Bool = false

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            ParePalette.canvasBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Progress Indicator
                HStack(spacing: 8) {
                    ForEach(0..<4) { idx in
                        Capsule()
                            .fill(idx <= currentStep ? ParePalette.accent : Color.white.opacity(0.15))
                            .frame(width: idx == currentStep ? 40 : nil, height: idx == currentStep ? 6 : 4)
                            .frame(maxWidth: idx == currentStep ? nil : .infinity)
                            .shadow(color: idx <= currentStep ? ParePalette.accent.opacity(0.6) : .clear, radius: idx == currentStep ? 5 : 0)
                            .animation(.spring(response: 0.35, dampingFraction: 0.55), value: currentStep)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                Spacer()

                // Step Content Viewport
                Group {
                    switch currentStep {
                    case 0:
                        valueStepView
                    case 1:
                        privacyStepView
                    case 2:
                        permissionStepView
                    default:
                        ahaRevealStepView
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.9).combined(with: .move(edge: .trailing))),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: currentStep)

                Spacer()

                // Bottom Action Buttons
                bottomActionBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
            }
        }
    }

    // MARK: - Step 1: Mathematical Value
    private var valueStepView: some View {
        VStack(spacing: 24) {
            BouncyHeroIcon(symbol: "camera.macro", tint: ParePalette.accent)

            VStack(spacing: 12) {
                Text("KEEP THE HEROES.\nPARE THE NOISE.")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ParePalette.textPrimary)
                    .tracking(0.5)

                Text("Pare clears the bad shots cluttering your library and keeps the ones that matter.")
                    .font(.system(size: 14))
                    .foregroundStyle(ParePalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Step 2: On-Device Privacy
    private var privacyStepView: some View {
        VStack(spacing: 24) {
            BouncyHeroIcon(symbol: "lock.shield.fill", tint: ParePalette.successGreen)

            VStack(spacing: 12) {
                Text("100% ON-DEVICE.\nNEVER IN THE CLOUD.")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ParePalette.textPrimary)
                    .tracking(0.5)

                Text("Everything runs right on your iPhone. No cloud. No uploads. Your photos never leave your device.")
                    .font(.system(size: 14))
                    .foregroundStyle(ParePalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Step 3: Permission Priming & Safety Guarantee
    private var permissionStepView: some View {
        VStack(spacing: 24) {
            if isPermissionDenied {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(ParePalette.alertRed)

                    Text("Photo Access Required")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(ParePalette.textPrimary)

                    Text("Pare needs access to clear the clutter and move the extras to Recently Deleted.")
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
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    #endif
                }
            } else {
                BouncyHeroIcon(symbol: "photo.stack.fill", tint: ParePalette.accent)

                VStack(spacing: 12) {
                    Text("ALLOW PHOTO ACCESS")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(ParePalette.textPrimary)
                        .tracking(0.5)

                    Text("When prompted by iOS, tap \"Allow Access to All Photos\". The photos you clear go to Recently Deleted, so you can always bring them back within 30 days.")
                        .font(.system(size: 14))
                        .foregroundStyle(ParePalette.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 24)
                }
            }
        }
    }

    // MARK: - Step 4: Instant Auto-Scan & "Aha" Reveal
    private var ahaRevealStepView: some View {
        VStack(spacing: 24) {
            if isScanning {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.6)
                        .tint(ParePalette.accent)
                    Text("Scanning your photos...")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(ParePalette.textPrimary)
                    Text("Finding the clutter in your library")
                        .font(.system(size: 12))
                        .foregroundStyle(ParePalette.textSecondary)
                }
            } else {
                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(ParePalette.heroGold.opacity(0.15))
                            .frame(width: 160, height: 160)
                            .blur(radius: 24)

                        VStack(spacing: 4) {
                            Text("\(scannedPhotoCount)")
                                .font(.system(size: 56, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(ParePalette.textPrimary)
                            Text("PHOTOS")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .tracking(1.4)
                                .foregroundStyle(ParePalette.heroGold)
                        }
                    }

                    VStack(spacing: 10) {
                        Text("Your Library Is Ready")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(ParePalette.textPrimary)

                        Text("Pare will sort through your photos and find the ones you can safely clear.")
                            .font(.system(size: 14))
                            .foregroundStyle(ParePalette.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 24)
                    }
                }
            }
        }
    }

    // MARK: - Bottom Action Bar
    private var bottomActionBar: some View {
        VStack(spacing: 12) {
            Button {
                handleNextStep()
            } label: {
                HStack(spacing: 8) {
                    Text(buttonTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .disabled(isScanning)
            .primaryActionButton(cornerRadius: 18)
            .buttonStyle(ScalePressStyle())
        }
    }

    private var buttonTitle: String {
        switch currentStep {
        case 0, 1:
            return "Continue"
        case 2:
            return isPermissionDenied ? "Retry Permission" : "Allow Access & Scan"
        default:
            return isScanning ? "Sorting..." : "Start Cleaning"
        }
    }

    private func handleNextStep() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        if currentStep < 2 {
            currentStep += 1
        } else if currentStep == 2 {
            Task {
                let auth = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                if auth == .authorized || auth == .limited {
                    self.isPermissionDenied = false
                    self.currentStep = 3
                    self.runInitialScan()
                } else {
                    self.isPermissionDenied = true
                }
            }
        } else {
            // Step 3 completed -> Enter main app
            onComplete()
        }
    }

    private func runInitialScan() {
        self.isScanning = true
        Task {
            let count = await ParePhotoScanner.shared.fetchLibraryPhotoCount()
            self.scannedPhotoCount = count
            self.isScanning = false
        }
    }
}

// 3D bouncy hero icon with springy entrance + gentle continuous float
public struct BouncyHeroIcon: View {
    let symbol: String
    let tint: Color
    @State private var appeared = false
    @State private var floating = false

    public init(symbol: String, tint: Color) {
        self.symbol = symbol
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
                .frame(width: 150, height: 150)
                .blur(radius: 22)

            Image(systemName: symbol)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(tint)
        }
        .scaleEffect(appeared ? 1.0 : 0.55)
        .rotation3DEffect(.degrees(appeared ? 0 : 28), axis: (x: 0, y: 1, z: 0))
        .offset(y: floating ? -6 : 6)
        .animation(.spring(response: 0.55, dampingFraction: 0.55), value: appeared)
        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: floating)
        .onAppear {
            appeared = true
            floating = true
        }
    }
}
