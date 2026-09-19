#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface VOTSigner : NSObject
+ (NSString *)signatureForData:(NSData *)data;
+ (NSString *)randomToken;
@end
NS_ASSUME_NONNULL_END
