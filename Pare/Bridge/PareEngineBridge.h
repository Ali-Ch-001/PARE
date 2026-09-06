// PareEngineBridge.h - Objective-C Interface to Pare C++20 Core Engine
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PareClusterBridgeResult : NSObject
@property (nonatomic, assign) uint32_t heroIndex;
@property (nonatomic, copy) NSArray<NSNumber *> *heroIndices;
@property (nonatomic, copy) NSArray<NSNumber *> *redundantIndices;
@property (nonatomic, assign) uint64_t reclaimableBytes;
@property (nonatomic, assign) float coverageScore;
@end

@interface PareEngineBridge : NSObject

+ (instancetype)sharedEngine;

/**
 * Curates a candidate window using the C++20 submodular facility location engine.
 *
 * @param hashWords Array of 128-bit hashes, each packed as 4 x uint32 numbers [w0, w1, w2, w3]
 * @param qualityScores Normalized intrinsic quality scores in [0.0, 1.0]
 * @param fileBytes File sizes in bytes for knapsack weight computation
 * @param targetK Number of storytelling pivots to extract
 * @param ruthlessnessMu Redundancy penalty coefficient (0.2 to 0.8)
 * @param qualityLambda Quality score prior weight (default: 0.35)
 */
- (PareClusterBridgeResult *)curateWindowWithHashes:(NSArray<NSArray<NSNumber *> *> *)hashWords
                                      qualityScores:(NSArray<NSNumber *> *)qualityScores
                                          fileBytes:(NSArray<NSNumber *> *)fileBytes
                                            targetK:(NSUInteger)targetK
                                     ruthlessnessMu:(float)ruthlessnessMu
                                      qualityLambda:(float)qualityLambda;

/**
 * Uploads/indexes an array of 128-bit hashes into a shared GPU buffer for sub-millisecond querying.
 */
- (void)indexLibraryHashes:(NSArray<NSArray<NSNumber *> *> *)allHashWords;

/**
 * Dispatches the Metal compute kernel to partition hashes into LSH buckets in O(N) time.
 * Returns a dictionary mapping bucketID -> array of photo indices.
 */
- (NSDictionary<NSNumber *, NSArray<NSNumber *> *> *)partitionLSHWithHashes:(NSArray<NSArray<NSNumber *> *> *)hashWords;

/**
 * Computes exact triangular Hamming distances for a bounded bucket of hashes on Apple Silicon GPU.
 * Returns NSData containing B * (B - 1) / 2 bytes.
 */
- (nullable NSData *)computeBoundedHammingMatrixForHashes:(NSArray<NSArray<NSNumber *> *> *)bucketHashes;

/**
 * Full GPU Pipeline: Dispatches L=4 Multi-Table LSH + Bounded Triangular Hamming Popcount on Metal GPU.
 * Returns array of candidate clusters, where each cluster contains photo indices with verified distance <= maxDistance.
 */
- (NSArray<NSArray<NSNumber *> *> *)findDuplicateClustersWithHashes:(NSArray<NSArray<NSNumber *> *> *)hashWords
                                                        maxDistance:(uint32_t)maxDistance;

/**
 * Zero-Allocation GPU Pipeline: Uses a contiguous raw byte buffer (16 bytes per 128-bit hash)
 * bypassing all NSNumber heap boxing for 50,000 photos.
 */
- (NSArray<NSArray<NSNumber *> *> *)findDuplicateClustersWithPackedHashes:(NSData *)packedHashes
                                                                    count:(NSUInteger)count
                                                              maxDistance:(uint32_t)maxDistance;

@end

NS_ASSUME_NONNULL_END
