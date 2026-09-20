#import "VOTClient.h"
#import "VOTConfig.h"
#import "VOTSigner.h"
#import "VOTProto.h"
#import "VOTSession.h"
#import "VOTTranslation.h"

static NSString * const VOTErrorDomain = @"YTFreePlus.VOT";
static const NSUInteger VOTAudioChunkSize = 5295308;

@interface VOTClient ()
@property(nonatomic, strong) NSURLSession *urlSession;
@property(nonatomic, strong, nullable) VOTSession *session;
@property(nonatomic, assign) NSUInteger operationID;
@property(nonatomic, copy, nullable) NSString *lastNativeAudioError;
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
    NSString *bodySign = [VOTSigner signatureForData:body];
    if (tokenSign.length == 0 || bodySign.length == 0) return @{};
    return @{
        @"Vtrans-Signature": bodySign,
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
    NSInteger status = response ? response.statusCode : 0;
    NSString *contentType = response.allHeaderFields[@"Content-Type"];
    NSString *message = [NSString stringWithFormat:@"%@ (HTTP %ld%@)",
                         description,
                         (long)status,
                         contentType.length ? [NSString stringWithFormat:@", %@", contentType] : @""];
    return [NSError errorWithDomain:VOTErrorDomain
                               code:status
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

- (void)ensureSession:(void (^)(NSError * _Nullable))completion {
    if ([self.session isValid]) {
        completion(nil);
        return;
    }

    NSString *uuid = [VOTSigner randomToken];
    NSData *body = [VOTProto sessionRequestWithUUID:uuid module:@"video-translation"];
    NSMutableURLRequest *request = [self requestForPath:@"/session/create" method:@"POST" body:body json:NO];
    NSString *signature = [VOTSigner signatureForData:body];
    if (signature.length == 0) {
        completion([NSError errorWithDomain:VOTErrorDomain
                                       code:-10
                                   userInfo:@{NSLocalizedDescriptionKey: @"VOT signing is unavailable on this device"}]);
        return;
    }
    [request setValue:signature forHTTPHeaderField:@"Vtrans-Signature"];

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
           audioStreamURL:(NSURL *)audioStreamURL
          sourceLanguage:(NSString *)sourceLanguage
          targetLanguage:(NSString *)targetLanguage
                progress:(VOTProgressBlock)progress
              completion:(VOTCompletionBlock)completion {
    NSUInteger operation = ++self.operationID;
    self.lastNativeAudioError = nil;
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
                    audioStreamURL:audioStreamURL
                     sourceLanguage:sourceLanguage
                     targetLanguage:targetLanguage
                       firstRequest:YES
                        pollAttempt:0
               audioFallbackAllowed:YES
                 failureRetryAllowed:YES
                          operation:operation
                           progress:progress
                         completion:completion];
    }];
}

- (void)requestTranslationURL:(NSString *)url
                      videoID:(NSString *)videoID
                     duration:(NSTimeInterval)duration
                audioStreamURL:(NSURL *)audioStreamURL
               sourceLanguage:(NSString *)sourceLanguage
               targetLanguage:(NSString *)targetLanguage
                 firstRequest:(BOOL)firstRequest
                  pollAttempt:(NSInteger)pollAttempt
         audioFallbackAllowed:(BOOL)audioFallbackAllowed
           failureRetryAllowed:(BOOL)failureRetryAllowed
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

        if (response.statusCode < 200 || response.statusCode >= 300) {
            completion(nil, [self httpErrorWithResponse:response description:@"VOT translation request failed"]);
            return;
        }

        VOTTranslation *translation = data.length ? [VOTProto decodeTranslation:data] : nil;
        if (!translation || !translation.parseValid || !translation.statusPresent) {
            NSString *description = [NSString stringWithFormat:@"Malformed VOT translation response (%lu bytes)",
                                     (unsigned long)data.length];
            completion(nil, [self httpErrorWithResponse:response description:description]);
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
            if (translation.shouldRetry > 0 && failureRetryAllowed) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (operation != self.operationID) return;
                    [self requestTranslationURL:url
                                        videoID:videoID
                                       duration:duration
                              audioStreamURL:audioStreamURL
                                 sourceLanguage:sourceLanguage
                                 targetLanguage:targetLanguage
                                   firstRequest:YES
                                    pollAttempt:pollAttempt + 1
                           audioFallbackAllowed:audioFallbackAllowed
                             failureRetryAllowed:NO
                                      operation:operation
                                       progress:progress
                                     completion:completion];
                });
                return;
            }

            NSString *baseMessage = translation.message.length
                ? translation.message
                : @"Yandex could not translate this video";
            NSString *nativeAudioInfo = self.lastNativeAudioError.length
                ? [NSString stringWithFormat:@"\nnative audio: %@", self.lastNativeAudioError]
                : @"";
            NSString *message = [NSString stringWithFormat:@"%@\n(status=%ld, retry=%ld%@)%@",
                                 baseMessage,
                                 (long)translation.status,
                                 (long)translation.shouldRetry,
                                 translation.translationID.length
                                     ? [NSString stringWithFormat:@", id=%@", translation.translationID]
                                     : @"",
                                 nativeAudioInfo];
            completion(nil, [NSError errorWithDomain:VOTErrorDomain
                                                code:translation.status
                                            userInfo:@{NSLocalizedDescriptionKey: message}]);
            return;
        }

        if (translation.status == VOTTranslationStatusAudioRequested && audioFallbackAllowed) {
            [self handleAudioRequestedForURL:url
                                     videoID:videoID
                               translationID:translation.translationID
                              audioStreamURL:audioStreamURL
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
                            audioStreamURL:audioStreamURL
                             sourceLanguage:sourceLanguage
                             targetLanguage:targetLanguage
                               firstRequest:YES
                                pollAttempt:pollAttempt + 1
                       audioFallbackAllowed:NO
                         failureRetryAllowed:failureRetryAllowed
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
                            audioStreamURL:audioStreamURL
                             sourceLanguage:sourceLanguage
                             targetLanguage:targetLanguage
                               firstRequest:NO
                                pollAttempt:pollAttempt + 1
                       audioFallbackAllowed:audioFallbackAllowed
                         failureRetryAllowed:failureRetryAllowed
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

- (NSURL *)audioURLBySettingRangeFromURL:(NSURL *)baseURL
                                     start:(long long)start
                                       end:(long long)end
                             requestNumber:(NSUInteger)requestNumber {
    if (!baseURL) return nil;

    NSURLComponents *components = [NSURLComponents componentsWithURL:baseURL resolvingAgainstBaseURL:NO];
    if (!components) return nil;

    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        NSString *name = item.name.lowercaseString;
        if ([name isEqualToString:@"range"] ||
            [name isEqualToString:@"rn"] ||
            [name isEqualToString:@"ump"]) {
            continue;
        }
        [items addObject:item];
    }

    [items addObject:[NSURLQueryItem queryItemWithName:@"range"
                                                 value:[NSString stringWithFormat:@"%lld-%lld", start, end]]];
    [items addObject:[NSURLQueryItem queryItemWithName:@"rn"
                                                 value:[NSString stringWithFormat:@"%lu", (unsigned long)requestNumber]]];
    components.queryItems = items;
    return components.URL;
}

- (long long)audioContentLengthFromURL:(NSURL *)URL {
    if (!URL) return 0;
    NSURLComponents *components = [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        if ([item.name.lowercaseString isEqualToString:@"clen"]) {
            long long value = item.value.longLongValue;
            if (value > 0) return value;
        }
    }
    return 0;
}

- (long long)audioContentLengthFromResponse:(NSHTTPURLResponse *)response {
    if (!response) return 0;

    NSString *contentRange = nil;
    for (id key in response.allHeaderFields) {
        if ([[key description] caseInsensitiveCompare:@"Content-Range"] == NSOrderedSame) {
            contentRange = [response.allHeaderFields[key] description];
            break;
        }
    }

    NSRange slash = [contentRange rangeOfString:@"/" options:NSBackwardsSearch];
    if (slash.location != NSNotFound && slash.location + 1 < contentRange.length) {
        NSString *total = [contentRange substringFromIndex:slash.location + 1];
        long long value = total.longLongValue;
        if (value > 0) return value;
    }
    return 0;
}

- (void)probeAudioContentLengthForURL:(NSURL *)audioStreamURL
                            operation:(NSUInteger)operation
                           completion:(void (^)(long long contentLength, NSError * _Nullable error))completion {
    long long embeddedLength = [self audioContentLengthFromURL:audioStreamURL];
    if (embeddedLength > 0) {
        completion(embeddedLength, nil);
        return;
    }

    NSURL *probeURL = [self audioURLBySettingRangeFromURL:audioStreamURL
                                                    start:0
                                                      end:0
                                            requestNumber:1];
    if (!probeURL) {
        completion(0, [NSError errorWithDomain:VOTErrorDomain
                                          code:-20
                                      userInfo:@{NSLocalizedDescriptionKey: @"YouTube audio URL is invalid"}]);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:probeURL];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 45;

    __weak typeof(self) weakSelf = self;
    [self performRequest:request completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || operation != self.operationID) return;

        if (error) {
            completion(0, error);
            return;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
            completion(0, [self httpErrorWithResponse:response description:@"YouTube audio probe failed"]);
            return;
        }

        long long contentLength = [self audioContentLengthFromResponse:response];
        if (contentLength <= 0) {
            completion(0, [NSError errorWithDomain:VOTErrorDomain
                                              code:-21
                                          userInfo:@{NSLocalizedDescriptionKey:
                                              @"Could not determine YouTube audio size"}]);
            return;
        }

        completion(contentLength, nil);
    }];
}

- (void)downloadAudioChunkFromURL:(NSURL *)audioStreamURL
                            start:(long long)start
                              end:(long long)end
                    requestNumber:(NSUInteger)requestNumber
                        operation:(NSUInteger)operation
                       completion:(void (^)(NSData * _Nullable data, NSError * _Nullable error))completion {
    NSURL *rangeURL = [self audioURLBySettingRangeFromURL:audioStreamURL
                                                    start:start
                                                      end:end
                                            requestNumber:requestNumber];
    if (!rangeURL) {
        completion(nil, [NSError errorWithDomain:VOTErrorDomain
                                            code:-22
                                        userInfo:@{NSLocalizedDescriptionKey: @"Could not build YouTube audio range URL"}]);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:rangeURL];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 120;

    __weak typeof(self) weakSelf = self;
    [self performRequest:request completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || operation != self.operationID) return;

        if (error) {
            completion(nil, error);
            return;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
            completion(nil, [self httpErrorWithResponse:response description:@"YouTube audio range request failed"]);
            return;
        }

        NSUInteger expectedLength = (NSUInteger)(end - start + 1);
        if (data.length != expectedLength) {
            completion(nil, [NSError errorWithDomain:VOTErrorDomain
                                                code:-23
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Incomplete YouTube audio chunk (%lu/%lu bytes)",
                                                 (unsigned long)data.length,
                                                 (unsigned long)expectedLength]}]);
            return;
        }

        completion(data, nil);
    }];
}

- (void)uploadAudioChunk:(NSData *)audioData
                     url:(NSString *)url
           translationID:(NSString *)translationID
                  fileID:(NSString *)fileID
                 chunkID:(NSInteger)chunkID
            partsLength:(NSInteger)partsLength
               operation:(NSUInteger)operation
              completion:(void (^)(NSError * _Nullable error))completion {
    NSData *body = [VOTProto partialAudioRequestWithURL:url
                                          translationID:translationID
                                                 fileID:fileID
                                                chunkID:chunkID
                                           partsLength:partsLength
                                                  data:audioData];
    NSString *path = @"/video-translation/audio";
    NSMutableURLRequest *request = [self requestForPath:path
                                                method:@"PUT"
                                                  body:body
                                                  json:NO];
    [self applyHeaders:[self sessionHeadersForBody:body path:path] toRequest:request];

    __weak typeof(self) weakSelf = self;
    [self performRequest:request completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || operation != self.operationID) return;

        if (error) {
            completion(error);
            return;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
            completion([self httpErrorWithResponse:response description:@"VOT audio chunk upload failed"]);
            return;
        }
        completion(nil);
    }];
}

- (void)downloadAndUploadAudioForURL:(NSString *)url
                       audioStreamURL:(NSURL *)audioStreamURL
                       translationID:(NSString *)translationID
                              fileID:(NSString *)fileID
                       contentLength:(long long)contentLength
                               index:(NSInteger)index
                          totalParts:(NSInteger)totalParts
                           operation:(NSUInteger)operation
                          completion:(void (^)(NSError * _Nullable error))completion {
    if (operation != self.operationID) return;
    if (index >= totalParts) {
        completion(nil);
        return;
    }

    long long start = (long long)index * (long long)VOTAudioChunkSize;
    long long end = MIN(contentLength - 1, start + (long long)VOTAudioChunkSize - 1);

    __weak typeof(self) weakSelf = self;
    [self downloadAudioChunkFromURL:audioStreamURL
                              start:start
                                end:end
                      requestNumber:(NSUInteger)index + 1
                          operation:operation
                         completion:^(NSData *data, NSError *downloadError) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || operation != self.operationID) return;

        if (downloadError || data.length == 0) {
            completion(downloadError ?: [NSError errorWithDomain:VOTErrorDomain
                                                            code:-24
                                                        userInfo:@{NSLocalizedDescriptionKey: @"YouTube audio chunk is empty"}]);
            return;
        }

        BOOL isLast = index == totalParts - 1;
        NSInteger announcedParts = isLast ? totalParts : 0;
        [self uploadAudioChunk:data
                           url:url
                 translationID:translationID
                        fileID:fileID
                       chunkID:index
                  partsLength:announcedParts
                     operation:operation
                    completion:^(NSError *uploadError) {
            if (operation != self.operationID) return;
            if (uploadError) {
                completion(uploadError);
                return;
            }

            [self downloadAndUploadAudioForURL:url
                                audioStreamURL:audioStreamURL
                                translationID:translationID
                                       fileID:fileID
                                contentLength:contentLength
                                        index:index + 1
                                   totalParts:totalParts
                                    operation:operation
                                   completion:completion];
        }];
    }];
}

- (void)uploadNativeAudioForURL:(NSString *)url
                        videoID:(NSString *)videoID
                  translationID:(NSString *)translationID
                 audioStreamURL:(NSURL *)audioStreamURL
                      operation:(NSUInteger)operation
                     completion:(void (^)(NSError * _Nullable error))completion {
    if (!audioStreamURL) {
        completion([NSError errorWithDomain:VOTErrorDomain
                                       code:-25
                                   userInfo:@{NSLocalizedDescriptionKey: @"YouTube audio stream is unavailable"}]);
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self probeAudioContentLengthForURL:audioStreamURL
                              operation:operation
                             completion:^(long long contentLength, NSError *probeError) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || operation != self.operationID) return;

        if (probeError || contentLength <= 0) {
            completion(probeError ?: [NSError errorWithDomain:VOTErrorDomain
                                                         code:-26
                                                     userInfo:@{NSLocalizedDescriptionKey: @"YouTube audio size is unavailable"}]);
            return;
        }

        NSInteger totalParts = (NSInteger)((contentLength + (long long)VOTAudioChunkSize - 1) /
                                           (long long)VOTAudioChunkSize);
        if (totalParts <= 0) {
            completion([NSError errorWithDomain:VOTErrorDomain
                                           code:-27
                                       userInfo:@{NSLocalizedDescriptionKey: @"Invalid YouTube audio chunk count"}]);
            return;
        }

        NSString *fileID = [NSString stringWithFormat:@"random-web_abr-%@",
                            NSUUID.UUID.UUIDString.lowercaseString];

        [self downloadAndUploadAudioForURL:url
                            audioStreamURL:audioStreamURL
                            translationID:translationID
                                   fileID:fileID
                            contentLength:contentLength
                                    index:0
                               totalParts:totalParts
                                operation:operation
                               completion:completion];
    }];
}

- (void)handleEmptyAudioFallbackForURL:(NSString *)url
                               videoID:(NSString *)videoID
                         translationID:(NSString *)translationID
                             operation:(NSUInteger)operation
                            completion:(void (^)(NSError * _Nullable))completion {
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

        if (data.length > 0) {
            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSNumber *status = [jsonResponse isKindOfClass:NSDictionary.class] ? jsonResponse[@"status"] : nil;
            if (status && status.integerValue != 1) {
                completion([NSError errorWithDomain:VOTErrorDomain
                                               code:-28
                                           userInfo:@{NSLocalizedDescriptionKey: @"Yandex rejected fail-audio fallback"}]);
                return;
            }
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

- (void)handleAudioRequestedForURL:(NSString *)url
                           videoID:(NSString *)videoID
                     translationID:(NSString *)translationID
                    audioStreamURL:(NSURL *)audioStreamURL
                         operation:(NSUInteger)operation
                        completion:(void (^)(NSError * _Nullable))completion {
    if (translationID.length == 0) {
        completion([NSError errorWithDomain:VOTErrorDomain
                                        code:-4
                                    userInfo:@{NSLocalizedDescriptionKey: @"Missing VOT translation ID"}]);
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self uploadNativeAudioForURL:url
                          videoID:videoID
                    translationID:translationID
                   audioStreamURL:audioStreamURL
                        operation:operation
                       completion:^(NSError *nativeError) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || operation != self.operationID) return;

        if (!nativeError) {
            self.lastNativeAudioError = nil;
            completion(nil);
            return;
        }

        self.lastNativeAudioError = nativeError.localizedDescription ?: @"unknown native audio error";
        NSLog(@"[YTFreePlus][VOT] Native audio upload failed: %@", self.lastNativeAudioError);
        [self handleEmptyAudioFallbackForURL:url
                                     videoID:videoID
                               translationID:translationID
                                   operation:operation
                                  completion:completion];
    }];
}

@end
