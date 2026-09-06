// PareHamming.h - Low-Level Hardware-Accelerated 128-bit Hamming Metric
#pragma once

#include <cstdint>
#include <cmath>

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#endif

namespace pare::compute {

/// Aligned 128-bit hash structure representing the discrete SimHash signature.
/// Memory layout matches uint4 in Metal Shading Language and fits in an ARM NEON 128-bit register.
struct alignas(16) PareHash128 {
    union {
        struct {
            uint64_t lo;
            uint64_t hi;
        };
        uint32_t words[4];
        uint8_t bytes[16];
    };

    constexpr PareHash128() noexcept : lo(0), hi(0) {}
    constexpr PareHash128(uint64_t l, uint64_t h) noexcept : lo(l), hi(h) {}
    constexpr PareHash128(uint32_t w0, uint32_t w1, uint32_t w2, uint32_t w3) noexcept 
        : words{w0, w1, w2, w3} {}

    bool operator==(const PareHash128& other) const noexcept {
        return lo == other.lo && hi == other.hi;
    }

    bool operator!=(const PareHash128& other) const noexcept {
        return !(*this == other);
    }
};

/// Hardware-accelerated 128-bit Hamming distance calculation.
/// On Apple Silicon (ARM64), executes via single-cycle vector XOR (veorq_u64)
/// and hardware vector bit-count (vcntq_u8).
inline uint32_t pare_hamming_distance(const PareHash128& a, const PareHash128& b) noexcept {
#if defined(__ARM_NEON) || defined(__ARM_NEON__)
    uint64x2_t va = vcombine_u64(vcreate_u64(a.lo), vcreate_u64(a.hi));
    uint64x2_t vb = vcombine_u64(vcreate_u64(b.lo), vcreate_u64(b.hi));
    uint64x2_t v_xor = veorq_u64(va, vb);
    
    // vcntq_u8 counts set bits per 8-bit lane in parallel
    uint8x16_t bit_counts = vcntq_u8(vreinterpretq_u8_u64(v_xor));
    // Vector pairwise add reduction across all 16 lanes into a scalar
    return vaddlvq_u8(bit_counts);
#else
    return static_cast<uint32_t>(__builtin_popcountll(a.hi ^ b.hi) + __builtin_popcountll(a.lo ^ b.lo));
#endif
}

/// Normalized structural similarity in [0.0, 1.0].
/// Distance 0 -> 1.0 (identical structural layout).
/// Distance 64 -> 0.5 (uncorrelated random hashes).
/// Distance 128 -> 0.0 (exact bitwise inversion).
inline float pare_similarity(const PareHash128& a, const PareHash128& b) noexcept {
    const uint32_t dist = pare_hamming_distance(a, b);
    return 1.0f - (static_cast<float>(dist) / 128.0f);
}

} // namespace pare::compute
