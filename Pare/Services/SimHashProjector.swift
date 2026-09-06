// SimHashProjector.swift - Dynamic Dimension (768/2048/512) to 128-bit SimHash Projector
import Foundation
import Accelerate

public final class SimHashProjector: @unchecked Sendable {
    public static let shared = SimHashProjector()

    private var matrixCache: [Int: [Float]] = [:]
    private let cacheLock = NSLock()

    public init() {
        // Pre-warm projection matrices for Apple Vision 768-dim and 2048-dim formats
        _ = getProjectionMatrix(dim: 768)
        _ = getProjectionMatrix(dim: 2048)
        _ = getProjectionMatrix(dim: 512)
    }

    /// Retrieves or deterministically generates an orthogonal 128 x Dim projection matrix
    public func getProjectionMatrix(dim: Int) -> [Float] {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = matrixCache[dim] {
            return cached
        }

        let totalElements = 128 * dim
        var matrix = [Float](repeating: 0.0, count: totalElements)
        
        // Deterministic Box-Muller Gaussian pseudo-random generation (Seed: 'PARE' + dim)
        var seed: UInt64 = 0x45524150 &+ UInt64(dim)
        for i in 0..<totalElements {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let u1 = Float((seed >> 32) & 0xFFFFFFFF) / Float(UInt32.max)
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let u2 = Float((seed >> 32) & 0xFFFFFFFF) / Float(UInt32.max)
            
            let radius = sqrt(-2.0 * log(max(u1, 1e-7)))
            let theta = 2.0 * Float.pi * u2
            matrix[i] = radius * cos(theta)
        }

        matrixCache[dim] = matrix
        return matrix
    }

    /**
     * Projects any continuous embedding (Vision Rev 2: 768-d, Vision Rev 1: 2048-d, or 512-d)
     * into a discrete 128-bit binary signature using hardware AMX matrix multiplication.
     *
     * @param embedding Continuous floating point feature vector
     * @return 4 x 32-bit unsigned integers representing the 128-bit SimHash
     */
    public func generateSimHash(from embedding: [Float]) -> [UInt32] {
        let dim = embedding.count
        guard dim > 0 else {
            return [0, 0, 0, 0]
        }

        let projectionMatrix = getProjectionMatrix(dim: dim)
        var projections = [Float](repeating: 0.0, count: 128)

        // Hardware-accelerated matrix-vector multiplication (AMX / NEON):
        // C (128x1) = A (128xDim) * B (Dimx1)
        projectionMatrix.withUnsafeBufferPointer { matrixPtr in
            embedding.withUnsafeBufferPointer { embedPtr in
                projections.withUnsafeMutableBufferPointer { projPtr in
                    vDSP_mmul(
                        matrixPtr.baseAddress!, 1,
                        embedPtr.baseAddress!, 1,
                        projPtr.baseAddress!, 1,
                        vDSP_Length(128),
                        vDSP_Length(1),
                        vDSP_Length(dim)
                    )
                }
            }
        }

        // Binarize the 128 projections into 4 x 32-bit unsigned integers (128 bits total)
        var hash128 = [UInt32](repeating: 0, count: 4)
        for i in 0..<128 {
            if projections[i] >= 0.0 {
                let wordIndex = i / 32
                let bitIndex = i % 32
                hash128[wordIndex] |= (1 << bitIndex)
            }
        }

        return hash128
    }

    // Backwards-compatible static helper
    public static func generateSimHash(from embedding: [Float], projectionMatrix: [Float]) -> [UInt32] {
        return SimHashProjector.shared.generateSimHash(from: embedding)
    }

    public static func loadOrCreateProjectionMatrix() -> [Float] {
        return SimHashProjector.shared.getProjectionMatrix(dim: 768)
    }

    /// Computes Hamming distance in Swift for validation
    public static func hammingDistance(_ a: [UInt32], _ b: [UInt32]) -> Int {
        guard a.count == 4, b.count == 4 else { return 128 }
        var dist = 0
        for i in 0..<4 {
            dist += (a[i] ^ b[i]).nonzeroBitCount
        }
        return dist
    }
}
