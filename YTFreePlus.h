#import <UIKit/UIKit.h>

@interface YTPlayerViewController : UIViewController
- (NSString *)contentVideoID;
- (CGFloat)currentVideoMediaTime;
- (CGFloat)currentVideoTotalMediaTime;
- (id)activeVideoPlayerOverlay;
@end

@interface YTMainAppVideoPlayerOverlayViewController : UIViewController
- (CGFloat)currentPlaybackRate;
@end

@interface YTMainAppControlsOverlayView : UIView
@property(nonatomic, strong, readwrite) YTPlayerViewController *playerViewController;
@end
