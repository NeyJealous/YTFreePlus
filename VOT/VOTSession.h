#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface VOTSession : NSObject
@property(nonatomic, copy) NSString *uuid;
@property(nonatomic, copy) NSString *secretKey;
@property(nonatomic, assign) NSInteger expires;
@property(nonatomic, strong) NSDate *createdAt;
@property(nonatomic, assign) BOOL parseValid;
- (BOOL)isValid;
@end
NS_ASSUME_NONNULL_END
