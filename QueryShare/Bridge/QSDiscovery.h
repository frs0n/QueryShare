// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
NSDictionary<NSString *, id> * _Nullable QSDiscoveryVolume(void);
NSString * _Nullable QSDiscoveryResolve(uint64_t inode);
// Bounded work; next is the first unexamined inode. Database search walks down.
NSDictionary<NSString *, id> * _Nullable QSDiscoveryBatch(uint64_t first, uint64_t last, BOOL newestFirst, double seconds);
NSString * _Nullable QSContainerRoot(NSString *path);
NS_ASSUME_NONNULL_END
