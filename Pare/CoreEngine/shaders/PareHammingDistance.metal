// PareHammingDistance.metal - Low-Level Apple Silicon GPU Compute Pipeline
#include <metal_stdlib>
using namespace metal;

typedef uint4 PareHash128;

// =========================================================================
// KERNEL 1: Multi-Table Locality-Sensitive Hashing (L=4 tables × 8 bits each)
// Partitions hashes into 4 independent 8-bit tables (256 buckets each).
// Multi-table union achieves >= 90.4% recall on near-duplicate pairs (d <= 12).
// Output buffer is N × 4 bytes (1 byte per table for each photo).
// =========================================================================
kernel void compute_lsh_multi_table(
    constant PareHash128*   hashArray         [[buffer(0)]],
    constant uint*          tableBitIndices   [[buffer(1)]], // 4 tables × 8 bit positions = 32 uints
    device   uint8_t*       outMultiBucketIDs [[buffer(2)]], // N × 4 bytes
    constant uint&          totalCount        [[buffer(3)]],
    uint                    gid               [[thread_position_in_grid]]
) {
    if (gid >= totalCount) return;

    PareHash128 item = hashArray[gid];

    for (uint t = 0; t < 4; ++t) {
        uint8_t bucket = 0;
        for (uint p = 0; p < 8; ++p) {
            uint bitIdx = tableBitIndices[t * 8 + p] & 127u;
            uint wordIdx = bitIdx / 32u;
            uint bitPos = bitIdx % 32u;
            uint w = (wordIdx == 0) ? item.x : ((wordIdx == 1) ? item.y : ((wordIdx == 2) ? item.z : item.w));
            if ((w >> bitPos) & 1u) {
                bucket |= (1u << p);
            }
        }
        outMultiBucketIDs[gid * 4 + t] = bucket;
    }
}

// Single-table LSH kernel preserved for backwards compatibility
kernel void compute_streaming_lsh_buckets(
    constant PareHash128*   hashArray         [[buffer(0)]],
    constant uint*          bitIndices        [[buffer(1)]], // 8 bit coordinates in [0, 127]
    device   uint8_t*       outBucketIDs      [[buffer(2)]],
    constant uint&          totalCount        [[buffer(3)]],
    uint                    gid               [[thread_position_in_grid]]
) {
    if (gid >= totalCount) return;

    PareHash128 item = hashArray[gid];
    uint8_t bucketID = 0;

    for (uint p = 0; p < 8; ++p) {
        uint bitIdx = bitIndices[p] & 127u;
        uint wordIdx = bitIdx / 32u;
        uint bitPos = bitIdx % 32u;
        uint w = (wordIdx == 0) ? item.x : ((wordIdx == 1) ? item.y : ((wordIdx == 2) ? item.z : item.w));
        if ((w >> bitPos) & 1u) {
            bucketID |= (1u << p);
        }
    }

    outBucketIDs[gid] = bucketID;
}

// =========================================================================
// KERNEL 2: Bounded Graph Neighborhood Hamming Distance
// Computes pairwise distances ONLY within an isolated bucket of size B
// Output size is strictly B * (B - 1) / 2 bytes (e.g., 20 photos = 190 bytes)
// =========================================================================
kernel void compute_bounded_neighborhood_hamming(
    constant PareHash128*   bucketHashes      [[buffer(0)]],
    device   uint8_t*       outTriangularDist [[buffer(1)]],
    constant uint&          bucketCount       [[buffer(2)]],
    uint2                   gid               [[thread_position_in_grid]]
) {
    uint i = gid.y;
    uint j = gid.x;

    if (i >= bucketCount || j >= bucketCount || i >= j) return;

    PareHash128 a = bucketHashes[i];
    PareHash128 b = bucketHashes[j];
    PareHash128 diff = a ^ b;

    // Single-cycle native popcount instruction on Apple Silicon GPU ALUs
    uint dist = popcount(diff.x) + popcount(diff.y) + popcount(diff.z) + popcount(diff.w);

    // Packed upper-triangular index within the bounded neighborhood
    ulong rowOffset = ulong(i) * ulong(bucketCount) - (ulong(i) * (ulong(i) + 1ul)) / 2ul;
    ulong packedIdx = rowOffset + ulong(j - i - 1u);

    outTriangularDist[packedIdx] = static_cast<uint8_t>(dist);
}
