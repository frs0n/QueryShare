#import <Foundation/Foundation.h>
#import "QSDiscovery.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    assert([QSContainerRoot(@"/var/mobile/Containers/Data/Application/UUID/Library/Caches/a.db") isEqual:@"/private/var/mobile/Containers/Data/Application/UUID"]);
    assert([QSContainerRoot(@"/private/var/mobile/Containers/Data/InternalDaemon/UUID/Library/Caches/com.apple.LaunchServices-v2.csstore") isEqual:@"/private/var/mobile/Containers/Data/InternalDaemon/UUID"]);
    assert(QSContainerRoot(@"/private/var/mobile/Library/Caches/a.db") == nil);
    assert(QSDiscoveryBatch(0, 1, YES, 0.01) == nil);
    assert(QSDiscoveryBatch(2, 1, NO, 0.01) == nil);
    NSDictionary *volume = QSDiscoveryVolume(); assert(volume);
    uint64_t upper = [volume[@"upper"] unsignedLongLongValue]; assert(upper > 1);
    NSDate *start = NSDate.date;
    NSDictionary *batch = QSDiscoveryBatch(1, upper, NO, 0.005);
    assert(batch && [batch[@"next"] unsignedLongLongValue] > 1);
    assert(-[start timeIntervalSinceNow] < 1);
    NSDictionary *reverse = QSDiscoveryBatch(1, upper, YES, 0.005);
    assert(reverse && [reverse[@"next"] unsignedLongLongValue] < upper);
    puts("PASS bounded inode batches, direction, progress and invalid ranges");
} return 0; }
