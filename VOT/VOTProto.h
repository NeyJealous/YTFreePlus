#import <Foundation/Foundation.h>
@class VOTSession;
@class VOTTranslation;

NS_ASSUME_NONNULL_BEGIN
@interface VOTProto : NSObject
+ (NSData *)sessionRequestWithUUID:(NSString *)uuid module:(NSString *)module;
+ (nullable VOTSession *)decodeSession:(NSData *)data;
+ (NSData *)translationRequestWithURL:(NSString *)url
                            duration:(NSTimeInterval)duration
                      sourceLanguage:(NSString *)sourceLanguage
                      targetLanguage:(NSString *)targetLanguage
                        firstRequest:(BOOL)firstRequest
                         livelyVoice:(BOOL)livelyVoice;
+ (nullable VOTTranslation *)decodeTranslation:(NSData *)data;
+ (NSData *)emptyAudioRequestWithURL:(NSString *)url
                       translationID:(NSString *)translationID
                              fileID:(NSString *)fileID;
+ (NSData *)partialAudioRequestWithURL:(NSString *)url
                          translationID:(NSString *)translationID
                                 fileID:(NSString *)fileID
                                chunkID:(NSInteger)chunkID
                           partsLength:(NSInteger)partsLength
                                  data:(NSData *)audioData;
@end
NS_ASSUME_NONNULL_END
