// SPDX-License-Identifier: GPL-3.0-or-later
// Discovery strategy follows WQFiles WQAccess.m (0d9c28c): newest-first
// bounded LaunchServices search, persistent inode identities, incremental scans.
#import "QSDiscovery.h"
#import <sys/fsgetpath.h>
#import <sys/mount.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <time.h>
#import <fcntl.h>
#import <unistd.h>

static NSString *QSPath(uint64_t inode, fsid_t fsid) {
    char buffer[PATH_MAX];
    if (fsgetpath(buffer, sizeof(buffer), &fsid, inode) <= 0) return nil;
    NSString *path = [NSFileManager.defaultManager stringWithFileSystemRepresentation:buffer length:strlen(buffer)];
    if ([path hasPrefix:@"/var/"]) path = [@"/private" stringByAppendingString:path];
    return path;
}
// App data can live on a different APFS volume from /private/var.
// Derive the volume and inode from the same open descriptor, and prove that
// fsgetpath resolves it before trusting either the range or saved progress.
static BOOL QSAppVolume(struct statfs *fs) {
    return statfs(NSTemporaryDirectory().fileSystemRepresentation, fs) == 0;
}
NSDictionary *QSDiscoveryVolume(void) {
    NSString *probe = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    int fd = open(probe.fileSystemRepresentation, O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC, 0600);
    if (fd < 0) return nil;
    struct stat st = {0}; struct statfs fs = {0}, base = {0}, mobile = {0};
    BOOL valid = fstat(fd, &st) == 0 && fstatfs(fd, &fs) == 0 && st.st_ino > 0 && st.st_ino < UINT64_MAX - 100000;
    NSString *resolved = valid ? QSPath(st.st_ino, fs.f_fsid) : nil;
    char physical[PATH_MAX];
    const char *expected = realpath(probe.fileSystemRepresentation, physical);
    BOOL resolvesProbe = expected && resolved && strcmp(expected, resolved.fileSystemRepresentation) == 0;
    close(fd); unlink(probe.fileSystemRepresentation);
    if (!valid || !resolvesProbe) return nil;
    statfs("/private/var", &base); statfs("/private/var/mobile", &mobile);
    char build[64] = {0}; size_t n = sizeof(build); sysctlbyname("kern.osversion", build, &n, NULL, 0);
    NSString *(^volumeID)(struct statfs) = ^NSString *(struct statfs v) {
        return [NSString stringWithFormat:@"%d:%d", v.f_fsid.val[0], v.f_fsid.val[1]];
    };
    return @{ @"volume": volumeID(fs), @"upper": @((uint64_t)st.st_ino + 100000), @"build": @(build),
              @"probeInode": @(st.st_ino), @"varVolume": volumeID(base), @"mobileVolume": volumeID(mobile), @"probeVerified": @YES };
}
NSString *QSDiscoveryResolve(uint64_t inode) {
    struct statfs fs;
    return QSAppVolume(&fs) ? QSPath(inode, fs.f_fsid) : nil;
}
NSString *QSContainerRoot(NSString *input) {
    NSString *path = [input hasPrefix:@"/var/"] ? [@"/private" stringByAppendingString:input] : input;
    static NSArray *roots; static dispatch_once_t once;
    dispatch_once(&once, ^{ roots = @[@"/private/var/mobile/Containers/Data/Application/", @"/private/var/mobile/Containers/Data/PluginKitPlugin/",
        @"/private/var/mobile/Containers/Data/InternalDaemon/", @"/private/var/mobile/Containers/Shared/AppGroup/",
        @"/private/var/containers/Shared/SystemGroup/", @"/private/var/containers/Data/System/"]; });
    for (NSString *base in roots) {
        if (![path hasPrefix:base]) continue;
        NSString *tail = [path substringFromIndex:base.length];
        NSString *name = [tail componentsSeparatedByString:@"/"].firstObject;
        if (name.length) return [base stringByAppendingString:name];
    }
    return nil;
}

static double QSNow(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
NSDictionary *QSDiscoveryBatch(uint64_t first, uint64_t last, BOOL newestFirst, double seconds) {
    if (!first || last < first || last == UINT64_MAX) return nil;
    struct statfs fs; if (!QSAppVolume(&fs)) return nil;
    NSMutableDictionary *containers = [NSMutableDictionary new];
    NSMutableDictionary *witnesses = [NSMutableDictionary new];
    NSString *store = nil; uint64_t inode = newestFirst ? last : first, count = 0;
    double deadline = QSNow() + MAX(0.001, MIN(0.05, seconds));
    for (;;) {
        @autoreleasepool {
            NSString *path = QSPath(inode, fs.f_fsid);
            if (path) {
                NSString *name = path.lastPathComponent;
                if ([name hasPrefix:@"com.apple.LaunchServices-"] && [name hasSuffix:@".csstore"]) store = path;
                // Any file beneath a container reveals its UUID. Waiting to hit
                // only the directory inode needlessly misses useful resolved paths.
                NSString *container = QSContainerRoot(path);
                if (container && !containers[container]) { containers[container] = @(inode); witnesses[container] = path; }
            }
        }
        count++;
        BOOL finished = newestFirst ? inode == first : inode == last;
        uint64_t next = newestFirst ? (inode > 1 ? inode - 1 : 0) : inode + 1;
        if (finished || store || (count % 64 == 0 && QSNow() >= deadline))
            return @{ @"containers": containers, @"witnesses": witnesses, @"store": store ?: @"", @"next": @(next), @"finished": @(finished), @"count": @(count) };
        inode = next;
    }
}
