#import <UIKit/UIKit.h>

@interface YTSingleVideoTime : NSObject
@property(nonatomic, assign, readonly) CGFloat time;
@end

@interface YTSingleVideoController : NSObject
@property(nonatomic, assign, readonly) float playbackRate;
@property(nonatomic, assign, readonly) CGFloat totalMediaTime;
@end

@interface YTPlayerViewController : UIViewController
@property(nonatomic, assign, readonly) YTSingleVideoController *activeVideo;
@property(nonatomic, readonly) NSString *contentVideoID;
- (void)play;
- (void)pause;
@end

@interface YTMainAppControlsOverlayView : UIView
@property(nonatomic, strong, readwrite) YTPlayerViewController *playerViewController;
@end
