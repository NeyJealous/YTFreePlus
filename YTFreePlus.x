#import "YTFreePlus.h"
#import "VOT/VOTManager.h"
#import "VOT/VOTConfig.h"

static NSString *VOTButtonTitleForState(VOTManagerState state, NSInteger remaining) {
    switch (state) {
        case VOTManagerStatePending:
            return remaining > 0 ? [NSString stringWithFormat:@"VOT %ld", (long)remaining] : @"VOT …";
        case VOTManagerStateActive:
            return @"VOT ✓";
        case VOTManagerStateError:
            return @"VOT !";
        case VOTManagerStateOff:
        default:
            return @"VOT";
    }
}

%hook YTPlayerViewController

- (void)loadWithPlayerTransition:(id)transition playbackConfig:(id)config {
    %orig;
    [VOTManager shared].playerController = self;
}

- (void)play {
    %orig;
    [[VOTManager shared] playerDidPlay];
}

- (void)pause {
    %orig;
    [[VOTManager shared] playerDidPause];
}

- (void)singleVideo:(YTSingleVideoController *)video currentVideoTimeDidChange:(YTSingleVideoTime *)time {
    %orig;
    [[VOTManager shared] updateTime:time.time rate:video.playbackRate];
}

- (void)potentiallyMutatedSingleVideo:(YTSingleVideoController *)video currentVideoTimeDidChange:(YTSingleVideoTime *)time {
    %orig;
    [[VOTManager shared] updateTime:time.time rate:video.playbackRate];
}

%end

%hook YTMainAppControlsOverlayView

%property(nonatomic, strong) UIButton *ytfpVOTButton;
%property(nonatomic, assign) BOOL ytfpVOTObserving;

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;

    if (!self.ytfpVOTButton) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        button.accessibilityLabel = @"Yandex voice-over translation";
        button.layer.cornerRadius = 8.0;
        button.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [button addTarget:self action:@selector(ytfpToggleVOT) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:button];

        [NSLayoutConstraint activateConstraints:@[
            [button.trailingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor constant:-12],
            [button.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:12],
            [button.widthAnchor constraintGreaterThanOrEqualToConstant:58],
            [button.heightAnchor constraintEqualToConstant:34]
        ]];

        self.ytfpVOTButton = button;
    }

    if (!self.ytfpVOTObserving) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ytfpVOTStateChanged:)
                                                     name:VOTStateChangedNotification
                                                   object:nil];
        self.ytfpVOTObserving = YES;
    }

    [self ytfpRefreshVOTButton:nil];
}

%new
- (void)ytfpToggleVOT {
    YTPlayerViewController *player = self.playerViewController;
    NSString *videoID = player.contentVideoID;
    NSTimeInterval duration = player.activeVideo.totalMediaTime;
    if (videoID.length == 0 || duration <= 0) return;
    [[VOTManager shared] toggleForVideoID:videoID duration:duration];
}

%new
- (void)ytfpVOTStateChanged:(NSNotification *)notification {
    [self ytfpRefreshVOTButton:notification];
}

%new
- (void)ytfpRefreshVOTButton:(NSNotification *)notification {
    NSInteger remaining = [notification.userInfo[@"remainingTime"] integerValue];
    NSString *title = VOTButtonTitleForState([VOTManager shared].state, remaining);
    [self.ytfpVOTButton setTitle:title forState:UIControlStateNormal];
}

- (void)dealloc {
    if (self.ytfpVOTObserving) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:VOTStateChangedNotification
                                                      object:nil];
    }
    %orig;
}

%end
