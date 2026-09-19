#import <Foundation/Foundation.h>
@class VOTTranslation;

NS_ASSUME_NONNULL_BEGIN
typedef void (^VOTProgressBlock)(VOTTranslation *translation);
typedef void (^VOTCompletionBlock)(VOTTranslation * _Nullable translation, NSError * _Nullable error);

@interface VOTClient : NSObject
@property(nonatomic, copy, nullable) NSString *oauthToken;
- (void)translateVideoURL:(NSString *)url
                 videoID:(NSString *)videoID
                duration:(NSTimeInterval)duration
          sourceLanguage:(NSString *)sourceLanguage
          targetLanguage:(NSString *)targetLanguage
                progress:(nullable VOTProgressBlock)progress
              completion:(VOTCompletionBlock)completion;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
