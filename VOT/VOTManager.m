#import "VOTManager.h"
#import "VOTClient.h"
#import "VOTAudioPlayer.h"
#import "VOTConfig.h"
#import "VOTTranslation.h"
#import "VOTPreferences.h"
#import "../YTFreePlus.h"

@interface YTFPAudioTrack : NSObject
@property(nonatomic, copy, readonly) NSString *id_p;
@property(nonatomic, assign, readonly) BOOL audioIsDefault;
@end

@interface YTFPMLFormat : NSObject
@property(nonatomic, readonly, strong) YTFPAudioTrack *audioTrack;
- (NSURL *)URL;
- (BOOL)isAudio;
- (NSInteger)bitrate;
@end

@interface YTFPStreamingData : NSObject
- (NSArray<YTFPMLFormat *> *)adaptiveStreams;
@end

@interface YTFPVideo : NSObject
- (YTFPStreamingData *)streamingData;
@end

@interface YTFPPlaybackData : NSObject
- (YTFPVideo *)video;
@end

@interface YTFPSingleVideo : NSObject
- (YTFPPlaybackData *)playbackData;
@end

@interface YTFPSingleVideoController : NSObject
- (YTFPSingleVideo *)singleVideo;
@end

static NSString *YTFPNormalizedLanguage(NSString *value) {
    if (value.length == 0) return nil;
    NSString *base = [[value componentsSeparatedByString:@"."] firstObject];
    base = [[base componentsSeparatedByString:@"-"] firstObject];
    return base.lowercaseString;
}

static NSURL *YTFPAudioStreamURLForPlayer(id player, NSString *sourceLanguage) {
    if (!player || ![player respondsToSelector:@selector(activeVideo)]) return nil;

    @try {
        YTFPSingleVideoController *activeVideo = [player activeVideo];
        YTFPSingleVideo *singleVideo = [activeVideo singleVideo];
        YTFPPlaybackData *playbackData = [singleVideo playbackData];
        YTFPVideo *video = [playbackData video];
        YTFPStreamingData *streamingData = [video streamingData];
        NSArray<YTFPMLFormat *> *streams = [streamingData adaptiveStreams];
        if (streams.count == 0) return nil;

        NSString *requested = YTFPNormalizedLanguage(sourceLanguage);
        BOOL wantsSpecificLanguage = requested.length > 0 && ![requested isEqualToString:@"auto"];

        YTFPMLFormat *best = nil;
        NSInteger bestTier = NSIntegerMax;
        NSInteger bestBitrate = NSIntegerMax;

        for (YTFPMLFormat *format in streams) {
            if (![format respondsToSelector:@selector(isAudio)] || ![format isAudio]) continue;
            NSURL *URL = [format respondsToSelector:@selector(URL)] ? [format URL] : nil;
            if (!URL) continue;

            YTFPAudioTrack *track = nil;
            if ([format respondsToSelector:@selector(audioTrack)]) {
                track = format.audioTrack;
            }

            NSString *trackLanguage = YTFPNormalizedLanguage(track.id_p);
            BOOL languageMatch = wantsSpecificLanguage && [trackLanguage isEqualToString:requested];
            BOOL isDefault = track.audioIsDefault;

            NSInteger tier = 2;
            if (languageMatch) tier = 0;
            else if (!wantsSpecificLanguage && isDefault) tier = 0;
            else if (isDefault) tier = 1;

            NSInteger bitrate = [format respondsToSelector:@selector(bitrate)] ? [format bitrate] : 0;
            if (bitrate <= 0) bitrate = NSIntegerMax - 1;

            if (!best || tier < bestTier || (tier == bestTier && bitrate < bestBitrate)) {
                best = format;
                bestTier = tier;
                bestBitrate = bitrate;
            }
        }

        return [best respondsToSelector:@selector(URL)] ? [best URL] : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}


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
@property(nonatomic, assign) NSUInteger videoIdentityMissTicks;
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
    self.videoIdentityMissTicks = 0;

    __weak typeof(self) weakSelf = self;
    self.syncTimer = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:YES block:^(NSTimer *timer) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        id player = self.playerController;
        if (!player || ![player respondsToSelector:@selector(currentVideoMediaTime)]) return;

        NSTimeInterval current = 0;
        float rate = 1.0f;
        id overlay = nil;
        NSString *observedVideoID = nil;

        @try {
            if ([player respondsToSelector:@selector(contentVideoID)]) {
                observedVideoID = [player contentVideoID];
            }
            if (observedVideoID.length == 0 &&
                [player respondsToSelector:@selector(currentVideoID)]) {
                observedVideoID = [player currentVideoID];
            }

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

        if (observedVideoID.length == 0) {
            self.videoIdentityMissTicks += 1;
            if (self.videoIdentityMissTicks >= 2) {
                [self stop];
            }
            return;
        }

        self.videoIdentityMissTicks = 0;
        if (self.videoID.length > 0 && ![observedVideoID isEqualToString:self.videoID]) {
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
    NSString *sourceLanguage = VOTPreferencesSourceLanguage();
    NSURL *audioStreamURL = YTFPAudioStreamURLForPlayer(self.playerController, sourceLanguage);
    __weak typeof(self) weakSelf = self;

    [self.client translateVideoURL:url
                          videoID:videoID
                         duration:duration
                    audioStreamURL:audioStreamURL
                   sourceLanguage:sourceLanguage
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
    self.latestTime = 0;
    self.lastObservedTime = -1;
    self.latestRate = 1.0f;
    self.stillTicks = 0;
    self.videoIdentityMissTicks = 0;
    [self setStateAndNotify:VOTManagerStateOff extra:nil];
}

@end
