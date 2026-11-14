// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "QSLaunchServices.h"
#include <assert.h>
static void put(NSMutableData *data, NSUInteger at, uint32_t value) { memcpy((uint8_t *)data.mutableBytes + at, &value, 4); }
static NSData *fixture(uint32_t recordSize, uint32_t pathOffset, uint32_t nameOffset, uint32_t displayOffset) {
    NSMutableData *data = [NSMutableData dataWithLength:0x3000];
    uint8_t *b = data.mutableBytes; memcpy(b, "bdsl", 4);
    put(data, 0x204, recordSize);
    put(data, 0x208 + 0x0c, 4);
    put(data, 0x208 + nameOffset, 8); put(data, 0x208 + displayOffset, 12);
    put(data, 0x208 + pathOffset, 16);
    NSArray *strings = @[@"com.example.demo", @"Demo", @"测试 Demo", @"/var/mobile/Containers/Data/Application/12345678-1234-1234-1234-123456789ABC"];
    for (NSUInteger i = 0; i < strings.count; i++) {
        NSUInteger at = 0x1000 + i * 0x100; NSData *utf8 = [strings[i] dataUsingEncoding:NSUTF8StringEncoding];
        put(data, at, (uint32_t)i + 1); put(data, at + 4, (uint32_t)utf8.length); memcpy(b + at + 8, utf8.bytes, utf8.length);
    }
    return data;
}
int main(void) { @autoreleasepool {
    for (NSArray *layout in @[@[@0x250,@0x68,@0x6c,@0x74], @[@0x23c,@0x64,@0x68,@0x70], @[@0x25c,@0x6c,@0x70,@0x78]]) {
        NSData *data = fixture([layout[0] unsignedIntValue],[layout[1] unsignedIntValue],[layout[2] unsignedIntValue],[layout[3] unsignedIntValue]);
        NSDictionary *index = QSParseLaunchServices(data, nil);
        assert(index);
        NSString *path = @"/private/var/mobile/Containers/Data/Application/12345678-1234-1234-1234-123456789ABC";
        assert([index[@"identifiers"][path] isEqual:@"com.example.demo"]);
        assert([index[@"names"][@"com.example.demo"] isEqual:@"测试 Demo"]);
        assert([index[@"paths"] containsObject:path]);
    }
    assert(QSParseLaunchServices([NSData data], nil) == nil);
    NSMutableData *invalid = [NSMutableData dataWithLength:8192]; assert(QSParseLaunchServices(invalid, nil) == nil);
    // Truncated records and hostile lengths must not read beyond the buffer.
    for (NSUInteger n = 0; n < 8192; n += 127) {
        NSData *data = fixture(0x250,0x68,0x6c,0x74);
        QSParseLaunchServices([data subdataWithRange:NSMakeRange(0,n)], nil);
    }
    puts("PASS CSStore 26/27.0/27.2 layouts, Unicode labels, invalid magic and truncated inputs");
} return 0; }
