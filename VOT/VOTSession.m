#import "VOTSession.h"
@implementation VOTSession
- (instancetype)init {
    self = [super init];
    if (self) {
        _uuid = @"";
        _secretKey = @"";
        _expires = 0;
        _createdAt = [NSDate dateWithTimeIntervalSince1970:0];
    }
    return self;
}
- (BOOL)isValid {
    if (!self.parseValid || self.uuid.length == 0 || self.secretKey.length == 0 || self.expires <= 0) return NO;
    return [[NSDate date] timeIntervalSinceDate:self.createdAt] < self.expires;
}
@end
