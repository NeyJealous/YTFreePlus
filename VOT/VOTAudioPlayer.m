#import "VOTAudioPlayer.h"
#import <AVFoundation/AVFoundation.h>

@interface VOTAudioPlayer ()
@property(nonatomic, strong, nullable) AVPlayer *player;
@property(nonatomic, assign, readwrite) BOOL ready;
@end

@implementation VOTAudioPlayer

- (instancetype)init {
    self = [super init];
    if (self) _volume = 1.0f;
    return self;
}

- (void)setVolume:(float)volume {
    _volume = fmaxf(0.0f, fminf(1.0f, volume));
    self.player.volume = _volume;
}

- (void)loadURL:(NSURL *)url completion:(void (^)(NSError *error))completion {
    [self stop];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    self.player = [AVPlayer playerWithPlayerItem:item];
    self.player.volume = self.volume;
    self.ready = YES;
    if (completion) completion(nil);
}

- (void)play { [self.player play]; }
- (void)pause { [self.player pause]; }

- (void)stop {
    [self.player pause];
    [self.player replaceCurrentItemWithPlayerItem:nil];
    self.player = nil;
    self.ready = NO;
}

- (void)syncToTime:(NSTimeInterval)time rate:(float)rate {
    if (!self.player || !self.ready || !isfinite(time) || time < 0) return;
    NSTimeInterval current = CMTimeGetSeconds(self.player.currentTime);
    if (!isfinite(current) || fabs(current - time) > 0.8) {
        [self.player seekToTime:CMTimeMakeWithSeconds(time, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    }
    if (rate > 0.01f && self.player.rate > 0.0f && fabsf(self.player.rate - rate) > 0.01f) {
        self.player.rate = rate;
    }
}

@end
