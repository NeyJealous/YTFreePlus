#import "VOTSigner.h"
#import "VOTConfig.h"
#import <CommonCrypto/CommonHMAC.h>

@implementation VOTSigner
+ (NSString *)signatureForData:(NSData *)data {
    NSData *key = [VOTHMACKey dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}
+ (NSString *)randomToken {
    static NSString *digits = @"0123456789ABCDEF";
    NSMutableString *result = [NSMutableString stringWithCapacity:32];
    for (NSUInteger i = 0; i < 32; i++) {
        uint32_t index = arc4random_uniform((uint32_t)digits.length);
        [result appendString:[digits substringWithRange:NSMakeRange(index, 1)]];
    }
    return result;
}
@end
