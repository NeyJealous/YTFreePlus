#import <Foundation/Foundation.h>
@class YTPlayerViewController;

typedef NS_ENUM(NSInteger, VOTManagerState) {
    VOTManagerStateOff,
    VOTManagerStatePending,
    VOTManagerStateActive,
    VOTManagerStateError,
};

NS_ASSUME_NONNULL_BEGIN
@interface VOTManager : NSObject
@property(nonatomic, readonly) VOTManagerState state;
@property(nonatomic, weak, nullable) YTPlayerViewController *playerController;
+ (instancetype)shared;
- (void)toggleForVideoID:(NSString *)videoID duration:(NSTimeInterval)duration;
- (void)playerDidPlay;
- (void)playerDidPause;
- (void)updateTime:(NSTimeInterval)time rate:(float)rate;
- (void)stop;
@end
NS_ASSUME_NONNULL_END
