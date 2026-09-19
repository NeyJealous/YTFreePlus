#import "VOTClient.h"
#import "VOTConfig.h"
#import "VOTSigner.h"
#import "VOTProto.h"
#import "VOTSession.h"
#import "VOTTranslation.h"

static NSString * const VOTErrorDomain = @"YTFreePlus.VOT";

@interface VOTClient ()
@property(nonatomic, strong) NSURLSession *urlSession;
@property(nonatomic, strong, nullable) VOTSession *session;
@property(nonatomic, assign) NSUInteger operationID;
@end

@implementation VOTClient

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest = 120;
        config.timeoutIntervalForResource = 180;
        _urlSession = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (void)cancel {
    self.operationID++;
}

- (NSMutableURLRequest *)requestForPath:(NSString *)path method:(NSString *)method body:(NSData *)body json:(BOOL)json {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@%@", VOTAPIHost, path]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    request.HTTPBody = body;
    [request setValue:VOTUserAgent forHTTPHeaderField:@"User-Agent"];
    [request setValue:(json ? @"application/json" : @"application/x-protobuf") forHTTPHeaderField:@"Content-Type"];
    [request setValue:(json ? @"application/json" : @"application/x-protobuf") forHTTPHeaderField:@"Accept"];
    [request setValue:@"en" forHTTPHeaderField:@"Accept-Language"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Pragma"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    return request;
}

- (void)applyHeaders:(NSDictionary<NSString *, NSString *> *)headers toRequest:(NSMutableURLRequest *)request {
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:key];
    }];
}

- (NSDictionary<NSString *, NSString *> *)sessionHeadersForBody:(NSData *)body path:(NSString *)path {
    VOTSession *session = self.session;
    if (!session) return @{};
    NSString *token = [NSString stringWithFormat:@"%@:%@:%@", session.uuid, path, VOTComponentVersion];
    NSData *tokenData = [token dataUsingEncoding:NSUTF8StringEncoding];
    NSString *tokenSign = [VOTSigner signatureForData:tokenData];
    return @{
        @"Vtrans-Signature": [VOTSigner signatureForData:body],
        @"Sec-Vtrans-Sk": session.secretKey,
        @"Sec-Vtrans-Token": [NSString stringWithFormat:@"%@:%@", tokenSign, token]
    };
}

- (void)performRequest:(NSMutableURLRequest *)request
            completion:(void (^)(NSData * _Nullable, NSHTTPURLResponse * _Nullable, NSError * _Nullable))completion {
    [[self.urlSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(data, (NSHTTPURLResponse *)response, error);
        });
    }] resume];
}

- (NSError *)httpErrorWithResponse:(NSHTTPURLResponse *)response description:(NSString *)description {
    return [NSError errorWithDomain:VOTErrorDomain
                               code:response.statusCode
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (void)ensureSession:(void (^)(NSError * _Nullable))completion {
    if ([self.session isValid]) {
        completion(nil);
        return;
    }

    NSString *uuid = [VOTSigner randomToken];
    NSData *body = [VOTProto sessionRequestWithUUID:uuid module:@"video-translation"];
    NSMutableURLRequest *request = [self requestForPath:@"/session/create" method:@"POST" body:body json:NO];
    [request setValue:[VOTSigner signatureForData:body] forHTTPHeaderField:@"Vtrans-Signature"];

    [self performRequest:request completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error) {
            completion(error);
            return;
        }
        if (response.statusCode < 200 || response.statusCode >= 300 || data.length == 0) {
            completion([self httpErrorWithResponse:response description:@"VOT session request failed"]);
            return;
        }

        VOTSession *session = [VOTProto decodeSession:data];
        session.uuid = uuid;
        session.createdAt = [NSDate date];
        if (![session isValid]) {
            completion([NSError errorWithDomain:VOTErrorDomain
                                           code:-2
                                       userInfo:@{NSLocalizedDescriptionKey: @"Malformed VOT session response"}]);
            return;
        }

        self.session = session;
        completion(nil);
    }];
}

- (NSInteger)pollDelayForAttempt:(NSInteger)attempt remaining:(NSInteger)remaining {
    if (attempt > 0 || remaining <= 0) return 30;
    if (remaining <= 180) return MAX(1, remaining);
    return 120;
}

- (void)translateVideoURL:(NSString *)url
                 videoID:(NSString *)videoID
                duration:(NSTimeInterval)duration
          sourceLanguage:(NSString *)sourceLanguage
          targetLanguage:(NSString *)targetLanguage
                progress:(VOTProgressBlock)progress
              completion:(VOTCompletionBlock)completion {
    NSUInteger operation = ++self.operationID;
    __weak typeof(self) weakSelf = self;

    [self ensureSession:^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || operation != self.operationID) return;
        if (error) {
            completion(nil, error);
            return;
        }

        [self requestTranslationURL:url
                            videoID:videoID
                           duration:duration
                     sourceLanguage:sourceLanguage
                     targetLanguage:targetLanguage
                       firstRequest:YES
                        pollAttempt:0
               audioFallbackAllowed:YES
                          operation:operation
                           progress:progress
                         completion:completion];
    }];
}

- (void)requestTranslationURL:(NSString *)url
                      videoID:(NSString *)videoID
                     duration:(NSTimeInterval)duration
               sourceLanguage:(NSString *)sourceLanguage
               targetLanguage:(NSString *)targetLanguage
                 firstRequest:(BOOL)firstRequest
                  pollAttempt:(NSInteger)pollAttempt
         audioFallbackAllowed:(BOOL)audioFallbackAllowed
                    operation:(NSUInteger)operation
                     progress:(VOTProgressBlock)progress
                   completion:(VOTCompletionBlock)completion {
    if (operation != self.operationID) return;

    NSData *body = [VOTProto translationRequestWithURL:url
                                             duration:duration
                                       sourceLanguage:sourceLanguage
                                       targetLanguage:targetLanguage
                                         firstRequest:firstRequest
                                          livelyVoice:self.oauthToken.length > 0];

    NSString *path = @"/video-translation/translate";
    NSMutableURLRequest *request = [self requestForPath:path method:@"POST" body:body json:NO];
    [self applyHeaders:[self sessionHeadersForBody:body path:path] toRequest:request];

    if (self.oauthToken.length > 0) {
        [request setValue:[NSString stringWithFormat:@"OAuth %@", self.oauthToken]
       forHTTPHeaderField:@"Authorization"];
    }

    __weak typeof(self) weakSelf = self;
    [self performRequest:request completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || operation != self.operationID) return;
        if (error) {
            completion(nil, error);
            return;
        }

        VOTTranslation *translation = data.length ? [VOTProto decodeTranslation:data] : nil;
        if (!translation || !translation.parseValid || !translation.statusPresent) {
            completion(nil, [self httpErrorWithResponse:response description:@"Malformed VOT translation response"]);
            return;
        }

        if (progress) progress(translation);

        if ([translation isReady] && translation.audioURL.length > 0) {
            completion(translation, nil);
            return;
        }

        if (translation.status == VOTTranslationStatusSessionRequired) {
            completion(nil, [NSError errorWithDomain:VOTErrorDomain
                                                code:7
                                            userInfo:@{NSLocalizedDescriptionKey: @"Yandex authentication required"}]);
            return;
        }

        if (translation.status == VOTTranslationStatusFailed) {
            NSString *message = translation.message.length ? translation.message : @"Yandex could not translate this video";
            completion(nil, [NSError errorWithDomain:VOTErrorDomain
                                                code:0
                                            userInfo:@{NSLocalizedDescriptionKey: message}]);
            return;
        }

        if (translation.status == VOTTranslationStatusAudioRequested && audioFallbackAllowed) {
            [self handleAudioRequestedForURL:url
                                     videoID:videoID
                               translationID:translation.translationID
                                   operation:operation
                                  completion:^(NSError *fallbackError) {
                if (operation != self.operationID) return;
                if (fallbackError) {
                    completion(nil, fallbackError);
                    return;
                }

                [self requestTranslationURL:url
                                    videoID:videoID
                                   duration:duration
                             sourceLanguage:sourceLanguage
                             targetLanguage:targetLanguage
                               firstRequest:NO
                                pollAttempt:pollAttempt + 1
                       audioFallbackAllowed:NO
                                  operation:operation
                                   progress:progress
                                 completion:completion];
            }];
            return;
        }

        if ([translation isWaiting] || translation.status == VOTTranslationStatusAudioRequested) {
            NSInteger delay = [self pollDelayForAttempt:pollAttempt remaining:translation.remainingTime];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (operation != self.operationID) return;
                [self requestTranslationURL:url
                                    videoID:videoID
                                   duration:duration
                             sourceLanguage:sourceLanguage
                             targetLanguage:targetLanguage
                               firstRequest:NO
                                pollAttempt:pollAttempt + 1
                       audioFallbackAllowed:audioFallbackAllowed
                                  operation:operation
                                   progress:progress
                                 completion:completion];
            });
            return;
        }

        completion(nil, [NSError errorWithDomain:VOTErrorDomain
                                            code:-3
                                        userInfo:@{NSLocalizedDescriptionKey: @"Unexpected VOT status"}]);
    }];
}

- (void)handleAudioRequestedForURL:(NSString *)url
                           videoID:(NSString *)videoID
                     translationID:(NSString *)translationID
                         operation:(NSUInteger)operation
                        completion:(void (^)(NSError * _Nullable))completion {
    if (translationID.length == 0) {
        completion([NSError errorWithDomain:VOTErrorDomain
                                        code:-4
                                    userInfo:@{NSLocalizedDescriptionKey: @"Missing VOT translation ID"}]);
        return;
    }

    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"video_url": url}
                                                   options:0
                                                     error:nil];
    NSMutableURLRequest *failRequest = [self requestForPath:@"/video-translation/fail-audio-js"
                                                     method:@"PUT"
                                                       body:json
                                                       json:YES];

    __weak typeof(self) weakSelf = self;
    [self performRequest:failRequest completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || operation != self.operationID) return;
        if (error || response.statusCode < 200 || response.statusCode >= 300) {
            completion(error ?: [self httpErrorWithResponse:response description:@"VOT fail-audio request failed"]);
            return;
        }

        NSString *fileID = [NSString stringWithFormat:@"fallback-empty-audio:video-translation:%@", videoID];
        NSData *audioBody = [VOTProto emptyAudioRequestWithURL:url
                                                 translationID:translationID
                                                        fileID:fileID];

        NSString *path = @"/video-translation/audio";
        NSMutableURLRequest *audioRequest = [self requestForPath:path
                                                          method:@"PUT"
                                                            body:audioBody
                                                            json:NO];
        [self applyHeaders:[self sessionHeadersForBody:audioBody path:path] toRequest:audioRequest];

        [self performRequest:audioRequest completion:^(NSData *audioData, NSHTTPURLResponse *audioResponse, NSError *audioError) {
            if (operation != self.operationID) return;
            if (audioError || audioResponse.statusCode < 200 || audioResponse.statusCode >= 300) {
                completion(audioError ?: [self httpErrorWithResponse:audioResponse description:@"VOT empty-audio fallback failed"]);
                return;
            }
            completion(nil);
        }];
    }];
}

@end
