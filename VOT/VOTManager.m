#import "VOTManager.h"
#import "VOTClient.h"
#import "VOTAudioPlayer.h"
#import "VOTConfig.h"
#import "VOTTranslation.h"
#import "VOTPreferences.h"
#import "../YTFreePlus.h"

@interface VOTManager ()
@property(nonatomic, strong) VOTClient *client;
@property(nonatomic, strong) VOTAudioPlayer *audioPlayer;
@property(nonatomic, assign, readwrite) VOTManagerState state;
@property(nonatomic, copy, nullable) NSString *videoID;
@property(nonatomic, strong, nullable) NSTimer *syncTimer;
@property(nonatomic, assign) NSTimeInterval latestTime;
@property(nonatomic, assign) NSTimeInterval lastObservedTime;
@property(nonatomic, assign) float latestRate;
@property(nonatomic, assign) BOOL youtubePlaying;
@property(nonatomic, assign) NSUInteger stillTicks;
@end

@implementation VOTManager

+ (instancetype)shared {
    static VOTManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [VOTManager new];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _client = [VOTClient new];
        _audioPlayer = [VOTAudioPlayer new];
        _audioPlayer.volume = VOTPreferencesTranslationVolume();
        _state = VOTManagerStateOff;
        _latestRate = 1.0f;
    }
    return self;
}

- (void)setStateAndNotify:(VOTManagerState)state extra:(NSDictionary *)extra {
    _state = state;
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:extra ?: @{}];
    info[@"state"] = @(state);
    [[NSNotificationCenter defaultCenter] postNotificationName:VOTStateChangedNotification object:self userInfo:info];
}

- (void)startSyncTimer {
    [self.syncTimer invalidate];
    self.lastObservedTime = -1;
    self.stillTicks = 0;

    __weak typeof(self) weakSelf = self;
    self.syncTimer = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:YES block:^(NSTimer *timer) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        id player = self.playerController;
        if (!player || ![player respondsToSelector:@selector(currentVideoMediaTime)]) return;

        NSTimeInterval current = 0;
        float rate = 1.0f;
        id overlay = nil;

        @try {
            current = [player currentVideoMediaTime];
            if ([player respondsToSelector:@selector(activeVideoPlayerOverlay)]) {
                overlay = [player activeVideoPlayerOverlay];
            }
            if ([overlay respondsToSelector:@selector(currentPlaybackRate)]) {
                rate = [(YTMainAppVideoPlayerOverlayViewController *)overlay currentPlaybackRate];
                if (rate <= 0.01f) rate = 1.0f;
            }
        } @catch (__unused NSException *exception) {
            [self stop];
            return;
        }

        if (!isfinite(current) || current < 0) return;

        if (self.lastObservedTime >= 0 && fabs(current - self.lastObservedTime) > 0.03) {
            self.youtubePlaying = YES;
            self.stillTicks = 0;
        } else {
            self.stillTicks += 1;
            if (self.stillTicks >= 2) self.youtubePlaying = NO;
        }

        self.latestTime = current;
        self.latestRate = rate;
        self.lastObservedTime = current;

        if (self.state == VOTManagerStateActive) {
            [self.audioPlayer syncToTime:current rate:rate];
            if (self.youtubePlaying) [self.audioPlayer play];
            else [self.audioPlayer pause];
        }
    }];
}

- (void)toggleForVideoID:(NSString *)videoID duration:(NSTimeInterval)duration {
    if (self.state != VOTManagerStateOff && [self.videoID isEqualToString:videoID]) {
        [self stop];
        return;
    }

    [self stop];
    self.videoID = videoID;
    [self startSyncTimer];
    [self setStateAndNotify:VOTManagerStatePending extra:nil];

    NSString *url = [NSString stringWithFormat:@"https://youtu.be/%@", videoID];
    __weak typeof(self) weakSelf = self;

    [self.client translateVideoURL:url
                          videoID:videoID
                         duration:duration
                   sourceLanguage:VOTPreferencesSourceLanguage()
                   targetLanguage:VOTPreferencesTargetLanguage()
                         progress:^(VOTTranslation *translation) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self.videoID isEqualToString:videoID]) return;
        [self setStateAndNotify:VOTManagerStatePending extra:@{@"remainingTime": @(translation.remainingTime)}];
    }
                       completion:^(VOTTranslation *translation, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self.videoID isEqualToString:videoID]) return;

        if (error || translation.audioURL.length == 0) {
            [self setStateAndNotify:VOTManagerStateError extra:@{@"message": error.localizedDescription ?: @"VOT error"}];
            return;
        }

        NSURL *audioURL = [NSURL URLWithString:translation.audioURL];
        if (!audioURL) {
            [self setStateAndNotify:VOTManagerStateError extra:@{@"message": @"Invalid translated audio URL"}];
            return;
        }

        [self.audioPlayer loadURL:audioURL completion:^(NSError *audioError) {
            if (audioError) {
                [self setStateAndNotify:VOTManagerStateError extra:@{@"message": audioError.localizedDescription ?: @"Audio error"}];
                return;
            }

            [self.audioPlayer syncToTime:self.latestTime rate:self.latestRate];
            if (self.youtubePlaying) [self.audioPlayer play];
            [self setStateAndNotify:VOTManagerStateActive extra:nil];
        }];
    }];
}

- (void)applyPreferences {
    self.audioPlayer.volume = VOTPreferencesTranslationVolume();
    if (!VOTPreferencesEnabled() && self.state != VOTManagerStateOff) {
        [self stop];
    }
}

- (void)stop {
    [self.syncTimer invalidate];
    self.syncTimer = nil;
    [self.client cancel];
    [self.audioPlayer stop];
    self.videoID = nil;
    self.youtubePlaying = NO;
    [self setStateAndNotify:VOTManagerStateOff extra:nil];
}

@end
