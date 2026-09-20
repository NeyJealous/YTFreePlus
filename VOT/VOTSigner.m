#import "VOTSigner.h"
#import "VOTConfig.h"
#import <dlfcn.h>

typedef void (*VOTCCHmacFunction)(int algorithm,
                                  const void *key,
                                  size_t keyLength,
                                  const void *data,
                                  size_t dataLength,
                                  void *macOut);

static VOTCCHmacFunction VOTResolveCCHmac(void) {
    static VOTCCHmacFunction function = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        function = (VOTCCHmacFunction)dlsym(RTLD_DEFAULT, "CCHmac");
        if (function) return;

        const char *paths[] = {
            "/usr/lib/system/libcommonCrypto.dylib",
            "/usr/lib/libcommonCrypto.dylib",
            NULL
        };

        for (NSUInteger i = 0; paths[i] != NULL && !function; i++) {
            void *handle = dlopen(paths[i], RTLD_LAZY | RTLD_LOCAL);
            if (handle) function = (VOTCCHmacFunction)dlsym(handle, "CCHmac");
        }
    });
    return function;
}

@implementation VOTSigner

+ (NSString *)signatureForData:(NSData *)data {
    VOTCCHmacFunction cchmac = VOTResolveCCHmac();
    if (!cchmac) return @"";

    NSData *key = [VOTHMACKey dataUsingEncoding:NSUTF8StringEncoding];
    if (key.length == 0) return @"";

    enum { VOTCCHmacAlgSHA256 = 2, VOTSHA256DigestLength = 32 };
    unsigned char digest[VOTSHA256DigestLength] = {0};

    cchmac(VOTCCHmacAlgSHA256,
           key.bytes,
           key.length,
           data.bytes,
           data.length,
           digest);

    NSMutableString *hex = [NSMutableString stringWithCapacity:VOTSHA256DigestLength * 2];
    for (NSUInteger i = 0; i < VOTSHA256DigestLength; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
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
