// PareHardwareProfile.swift - Apple Silicon Hardware Capability Profile
import Foundation
import Metal

public enum HardwareEngineTier: String, CaseIterable, Sendable {
    case appleSiliconNeural = "Apple Silicon Neural Engine (ANE)"

    public var badgeTitle: String {
        return "ON-DEVICE NEURAL ENGINE (ANE)"
    }

    public var hardwareDescription: String {
        return "Executes 100% on-device using Apple Silicon's dedicated Neural Engine and Metal GPU. Zero cloud uploads, zero network latency, complete personal privacy."
    }
}

public final class PareHardwareProfile {
    public static let shared = PareHardwareProfile()

    public let currentTier: HardwareEngineTier
    public let physicalMemoryGB: Double
    public let coreCount: Int
    public let gpuArchitecture: String

    /// True if device meets Apple Intelligence minimum unified memory (8GB RAM: iPhone 15 Pro, iPhone 16+, M-series)
    public var isAppleIntelligenceHardwareSupported: Bool {
        return physicalMemoryGB >= 7.5
    }

    public static var deviceModelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier.isEmpty ? "Apple Silicon" : "Apple (\(identifier))"
    }

    private init() {
        let memBytes = ProcessInfo.processInfo.physicalMemory
        self.physicalMemoryGB = Double(memBytes) / (1024.0 * 1024.0 * 1024.0)
        self.coreCount = ProcessInfo.processInfo.processorCount
        self.currentTier = .appleSiliconNeural

        // Dynamically query the actual Metal GPU device and supported family directly from the OS
        if let dev = MTLCreateSystemDefaultDevice() {
            let metalVersion = dev.supportsFamily(.metal3) ? "Metal 3" : "Metal 2"
            self.gpuArchitecture = "\(dev.name) (\(metalVersion))"
        } else {
            self.gpuArchitecture = "Apple Silicon GPU"
        }
    }
}
