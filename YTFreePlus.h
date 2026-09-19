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
@property(nonatomic, strong) UIButton *ytfpVOTButton;
@property(nonatomic, assign) BOOL ytfpVOTObserving;
- (void)ytfpToggleVOT;
- (void)ytfpVOTStateChanged:(NSNotification *)notification;
- (void)ytfpRefreshVOTButton:(NSNotification *)notification;
@end
