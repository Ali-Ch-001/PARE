// PareEngine.h - Public C++ API Interface for Pare Engine
#pragma once

#include "PareHamming.h"
#include "PareSubmodularOptimizer.hpp"
#include <vector>
#include <string>
#include <cstdint>

namespace pare {

/// Result structure for a curated event or cluster
struct ClusterResult {
    uint32_t cluster_id;
    uint32_t hero_index;
    std::vector<uint32_t> hero_indices;        // Selected storytelling pivots
    std::vector<uint32_t> redundant_indices;   // Redundant candidates flagged for review/reclamation
    uint64_t reclaimable_bytes;                // Sum of redundant file weights
    float coverage_score;                      // Submodular objective value F(S)
};

class PareEngineFacade {
public:
    static ClusterResult curate_window(
        const std::vector<compute::ImageCandidate>& window_candidates,
        size_t target_k,
        float ruthlessness_mu = 0.50f,
        float quality_lambda = 0.35f
    ) {
        ClusterResult result{};
        if (window_candidates.empty()) return result;

        result.hero_indices = compute::SubmodularCurator::select_optimal_subset(
            window_candidates, target_k, quality_lambda, ruthlessness_mu
        );

        if (!result.hero_indices.empty()) {
            result.hero_index = result.hero_indices.front();
        }

        // Monotonic Ruthlessness Threshold:
        // Gentle (< 0.35): max_dist = 10 bits (~92.2% bitwise similarity)
        // Balanced (0.35 ..< 0.70): max_dist = 15 bits (~88.3% bitwise similarity)
        // Thorough (>= 0.70): max_dist = 20 bits (~84.4% bitwise similarity)
        float clamped_mu = std::clamp(ruthlessness_mu, 0.0f, 1.0f);
        uint32_t max_dist;
        if (clamped_mu < 0.35f) {
            max_dist = 10;
        } else if (clamped_mu < 0.70f) {
            max_dist = 15;
        } else {
            max_dist = 20;
        }

        result.redundant_indices = compute::SubmodularCurator::identify_redundant_candidates(
            window_candidates, result.hero_indices, max_dist
        );

        result.reclaimable_bytes = 0;
        for (uint32_t red_idx : result.redundant_indices) {
            result.reclaimable_bytes += window_candidates[red_idx].file_bytes;
        }

        return result;
    }
};

} // namespace pare
