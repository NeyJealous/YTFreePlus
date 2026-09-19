#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface VOTAudioPlayer : NSObject
@property(nonatomic, assign) float volume;
@property(nonatomic, readonly) BOOL ready;
- (void)loadURL:(NSURL *)url completion:(void (^)(NSError * _Nullable error))completion;
- (void)play;
- (void)pause;
- (void)stop;
- (void)syncToTime:(NSTimeInterval)time rate:(float)rate;
@end
NS_ASSUME_NONNULL_END
