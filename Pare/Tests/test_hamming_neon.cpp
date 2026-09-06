// test_hamming_neon.cpp - Hardware ARM NEON Bitwise Parity & Benchmark Test
#include "../CoreEngine/include/PareHamming.h"
#include <iostream>
#include <cassert>
#include <chrono>
#include <random>

using namespace pare::compute;

int main() {
    std::cout << "========================================================\n";
    std::cout << "TEST 1: ARM NEON 128-BIT HAMMING POPCOUNT VERIFICATION\n";
    std::cout << "========================================================\n";

    // 1. Verify Memory Alignment
    static_assert(alignof(PareHash128) == 16, "PareHash128 must be 16-byte aligned for NEON load/store");
    static_assert(sizeof(PareHash128) == 16, "PareHash128 must be exactly 16 bytes (128 bits)");
    std::cout << "[PASS] Memory alignment & size verified (16 bytes, alignas 16)\n";

    // 2. Exact Bitwise Tests
    PareHash128 zero(0ULL, 0ULL);
    PareHash128 all_ones(~0ULL, ~0ULL);
    assert(pare_hamming_distance(zero, zero) == 0);
    assert(pare_hamming_distance(zero, all_ones) == 128);
    assert(pare_hamming_distance(all_ones, zero) == 128);
    assert(pare_hamming_distance(all_ones, all_ones) == 0);

    PareHash128 one_bit(1ULL, 0ULL);
    assert(pare_hamming_distance(zero, one_bit) == 1);
    assert(pare_similarity(zero, zero) == 1.0f);
    assert(pare_similarity(zero, all_ones) == 0.0f);
    std::cout << "[PASS] Deterministic bitwise boundary values verified\n";

    // 3. Fuzz Test 1,000,000 Random Vector Pairs against Scalar Popcount Reference
    std::mt19937_64 rng(0x45524150); // Seed 'PARE'
    constexpr size_t NUM_TRIALS = 1'000'000;

    auto start_time = std::chrono::high_resolution_clock::now();
    uint64_t total_distance = 0;

    for (size_t i = 0; i < NUM_TRIALS; ++i) {
        PareHash128 a(rng(), rng());
        PareHash128 b(rng(), rng());

        uint32_t neon_dist = pare_hamming_distance(a, b);
        uint32_t scalar_ref = static_cast<uint32_t>(
            __builtin_popcountll(a.lo ^ b.lo) + __builtin_popcountll(a.hi ^ b.hi)
        );

        if (neon_dist != scalar_ref) {
            std::cerr << "[FAIL] Divergence at trial " << i << ": NEON=" << neon_dist << " Scalar=" << scalar_ref << "\n";
            return 1;
        }
        total_distance += neon_dist;
    }

    auto end_time = std::chrono::high_resolution_clock::now();
    auto elapsed_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(end_time - start_time).count();
    double ns_per_op = static_cast<double>(elapsed_ns) / NUM_TRIALS;

    std::cout << "[PASS] 1,000,000 random pairs verified with 100% bitwise parity!\n";
    std::cout << "       Average latency: " << ns_per_op << " ns per 128-bit comparison\n";
    std::cout << "       Throughput: " << (1000.0 / ns_per_op) << " million comparisons/sec per core\n\n";

    return 0;
}
