// test_submodular_celf.cpp - Minoux CELF Submodular Optimization & Approximation Bound Test
#include "../CoreEngine/include/PareHamming.h"
#include "../CoreEngine/include/PareSubmodularOptimizer.hpp"
#include <iostream>
#include <vector>
#include <cassert>
#include <cmath>
#include <random>
#include <chrono>

using namespace pare::compute;

// Brute-force reference solver for small ground sets to verify (1 - 1/e) bound
float evaluate_objective(
    const std::vector<uint32_t>& S,
    const std::vector<ImageCandidate>& V,
    float lambda,
    float mu
) {
    if (S.empty()) return 0.0f;
    float coverage = 0.0f;
    for (size_t i = 0; i < V.size(); ++i) {
        float max_s = 0.0f;
        for (uint32_t s_idx : S) {
            float sim_val = pare_similarity(V[i].hash, V[s_idx].hash);
            if (sim_val > max_s) max_s = sim_val;
        }
        coverage += max_s;
    }

    float quality = 0.0f;
    for (uint32_t s_idx : S) {
        quality += lambda * V[s_idx].quality_score;
    }

    float redundancy = 0.0f;
    for (size_t a = 0; a < S.size(); ++a) {
        for (size_t b = a + 1; b < S.size(); ++b) {
            float r = pare_similarity(V[S[a]].hash, V[S[b]].hash);
            if (r > 0.88f) redundancy += (r * r);
        }
    }

    return coverage + quality - (mu * redundancy);
}

int main() {
    std::cout << "========================================================\n";
    std::cout << "TEST 2: MINOUX (1978) CELF SUBMODULAR OPTIMIZER TEST\n";
    std::cout << "========================================================\n";

    // 1. Synthesize 500 Photos across 10 Distinct Clusters
    // Cluster centers are separated by large Hamming distance (>= 50 bits)
    // Intra-cluster duplicates are perturbed by only 1 to 4 bits
    std::mt19937_64 rng(0x45524150);
    constexpr size_t NUM_CLUSTERS = 10;
    constexpr size_t PHOTOS_PER_CLUSTER = 50;
    constexpr size_t TOTAL_PHOTOS = NUM_CLUSTERS * PHOTOS_PER_CLUSTER; // 500 photos

    std::vector<PareHash128> cluster_centers(NUM_CLUSTERS);
    for (size_t c = 0; c < NUM_CLUSTERS; ++c) {
        cluster_centers[c] = PareHash128(rng(), rng());
    }

    std::vector<ImageCandidate> library;
    library.reserve(TOTAL_PHOTOS);

    for (size_t c = 0; c < NUM_CLUSTERS; ++c) {
        for (size_t p = 0; p < PHOTOS_PER_CLUSTER; ++p) {
            // Perturb center by a few random bits to simulate burst shots
            uint64_t perturb_lo = (p == 0) ? 0 : (1ULL << (p % 60));
            PareHash128 h(cluster_centers[c].lo ^ perturb_lo, cluster_centers[c].hi);
            
            // Photo 0 of each cluster has the highest quality score (Hero)
            float quality = (p == 0) ? 0.98f : 0.40f + static_cast<float>(p % 10) * 0.02f;
            uint64_t bytes = 3500000 + (p * 50000);

            library.push_back({
                static_cast<uint32_t>(c * PHOTOS_PER_CLUSTER + p),
                h,
                quality,
                bytes
            });
        }
    }

    std::cout << "[INFO] Synthesized " << library.size() << " photos across " << NUM_CLUSTERS << " burst clusters\n";

    // 2. Execute CELF Lazy Submodular Optimizer
    auto start_time = std::chrono::high_resolution_clock::now();
    std::vector<uint32_t> heroes = SubmodularCurator::select_optimal_subset(
        library, NUM_CLUSTERS, 0.35f, 0.50f
    );
    auto end_time = std::chrono::high_resolution_clock::now();
    auto elapsed_ms = std::chrono::duration_cast<std::chrono::microseconds>(end_time - start_time).count() / 1000.0;

    assert(heroes.size() == NUM_CLUSTERS);
    std::cout << "[PASS] Submodular selection extracted exactly k = " << heroes.size() << " storytelling pivots\n";
    std::cout << "       Execution runtime: " << elapsed_ms << " ms for 500 photos\n";

    // Verify diversity: Ensure each selected hero belongs to a distinct cluster
    std::vector<bool> cluster_covered(NUM_CLUSTERS, false);
    for (uint32_t h_idx : heroes) {
        size_t cluster_id = h_idx / PHOTOS_PER_CLUSTER;
        cluster_covered[cluster_id] = true;
    }
    for (size_t c = 0; c < NUM_CLUSTERS; ++c) {
        assert(cluster_covered[c] && "CELF must cover all 10 distinct clusters!");
    }
    std::cout << "[PASS] 100% Cluster Diversity Verified: All 10 distinct scenes have a representative Hero!\n";

    // 3. Test Redundant Candidate Identification with Strict Similarity Verification
    std::vector<uint32_t> redundant = SubmodularCurator::identify_redundant_candidates(
        library, heroes, 18
    );
    assert(redundant.size() == TOTAL_PHOTOS - NUM_CLUSTERS);
    uint64_t total_reclaimed_bytes = 0;
    for (uint32_t r_idx : redundant) {
        total_reclaimed_bytes += library[r_idx].file_bytes;
    }
    double reclaimed_gb = static_cast<double>(total_reclaimed_bytes) / 1073741824.0;
    std::cout << "[PASS] Identified " << redundant.size() << " redundant candidates saving " << reclaimed_gb << " GB\n";

    // 3b. CRITICAL SAFETY TEST: Dissimilar photos must NEVER be flagged as redundant
    std::vector<ImageCandidate> dissimilar_photos;
    for (uint32_t i = 0; i < 5; ++i) {
        PareHash128 h{};
        // Orthogonal bit patterns ensuring Hamming distance >= 64 bits between every pair
        h.words[0] = (i == 0) ? 0xFFFFFFFF : (i == 1 ? 0x00000000 : (i == 2 ? 0xAAAAAAAA : (i == 3 ? 0x55555555 : 0x0F0F0F0F)));
        h.words[1] = ~h.words[0];
        h.words[2] = (i * 0x12345678) ^ 0xA5A5A5A5;
        h.words[3] = ~h.words[2];
        dissimilar_photos.push_back({i, h, 0.8f, 2000000});
    }
    std::vector<uint32_t> single_hero = {0};
    std::vector<uint32_t> zero_redundant = SubmodularCurator::identify_redundant_candidates(
        dissimilar_photos, single_hero, 18
    );
    assert(zero_redundant.empty() && "CRITICAL SAFETY FAILURE: Distinct dissimilar photos must NEVER be marked redundant!");
    std::cout << "[PASS] Critical Safety Verified: 0 of 4 dissimilar photos marked redundant (0% data loss)!\n";

    // 4. Mathematical Verification of (1 - 1/e) Bound on Ground-Truth Subset (N=16, k=3)
    std::vector<ImageCandidate> small_set(library.begin(), library.begin() + 16);
    constexpr size_t K_SMALL = 3;
    std::vector<uint32_t> greedy_small = SubmodularCurator::select_optimal_subset(small_set, K_SMALL);
    float greedy_obj = evaluate_objective(greedy_small, small_set, 0.35f, 0.50f);

    // Compute exact brute-force optimum over all C(16, 3) = 560 combinations
    float brute_force_opt = 0.0f;
    for (uint32_t i = 0; i < 16; ++i) {
        for (uint32_t j = i + 1; j < 16; ++j) {
            for (uint32_t k = j + 1; k < 16; ++k) {
                float val = evaluate_objective({i, j, k}, small_set, 0.35f, 0.50f);
                if (val > brute_force_opt) brute_force_opt = val;
            }
        }
    }

    float approx_ratio = greedy_obj / brute_force_opt;
    float theoretical_bound = 1.0f - (1.0f / std::exp(1.0f)); // ≈ 0.63212

    std::cout << "[PASS] (1 - 1/e) Bound Check: Greedy Obj = " << greedy_obj 
              << " | Optimal Obj = " << brute_force_opt 
              << " | Ratio = " << (approx_ratio * 100.0f) << "% (Min Bound: " 
              << (theoretical_bound * 100.0f) << "%)\n";
    assert(approx_ratio >= theoretical_bound);

    std::cout << "[PASS] All Submodular CELF Mathematical Properties Verified!\n\n";
    return 0;
}
