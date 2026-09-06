// PareEngineBridge.mm - Objective-C++ Bridge Implementation
#import "PareEngineBridge.h"
#include "../CoreEngine/include/PareEngine.h"
#include "../CoreEngine/include/PareComputeEngine.hpp"
#import <os/lock.h>

@implementation PareClusterBridgeResult
@end

@interface PareEngineBridge () {
    std::unique_ptr<pare::compute::PareComputeEngine> _computeEngine;
    id<MTLBuffer> _libraryHashesBuffer;
    uint32_t _libraryCount;
    id<MTLDevice> _device;
    os_unfair_lock _engineLock;
}
@end

@implementation PareEngineBridge

+ (instancetype)sharedEngine {
    static PareEngineBridge *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PareEngineBridge alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _engineLock = OS_UNFAIR_LOCK_INIT;
        _device = MTLCreateSystemDefaultDevice();
        try {
            _computeEngine = std::make_unique<pare::compute::PareComputeEngine>(_device);
        } catch (const std::exception &e) {
            NSLog(@"[PareEngineBridge] Compute engine initialized with CPU fallback: %s", e.what());
        }
    }
    return self;
}

- (void)indexLibraryHashes:(NSArray<NSArray<NSNumber *> *> *)allHashWords {
    const NSUInteger count = [allHashWords count];
    if (count == 0 || !_device) return;

    os_unfair_lock_lock(&_engineLock);
    _libraryCount = static_cast<uint32_t>(count);
    size_t bufferSize = count * sizeof(pare::compute::PareHash128);

    _libraryHashesBuffer = [_device newBufferWithLength:bufferSize
                                                options:MTLResourceStorageModeShared];
    pare::compute::PareHash128 *dst = static_cast<pare::compute::PareHash128*>([_libraryHashesBuffer contents]);

    for (NSUInteger i = 0; i < count; ++i) {
        NSArray<NSNumber *> *words = allHashWords[i];
        if ([words count] >= 4) {
            dst[i].words[0] = [words[0] unsignedIntValue];
            dst[i].words[1] = [words[1] unsignedIntValue];
            dst[i].words[2] = [words[2] unsignedIntValue];
            dst[i].words[3] = [words[3] unsignedIntValue];
        }
    }
    os_unfair_lock_unlock(&_engineLock);
}

- (NSDictionary<NSNumber *, NSArray<NSNumber *> *> *)partitionLSHWithHashes:(NSArray<NSArray<NSNumber *> *> *)hashWords {
    const NSUInteger count = [hashWords count];
    if (count == 0 || !_device || !_computeEngine) {
        return @{};
    }

    [self indexLibraryHashes:hashWords];

    os_unfair_lock_lock(&_engineLock);
    if (!_libraryHashesBuffer) {
        os_unfair_lock_unlock(&_engineLock);
        return @{};
    }

    auto buckets = _computeEngine->execute_streaming_lsh(_libraryHashesBuffer, static_cast<uint32_t>(count));
    os_unfair_lock_unlock(&_engineLock);

    NSMutableDictionary<NSNumber *, NSArray<NSNumber *> *> *dict = [NSMutableDictionary dictionaryWithCapacity:buckets.size()];
    for (const auto &pair : buckets) {
        NSMutableArray<NSNumber *> *arr = [NSMutableArray arrayWithCapacity:pair.second.size()];
        for (uint32_t idx : pair.second) {
            [arr addObject:@(idx)];
        }
        dict[@(pair.first)] = [arr copy];
    }

    return [dict copy];
}

- (PareClusterBridgeResult *)curateWindowWithHashes:(NSArray<NSArray<NSNumber *> *> *)hashWords
                                      qualityScores:(NSArray<NSNumber *> *)qualityScores
                                          fileBytes:(NSArray<NSNumber *> *)fileBytes
                                            targetK:(NSUInteger)targetK
                                     ruthlessnessMu:(float)ruthlessnessMu
                                      qualityLambda:(float)qualityLambda {
    const NSUInteger count = [hashWords count];
    if (count == 0) {
        return [[PareClusterBridgeResult alloc] init];
    }

    std::vector<pare::compute::ImageCandidate> candidates;
    candidates.reserve(count);

    for (NSUInteger i = 0; i < count; ++i) {
        NSArray<NSNumber *> *words = hashWords[i];
        pare::compute::PareHash128 h{};
        if ([words count] >= 4) {
            h.words[0] = [words[0] unsignedIntValue];
            h.words[1] = [words[1] unsignedIntValue];
            h.words[2] = [words[2] unsignedIntValue];
            h.words[3] = [words[3] unsignedIntValue];
        }

        float q = (i < [qualityScores count]) ? [qualityScores[i] floatValue] : 0.5f;
        uint64_t bytes = (i < [fileBytes count]) ? [fileBytes[i] unsignedLongLongValue] : 1024ULL;

        candidates.push_back({
            static_cast<uint32_t>(i),
            h,
            q,
            bytes
        });
    }

    pare::ClusterResult result = pare::PareEngineFacade::curate_window(
        candidates, targetK, ruthlessnessMu, qualityLambda
    );

    PareClusterBridgeResult *bridgeResult = [[PareClusterBridgeResult alloc] init];
    bridgeResult.heroIndex = result.hero_index;
    bridgeResult.reclaimableBytes = result.reclaimable_bytes;
    bridgeResult.coverageScore = result.coverage_score;

    NSMutableArray<NSNumber *> *heroes = [NSMutableArray arrayWithCapacity:result.hero_indices.size()];
    for (uint32_t idx : result.hero_indices) {
        [heroes addObject:@(idx)];
    }
    bridgeResult.heroIndices = [heroes copy];

    NSMutableArray<NSNumber *> *redundant = [NSMutableArray arrayWithCapacity:result.redundant_indices.size()];
    for (uint32_t idx : result.redundant_indices) {
        [redundant addObject:@(idx)];
    }
    bridgeResult.redundantIndices = [redundant copy];

    return bridgeResult;
}

- (nullable NSData *)computeBoundedHammingMatrixForHashes:(NSArray<NSArray<NSNumber *> *> *)bucketHashes {
    const NSUInteger B = [bucketHashes count];
    if (B < 2 || !_device || !_computeEngine) {
        return nil;
    }

    std::vector<pare::compute::PareHash128> hashes;
    hashes.reserve(B);
    for (NSUInteger i = 0; i < B; ++i) {
        NSArray<NSNumber *> *words = bucketHashes[i];
        pare::compute::PareHash128 h{};
        if ([words count] >= 4) {
            h.words[0] = [words[0] unsignedIntValue];
            h.words[1] = [words[1] unsignedIntValue];
            h.words[2] = [words[2] unsignedIntValue];
            h.words[3] = [words[3] unsignedIntValue];
        }
        hashes.push_back(h);
    }

    os_unfair_lock_lock(&_engineLock);
    id<MTLBuffer> mtlBuf = _computeEngine->compute_bounded_neighborhood_matrix(hashes, static_cast<uint32_t>(B));
    os_unfair_lock_unlock(&_engineLock);

    if (!mtlBuf) return nil;

    NSUInteger byteCount = (B * (B - 1)) / 2;
    return [NSData dataWithBytes:[mtlBuf contents] length:byteCount];
}

- (NSArray<NSArray<NSNumber *> *> *)findDuplicateClustersWithHashes:(NSArray<NSArray<NSNumber *> *> *)hashWords
                                                        maxDistance:(uint32_t)maxDistance {
    const NSUInteger N = [hashWords count];
    if (N < 2 || !_device || !_computeEngine) {
        return @[];
    }

    [self indexLibraryHashes:hashWords];

    os_unfair_lock_lock(&_engineLock);
    if (!_libraryHashesBuffer) {
        os_unfair_lock_unlock(&_engineLock);
        return @[];
    }

    std::vector<pare::compute::PareHash128> allHashes;
    allHashes.reserve(N);
    const pare::compute::PareHash128 *ptr = static_cast<const pare::compute::PareHash128 *>([_libraryHashesBuffer contents]);
    for (NSUInteger i = 0; i < N; ++i) {
        allHashes.push_back(ptr[i]);
    }

    auto clusters = _computeEngine->find_duplicate_clusters_gpu(_libraryHashesBuffer, allHashes, maxDistance);
    os_unfair_lock_unlock(&_engineLock);

    NSMutableArray<NSArray<NSNumber *> *> *outClusters = [NSMutableArray arrayWithCapacity:clusters.size()];
    for (const auto &c : clusters) {
        NSMutableArray<NSNumber *> *arr = [NSMutableArray arrayWithCapacity:c.size()];
        for (uint32_t idx : c) {
            [arr addObject:@(idx)];
        }
        [outClusters addObject:[arr copy]];
    }

    return [outClusters copy];
}

- (NSArray<NSArray<NSNumber *> *> *)findDuplicateClustersWithPackedHashes:(NSData *)packedHashes
                                                                    count:(NSUInteger)count
                                                              maxDistance:(uint32_t)maxDistance {
    if (count < 2 || [packedHashes length] < count * sizeof(pare::compute::PareHash128) || !_device || !_computeEngine) {
        return @[];
    }

    os_unfair_lock_lock(&_engineLock);
    _libraryCount = static_cast<uint32_t>(count);
    _libraryHashesBuffer = [_device newBufferWithBytes:[packedHashes bytes]
                                                length:count * sizeof(pare::compute::PareHash128)
                                               options:MTLResourceStorageModeShared];

    const pare::compute::PareHash128 *ptr = static_cast<const pare::compute::PareHash128 *>([_libraryHashesBuffer contents]);
    std::vector<pare::compute::PareHash128> allHashes(ptr, ptr + count);

    auto clusters = _computeEngine->find_duplicate_clusters_gpu(_libraryHashesBuffer, allHashes, maxDistance);
    os_unfair_lock_unlock(&_engineLock);

    NSMutableArray<NSArray<NSNumber *> *> *outClusters = [NSMutableArray arrayWithCapacity:clusters.size()];
    for (const auto &c : clusters) {
        NSMutableArray<NSNumber *> *arr = [NSMutableArray arrayWithCapacity:c.size()];
        for (uint32_t idx : c) {
            [arr addObject:@(idx)];
        }
        [outClusters addObject:[arr copy]];
    }

    return [outClusters copy];
}

@end
