#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger, VOTTranslationStatus) {
    VOTTranslationStatusFailed = 0,
    VOTTranslationStatusFinished = 1,
    VOTTranslationStatusWaiting = 2,
    VOTTranslationStatusLongWaiting = 3,
    VOTTranslationStatusPartContent = 5,
    VOTTranslationStatusAudioRequested = 6,
    VOTTranslationStatusSessionRequired = 7,
};
NS_ASSUME_NONNULL_BEGIN
@interface VOTTranslation : NSObject
@property(nonatomic, copy, nullable) NSString *audioURL;
@property(nonatomic, assign) VOTTranslationStatus status;
@property(nonatomic, assign) NSInteger remainingTime;
@property(nonatomic, copy, nullable) NSString *translationID;
@property(nonatomic, copy, nullable) NSString *message;
@property(nonatomic, assign) BOOL parseValid;
@property(nonatomic, assign) BOOL statusPresent;
@property(nonatomic, assign) BOOL livelyVoice;
@property(nonatomic, assign) BOOL allowed;
@property(nonatomic, assign) NSInteger shouldRetry;
- (BOOL)isReady;
- (BOOL)isComplete;
- (BOOL)isWaiting;
@end
NS_ASSUME_NONNULL_END
