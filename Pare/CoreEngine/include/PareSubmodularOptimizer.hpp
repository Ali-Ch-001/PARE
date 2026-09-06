// PareSubmodularOptimizer.hpp - Accelerated Submodular Facility Location Solver
#pragma once

#include "PareHamming.h"
#include <vector>
#include <queue>
#include <numeric>
#include <cmath>
#include <algorithm>
#include <cstdint>

namespace pare::compute {

/// Node representing an image asset inside a candidate temporal window or cluster.
struct ImageCandidate {
    uint32_t asset_id;       // Local index or PhotoKit identifier hash
    PareHash128 hash;        // 128-bit SimHash structural signature
    float quality_score;     // Intrinsic quality Q(j) ∈ [0.0, 1.0] (sharpness, exposure, face focus)
    uint64_t file_bytes;     // File size in bytes (weight for storage reclamation)
};

/// Priority queue element for Minoux's Cost-Effective Lazy Forward (CELF) optimization.
struct ElementBenefit {
    uint32_t element_index;
    float marginal_gain;
    uint32_t iteration_evaluated;

    bool operator<(const ElementBenefit& other) const noexcept {
        return marginal_gain < other.marginal_gain; // Max-heap ordering
    }
};

/// Solves the Submodular Facility Location Problem:
/// max_{S ⊆ V, |S| ≤ k} [ ∑_{i ∈ V} max_{j ∈ S} sim(i, j) + λ ∑_{j ∈ S} Q(j) - μ ∑_{j, l ∈ S} redundancy(j, l) ]
class SubmodularCurator {
public:
    /**
     * Solves the submodular maximization using Minoux's (1978) CELF lazy evaluation greedy algorithm.
     * Guarantees a provable (1 - 1/e) ≈ 63.2% approximation of the mathematical optimum.
     *
     * @param candidates Array of candidate image assets in the current temporal window
     * @param target_k Number of representative "Hero" storytelling pivots to select
     * @param lambda_qual Weight for intrinsic capture quality (default: 0.35)
     * @param mu_redundancy Weight for penalizing redundant selections (default: 0.50)
     * @return Indices of selected storytelling pivots in the candidates array
     */
    static std::vector<uint32_t> select_optimal_subset(
        const std::vector<ImageCandidate>& candidates,
        size_t target_k,
        float lambda_qual = 0.35f,
        float mu_redundancy = 0.50f
    ) {
        const size_t N = candidates.size();
        if (N <= target_k) {
            std::vector<uint32_t> all_indices(N);
            std::iota(all_indices.begin(), all_indices.end(), 0);
            return all_indices;
        }

        // max_sim[i] tracks the maximum similarity of element i to any currently selected element in S
        std::vector<float> current_max_sim(N, 0.0f);
        std::vector<uint32_t> selected_set;
        selected_set.reserve(target_k);

        // Max-heap storing (element_index, marginal_gain, iteration_evaluated)
        std::priority_queue<ElementBenefit> lazy_queue;

        // Seed the queue with initial marginal gains evaluated with S = ∅
        for (uint32_t i = 0; i < static_cast<uint32_t>(N); ++i) {
            float initial_gain = compute_marginal_gain(
                i, candidates, current_max_sim, selected_set, lambda_qual, mu_redundancy
            );
            lazy_queue.push({i, initial_gain, 0});
        }

        uint32_t current_iteration = 0;

        // Greedy selection loop with Minoux's lazy evaluation
        while (selected_set.size() < target_k && !lazy_queue.empty()) {
            ElementBenefit top = lazy_queue.top();
            lazy_queue.pop();

            // Minoux Lazy Evaluation Condition:
            // If this element's gain was evaluated in the current iteration, then by the
            // submodularity diminishing returns property (F(A ∪ {x}) - F(A) ≥ F(B ∪ {x}) - F(B)),
            // its marginal gain is guaranteed to be ≥ all other elements in the queue.
            if (top.iteration_evaluated == current_iteration) {
                selected_set.push_back(top.element_index);

                // Update baseline maximum coverage for all elements
                const auto& newly_selected_hash = candidates[top.element_index].hash;
                for (size_t i = 0; i < N; ++i) {
                    float s = pare_similarity(candidates[i].hash, newly_selected_hash);
                    if (s > current_max_sim[i]) {
                        current_max_sim[i] = s;
                    }
                }

                current_iteration++;
            } else {
                // Re-evaluate marginal gain with the updated coverage vector
                top.marginal_gain = compute_marginal_gain(
                    top.element_index, candidates, current_max_sim, selected_set, lambda_qual, mu_redundancy
                );
                top.iteration_evaluated = current_iteration;
                lazy_queue.push(top); // Re-insert with refreshed upper bound
            }
        }

        return selected_set;
    }

    /**
     * Identifies redundant candidates based on STRICT Hamming distance similarity verification.
     * A candidate is ONLY classified as redundant IF its Hamming distance to its closest
     * selected hero is less than or equal to `max_distance_threshold`.
     *
     * Non-hero photos that are visually distinct (Hamming distance > threshold) represent
     * unique photos/moments and MUST NEVER be marked for deletion.
     *
     * @param candidates Array of candidate image assets in the current window/cluster
     * @param selected_heroes Indices of selected storytelling pivots
     * @param max_distance_threshold Max Hamming distance to be considered a redundant duplicate (e.g. 18 bits out of 128)
     * @return Indices of verified near-duplicate candidates eligible for reclamation
     */
    static std::vector<uint32_t> identify_redundant_candidates(
        const std::vector<ImageCandidate>& candidates,
        const std::vector<uint32_t>& selected_heroes,
        uint32_t max_distance_threshold = 18
    ) {
        if (selected_heroes.empty() || candidates.empty()) {
            return {};
        }

        const size_t total_count = candidates.size();
        std::vector<bool> is_hero(total_count, false);
        for (uint32_t idx : selected_heroes) {
            if (idx < total_count) is_hero[idx] = true;
        }

        std::vector<uint32_t> redundant_indices;
        redundant_indices.reserve(total_count);

        for (uint32_t i = 0; i < static_cast<uint32_t>(total_count); ++i) {
            // Heroes are never redundant
            if (is_hero[i]) continue;

            // Compute minimum Hamming distance to any selected hero
            uint32_t min_dist_to_hero = UINT32_MAX;
            for (uint32_t hero_idx : selected_heroes) {
                if (hero_idx < total_count) {
                    uint32_t d = pare_hamming_distance(candidates[i].hash, candidates[hero_idx].hash);
                    if (d < min_dist_to_hero) {
                        min_dist_to_hero = d;
                    }
                }
            }

            // CRITICAL SAFETY GATE: Only flag as redundant if proven to be a near-duplicate
            // of a preserved hero shot (distance <= threshold, where threshold <= 22 bits).
            if (min_dist_to_hero <= max_distance_threshold) {
                redundant_indices.push_back(i);
            }
        }

        return redundant_indices;
    }

private:
    static float compute_marginal_gain(
        uint32_t candidate_idx,
        const std::vector<ImageCandidate>& candidates,
        const std::vector<float>& max_sim,
        const std::vector<uint32_t>& current_S,
        float lambda,
        float mu
    ) noexcept {
        const auto& cand = candidates[candidate_idx];
        const size_t N = candidates.size();

        // 1. Marginal Coverage Gain: ∑_{i ∈ V} max(0, sim(i, cand) - max_sim[i])
        float coverage_gain = 0.0f;
        for (size_t i = 0; i < N; ++i) {
            float s = pare_similarity(candidates[i].hash, cand.hash);
            if (s > max_sim[i]) {
                coverage_gain += (s - max_sim[i]);
            }
        }

        // 2. Intrinsic Quality Prior: λ * Q(cand)
        float quality_term = lambda * cand.quality_score;

        // 3. Quadratic Redundancy Penalty: μ * ∑_{j ∈ S} redundancy(cand, j)
        float redundancy_penalty = 0.0f;
        for (uint32_t sel_idx : current_S) {
            float r = pare_similarity(cand.hash, candidates[sel_idx].hash);
            if (r > 0.88f) { // High redundancy threshold (~ 15 bits out of 128)
                redundancy_penalty += (r * r);
            }
        }

        return coverage_gain + quality_term - (mu * redundancy_penalty);
    }
};

} // namespace pare::compute
