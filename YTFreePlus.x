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

static UIViewController *YTFPTopViewController(void) {
    UIWindow *window = nil;
    for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
        if (candidate.isKeyWindow) {
            window = candidate;
            break;
        }
    }
    if (!window) window = UIApplication.sharedApplication.windows.firstObject;

    UIViewController *controller = window.rootViewController;
    while (controller) {
        if (controller.presentedViewController) {
            controller = controller.presentedViewController;
            continue;
        }
        if ([controller isKindOfClass:UINavigationController.class]) {
            controller = ((UINavigationController *)controller).visibleViewController;
            continue;
        }
        if ([controller isKindOfClass:UITabBarController.class]) {
            controller = ((UITabBarController *)controller).selectedViewController;
            continue;
        }
        break;
    }
    return controller;
}

static void YTFPShowVOTError(NSString *message) {
    if (message.length == 0) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *controller = YTFPTopViewController();
        if (!controller) return;
        if ([controller.presentedViewController isKindOfClass:UIAlertController.class]) return;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Yandex VOT"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [controller presentViewController:alert animated:YES completion:nil];
    });
}

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
    id player = nil;

    @try {
        if ([self respondsToSelector:@selector(playerViewController)]) {
            player = self.playerViewController;
        }
    } @catch (__unused NSException *exception) {
        player = nil;
    }

    if (!player ||
        ![player respondsToSelector:@selector(contentVideoID)] ||
        ![player respondsToSelector:@selector(currentVideoTotalMediaTime)]) {
        [self.ytfpVOTButton setTitle:@"VOT !" forState:UIControlStateNormal];
        YTFPShowVOTError(@"YouTube player API is unavailable.");
        return;
    }

    NSString *videoID = nil;
    NSTimeInterval duration = 0;

    @try {
        videoID = [player contentVideoID];
        duration = [player currentVideoTotalMediaTime];
    } @catch (NSException *exception) {
        [self.ytfpVOTButton setTitle:@"VOT !" forState:UIControlStateNormal];
        YTFPShowVOTError([NSString stringWithFormat:@"Player exception: %@", exception.reason ?: @"unknown"]);
        return;
    }

    if (videoID.length == 0 || !isfinite(duration) || duration <= 0) {
        [self.ytfpVOTButton setTitle:@"VOT !" forState:UIControlStateNormal];
        YTFPShowVOTError([NSString stringWithFormat:@"Invalid video metadata (id=%@, duration=%.2f).",
                          videoID ?: @"nil", duration]);
        return;
    }

    [VOTManager shared].playerController = player;
    [[VOTManager shared] toggleForVideoID:videoID duration:duration];
}

%new
- (void)ytfpVOTStateChanged:(NSNotification *)notification {
    [self ytfpRefreshVOTButton:notification];

    if ([VOTManager shared].state == VOTManagerStateError && self.window) {
        NSString *message = notification.userInfo[@"message"];
        if (message.length > 0) {
            NSLog(@"[YTFreePlus][VOT] %@", message);
            YTFPShowVOTError(message);
        }
    }
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
