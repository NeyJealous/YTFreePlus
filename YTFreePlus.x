#import "YTFreePlus.h"
#import "VOT/VOTManager.h"
#import "VOT/VOTConfig.h"
#import "VOT/VOTPreferences.h"
#import <dlfcn.h>

static NSString * const YTFPVOTOverlayKey = @"YTFreePlusVOT";
static NSString * const YTFPVOTShowButtonDefaultsKey = @"YTFreePlus.VOT.OverlayEnabled";
static BOOL YTFPUsingYTVideoOverlay = NO;
static __weak YTPlayerViewController *YTFPActivePlayerController = nil;

@interface YTSettingsSectionItemManager : NSObject
+ (void)registerTweak:(NSString *)tweakId metadata:(NSDictionary *)metadata;
@end

@interface YTInlinePlayerBarContainerView : UIView
- (void)ytfpToggleVOTFromOverlay:(id)sender;
- (void)ytfpVOTStateChanged:(NSNotification *)notification;
- (void)ytfpRefreshVOTButton:(NSNotification *)notification;
- (void)ytfpVOTPreferencesChanged:(NSNotification *)notification;
@end

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

static UIWindow *YTFPKeyWindow(void) {
    for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
        if (candidate.isKeyWindow) return candidate;
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static UIViewController *YTFPTopViewController(void) {
    UIViewController *controller = YTFPKeyWindow().rootViewController;
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

static YTPlayerViewController *YTFPFindPlayerInResponderChain(UIResponder *responder) {
    Class playerClass = NSClassFromString(@"YTPlayerViewController");
    if (!playerClass) return nil;

    UIResponder *current = responder;
    NSUInteger depth = 0;
    while (current && depth++ < 100) {
        if ([current isKindOfClass:playerClass]) {
            return (YTPlayerViewController *)current;
        }
        current = current.nextResponder;
    }
    return nil;
}

static YTPlayerViewController *YTFPFindPlayerInController(UIViewController *controller) {
    if (!controller) return nil;

    Class playerClass = NSClassFromString(@"YTPlayerViewController");
    if (playerClass && [controller isKindOfClass:playerClass]) {
        return (YTPlayerViewController *)controller;
    }

    if (controller.presentedViewController) {
        YTPlayerViewController *found = YTFPFindPlayerInController(controller.presentedViewController);
        if (found) return found;
    }

    if ([controller isKindOfClass:UINavigationController.class]) {
        YTPlayerViewController *found =
            YTFPFindPlayerInController(((UINavigationController *)controller).visibleViewController);
        if (found) return found;
    }

    if ([controller isKindOfClass:UITabBarController.class]) {
        YTPlayerViewController *found =
            YTFPFindPlayerInController(((UITabBarController *)controller).selectedViewController);
        if (found) return found;
    }

    for (UIViewController *child in [controller.childViewControllers reverseObjectEnumerator]) {
        YTPlayerViewController *found = YTFPFindPlayerInController(child);
        if (found) return found;
    }

    return nil;
}

static YTPlayerViewController *YTFPResolvePlayerController(UIResponder *origin) {
    YTPlayerViewController *player = YTFPFindPlayerInResponderChain(origin);
    if (player) return player;

    player = YTFPFindPlayerInController(YTFPKeyWindow().rootViewController);
    if (player) return player;

    return YTFPActivePlayerController;
}

static void YTFPShowVOTError(NSString *message) {
    if (message.length == 0 || !VOTPreferencesDiagnosticsEnabled()) return;

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

static UIButton *YTFPOverlayButtonForHost(id host) {
    if (!host || ![host respondsToSelector:NSSelectorFromString(@"overlayButtons")]) return nil;

    @try {
        NSDictionary *buttons = [host valueForKey:@"overlayButtons"];
        id button = buttons[YTFPVOTOverlayKey];
        return [button isKindOfClass:UIButton.class] ? button : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void YTFPRefreshOverlayButton(id host, NSNotification *notification) {
    UIButton *button = YTFPOverlayButtonForHost(host);
    if (!button) return;

    NSInteger remaining = [notification.userInfo[@"remainingTime"] integerValue];
    NSString *title = VOTButtonTitleForState([VOTManager shared].state, remaining);
    [button setTitle:title forState:UIControlStateNormal];

    BOOL visible = VOTPreferencesEnabled() && VOTPreferencesShowButton();
    button.hidden = !visible;
    if (visible && button.alpha <= 0.0 && [host window]) {
        button.alpha = 1.0;
    }

    if ([host respondsToSelector:@selector(setNeedsLayout)]) {
        [host setNeedsLayout];
    }
}

static void YTFPToggleVOTFromOrigin(UIResponder *origin, UIButton *button) {
    if (!VOTPreferencesEnabled()) {
        return;
    }

    id player = YTFPResolvePlayerController(origin);

    if (!player ||
        ![player respondsToSelector:@selector(contentVideoID)] ||
        ![player respondsToSelector:@selector(currentVideoTotalMediaTime)]) {
        [button setTitle:@"VOT !" forState:UIControlStateNormal];
        NSString *detail = player
            ? [NSString stringWithFormat:@"Found %@, but required player methods are unavailable.",
                                         NSStringFromClass([player class])]
            : @"YTPlayerViewController was not found in the active view hierarchy.";
        YTFPShowVOTError(detail);
        return;
    }

    NSString *videoID = nil;
    NSTimeInterval duration = 0;

    @try {
        videoID = [player contentVideoID];
        duration = [player currentVideoTotalMediaTime];
    } @catch (NSException *exception) {
        [button setTitle:@"VOT !" forState:UIControlStateNormal];
        YTFPShowVOTError([NSString stringWithFormat:@"Player exception: %@",
                                                    exception.reason ?: @"unknown"]);
        return;
    }

    if (videoID.length == 0 || !isfinite(duration) || duration <= 0) {
        [button setTitle:@"VOT !" forState:UIControlStateNormal];
        YTFPShowVOTError([NSString stringWithFormat:@"Invalid video metadata (id=%@, duration=%.2f).",
                                                    videoID ?: @"nil", duration]);
        return;
    }

    [VOTManager shared].playerController = player;
    [[VOTManager shared] toggleForVideoID:videoID duration:duration];
}

static BOOL YTFPRegisterWithYTVideoOverlay(void) {
    NSString *frameworkPath = [[NSBundle mainBundle].bundlePath
        stringByAppendingPathComponent:@"Frameworks/YTVideoOverlay.dylib"];
    dlopen(frameworkPath.UTF8String, RTLD_LAZY | RTLD_LOCAL);

    Class managerClass = NSClassFromString(@"YTSettingsSectionItemManager");
    SEL registerSelector = NSSelectorFromString(@"registerTweak:metadata:");
    if (!managerClass || ![managerClass respondsToSelector:registerSelector]) {
        return NO;
    }

    NSDictionary *metadata = @{
        @"accessibilityLabel": @"Yandex voice-over translation",
        @"toggle": YTFPVOTShowButtonDefaultsKey,
        @"asText": @YES,
        @"selector": @"ytfpToggleVOTFromOverlay:"
    };

    [managerClass registerTweak:YTFPVOTOverlayKey metadata:metadata];
    return YES;
}

%hook YTPlayerViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    YTFPActivePlayerController = self;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    YTFPActivePlayerController = self;
}

%end

%hook YTMainAppControlsOverlayView

%property(nonatomic, strong) UIButton *ytfpVOTButton;
%property(nonatomic, assign) BOOL ytfpVOTObserving;

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;

    if (!YTFPUsingYTVideoOverlay && !self.ytfpVOTButton) {
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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ytfpVOTPreferencesChanged:)
                                                     name:VOTPreferencesDidChangeNotification
                                                   object:nil];
        self.ytfpVOTObserving = YES;
    }

    [self ytfpRefreshVOTButton:nil];
}

%new
- (void)ytfpToggleVOT {
    YTFPToggleVOTFromOrigin(self, self.ytfpVOTButton);
}

%new
- (void)ytfpToggleVOTFromOverlay:(id)sender {
    UIButton *button = [sender isKindOfClass:UIButton.class] ? sender : YTFPOverlayButtonForHost(self);
    YTFPToggleVOTFromOrigin(self, button);
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
    if (YTFPUsingYTVideoOverlay) {
        YTFPRefreshOverlayButton(self, notification);
        return;
    }

    self.ytfpVOTButton.hidden = !(VOTPreferencesEnabled() && VOTPreferencesShowButton());
    NSInteger remaining = [notification.userInfo[@"remainingTime"] integerValue];
    NSString *title = VOTButtonTitleForState([VOTManager shared].state, remaining);
    [self.ytfpVOTButton setTitle:title forState:UIControlStateNormal];
}

%new
- (void)ytfpVOTPreferencesChanged:(NSNotification *)notification {
    [[VOTManager shared] applyPreferences];
    [self ytfpRefreshVOTButton:nil];
}

- (void)dealloc {
    if (self.ytfpVOTObserving) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:VOTStateChangedNotification
                                                      object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:VOTPreferencesDidChangeNotification
                                                      object:nil];
    }
    %orig;
}

%end

%hook YTInlinePlayerBarContainerView

- (void)didMoveToWindow {
    %orig;
    if (!YTFPUsingYTVideoOverlay) return;

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:VOTStateChangedNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:VOTPreferencesDidChangeNotification
                                                  object:nil];

    if (self.window) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ytfpVOTStateChanged:)
                                                     name:VOTStateChangedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ytfpVOTPreferencesChanged:)
                                                     name:VOTPreferencesDidChangeNotification
                                                   object:nil];
        [self ytfpRefreshVOTButton:nil];
    }
}

%new
- (void)ytfpToggleVOTFromOverlay:(id)sender {
    UIButton *button = [sender isKindOfClass:UIButton.class] ? sender : YTFPOverlayButtonForHost(self);
    YTFPToggleVOTFromOrigin(self, button);
}

%new
- (void)ytfpVOTStateChanged:(NSNotification *)notification {
    [self ytfpRefreshVOTButton:notification];
}

%new
- (void)ytfpRefreshVOTButton:(NSNotification *)notification {
    YTFPRefreshOverlayButton(self, notification);
}

%new
- (void)ytfpVOTPreferencesChanged:(NSNotification *)notification {
    [[VOTManager shared] applyPreferences];
    [self ytfpRefreshVOTButton:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:VOTStateChangedNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:VOTPreferencesDidChangeNotification
                                                  object:nil];
    %orig;
}

%end

%ctor {
    (void)VOTPreferencesEnabled();
    (void)VOTPreferencesShowButton();
    YTFPUsingYTVideoOverlay = YTFPRegisterWithYTVideoOverlay();
}
