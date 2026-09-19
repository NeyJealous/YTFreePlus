#import "VOTManager.h"
#import "VOTClient.h"
#import "VOTAudioPlayer.h"
#import "VOTConfig.h"
#import "VOTTranslation.h"

@interface VOTManager ()
@property(nonatomic, strong) VOTClient *client;
@property(nonatomic, strong) VOTAudioPlayer *audioPlayer;
@property(nonatomic, assign, readwrite) VOTManagerState state;
@property(nonatomic, copy, nullable) NSString *videoID;
@property(nonatomic, assign) NSTimeInterval latestTime;
@property(nonatomic, assign) float latestRate;
@property(nonatomic, assign) BOOL youtubePlaying;
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
        _audioPlayer.volume = 1.0f;
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

- (void)toggleForVideoID:(NSString *)videoID duration:(NSTimeInterval)duration {
    if (self.state != VOTManagerStateOff && [self.videoID isEqualToString:videoID]) {
        [self stop];
        return;
    }

    [self stop];
    self.videoID = videoID;
    [self setStateAndNotify:VOTManagerStatePending extra:nil];

    NSString *url = [NSString stringWithFormat:@"https://youtu.be/%@", videoID];
    __weak typeof(self) weakSelf = self;

    [self.client translateVideoURL:url
                          videoID:videoID
                         duration:duration
                   sourceLanguage:VOTDefaultSourceLanguage
                   targetLanguage:VOTDefaultTargetLanguage
                         progress:^(VOTTranslation *translation) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self.videoID isEqualToString:videoID]) return;
        [self setStateAndNotify:VOTManagerStatePending
                          extra:@{@"remainingTime": @(translation.remainingTime)}];
    }
                       completion:^(VOTTranslation *translation, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self.videoID isEqualToString:videoID]) return;

        if (error || translation.audioURL.length == 0) {
            [self setStateAndNotify:VOTManagerStateError
                              extra:@{@"message": error.localizedDescription ?: @"VOT error"}];
            return;
        }

        NSURL *audioURL = [NSURL URLWithString:translation.audioURL];
        if (!audioURL) {
            [self setStateAndNotify:VOTManagerStateError extra:@{@"message": @"Invalid translated audio URL"}];
            return;
        }

        [self.audioPlayer loadURL:audioURL completion:^(NSError *audioError) {
            if (audioError) {
                [self setStateAndNotify:VOTManagerStateError
                                  extra:@{@"message": audioError.localizedDescription ?: @"Audio error"}];
                return;
            }

            [self.audioPlayer syncToTime:self.latestTime rate:self.latestRate];
            if (self.youtubePlaying) [self.audioPlayer play];
            [self setStateAndNotify:VOTManagerStateActive extra:nil];
        }];
    }];
}

- (void)playerDidPlay {
    self.youtubePlaying = YES;
    if (self.state == VOTManagerStateActive) [self.audioPlayer play];
}

- (void)playerDidPause {
    self.youtubePlaying = NO;
    [self.audioPlayer pause];
}

- (void)updateTime:(NSTimeInterval)time rate:(float)rate {
    self.latestTime = time;
    self.latestRate = rate > 0.01f ? rate : 1.0f;
    if (self.state == VOTManagerStateActive) {
        [self.audioPlayer syncToTime:time rate:self.latestRate];
    }
}

- (void)stop {
    [self.client cancel];
    [self.audioPlayer stop];
    self.videoID = nil;
    [self setStateAndNotify:VOTManagerStateOff extra:nil];
}

@end
