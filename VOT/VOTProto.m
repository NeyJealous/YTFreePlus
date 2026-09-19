#import "VOTProto.h"
#import "VOTSession.h"
#import "VOTTranslation.h"

static void VOTWriteVarint(NSMutableData *out, uint64_t value) {
    while (value >= 0x80) {
        uint8_t byte = (uint8_t)((value & 0x7F) | 0x80);
        [out appendBytes:&byte length:1];
        value >>= 7;
    }
    uint8_t byte = (uint8_t)value;
    [out appendBytes:&byte length:1];
}

static void VOTWriteTag(NSMutableData *out, NSUInteger field, NSUInteger wire) {
    VOTWriteVarint(out, ((uint64_t)field << 3) | wire);
}

static void VOTWriteBytes(NSMutableData *out, NSUInteger field, NSData *data) {
    VOTWriteTag(out, field, 2);
    VOTWriteVarint(out, data.length);
    [out appendData:data];
}

static void VOTWriteString(NSMutableData *out, NSUInteger field, NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    VOTWriteBytes(out, field, data);
}

static void VOTWriteInt(NSMutableData *out, NSUInteger field, uint64_t value) {
    VOTWriteTag(out, field, 0);
    VOTWriteVarint(out, value);
}

static void VOTWriteDouble(NSMutableData *out, NSUInteger field, double value) {
    VOTWriteTag(out, field, 1);
    uint64_t raw = 0;
    memcpy(&raw, &value, sizeof(raw));
    uint64_t little = CFSwapInt64HostToLittle(raw);
    [out appendBytes:&little length:sizeof(little)];
}

static BOOL VOTReadVarint(const uint8_t *bytes, NSUInteger length, NSUInteger *position, uint64_t *value) {
    uint64_t result = 0;
    NSUInteger shift = 0;
    while (*position < length && shift <= 63) {
        uint8_t byte = bytes[(*position)++];
        result |= ((uint64_t)(byte & 0x7F)) << shift;
        if ((byte & 0x80) == 0) {
            *value = result;
            return YES;
        }
        shift += 7;
    }
    return NO;
}

static NSDictionary<NSNumber *, id> *VOTParseFields(NSData *data, BOOL *valid) {
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSUInteger position = 0;
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    *valid = YES;

    while (position < length) {
        uint64_t tag = 0;
        if (!VOTReadVarint(bytes, length, &position, &tag)) { *valid = NO; break; }
        NSUInteger field = (NSUInteger)(tag >> 3);
        NSUInteger wire = (NSUInteger)(tag & 7);

        if (wire == 0) {
            uint64_t value = 0;
            if (!VOTReadVarint(bytes, length, &position, &value)) { *valid = NO; break; }
            fields[@(field)] = @(value);
        } else if (wire == 1) {
            if (position + 8 > length) { *valid = NO; break; }
            position += 8;
        } else if (wire == 2) {
            uint64_t size = 0;
            if (!VOTReadVarint(bytes, length, &position, &size) || position + size > length) { *valid = NO; break; }
            NSData *chunk = [NSData dataWithBytes:bytes + position length:(NSUInteger)size];
            position += (NSUInteger)size;
            NSString *string = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
            if (string) fields[@(field)] = string;
        } else if (wire == 5) {
            if (position + 4 > length) { *valid = NO; break; }
            position += 4;
        } else {
            *valid = NO;
            break;
        }
    }
    return fields;
}

@implementation VOTProto

+ (NSData *)sessionRequestWithUUID:(NSString *)uuid module:(NSString *)module {
    NSMutableData *data = [NSMutableData data];
    VOTWriteString(data, 1, uuid);
    VOTWriteString(data, 2, module);
    return data;
}

+ (VOTSession *)decodeSession:(NSData *)data {
    BOOL valid = NO;
    NSDictionary *fields = VOTParseFields(data, &valid);
    VOTSession *session = [VOTSession new];
    session.parseValid = valid;
    id key = fields[@1];
    id expires = fields[@2];
    if ([key isKindOfClass:NSString.class]) session.secretKey = key;
    if ([expires isKindOfClass:NSNumber.class]) session.expires = [expires integerValue];
    if (session.expires <= 0) session.expires = 3600;
    return session;
}

+ (NSData *)translationRequestWithURL:(NSString *)url
                            duration:(NSTimeInterval)duration
                      sourceLanguage:(NSString *)sourceLanguage
                      targetLanguage:(NSString *)targetLanguage
                        firstRequest:(BOOL)firstRequest
                         livelyVoice:(BOOL)livelyVoice {
    NSMutableData *data = [NSMutableData data];
    VOTWriteString(data, 3, url);
    VOTWriteInt(data, 5, firstRequest ? 1 : 0);
    VOTWriteDouble(data, 6, duration);
    VOTWriteInt(data, 7, 1);
    VOTWriteString(data, 8, sourceLanguage);
    VOTWriteInt(data, 9, 0);
    VOTWriteInt(data, 10, 0);
    VOTWriteString(data, 14, targetLanguage);
    VOTWriteInt(data, 15, 1);
    VOTWriteInt(data, 16, 2);
    VOTWriteInt(data, 18, livelyVoice ? 1 : 0);
    return data;
}

+ (VOTTranslation *)decodeTranslation:(NSData *)data {
    BOOL valid = NO;
    NSDictionary *fields = VOTParseFields(data, &valid);
    VOTTranslation *result = [VOTTranslation new];
    result.parseValid = valid;

    id url = fields[@1];
    id status = fields[@4];
    id remaining = fields[@5];
    id translationID = fields[@7];
    id message = fields[@9];
    id lively = fields[@10];
    id allowed = fields[@11];
    id retry = fields[@12];

    if ([url isKindOfClass:NSString.class]) result.audioURL = url;
    if ([status isKindOfClass:NSNumber.class]) {
        result.statusPresent = YES;
        result.status = (VOTTranslationStatus)[status integerValue];
    }
    if ([remaining isKindOfClass:NSNumber.class]) result.remainingTime = [remaining integerValue];
    if ([translationID isKindOfClass:NSString.class]) result.translationID = translationID;
    if ([message isKindOfClass:NSString.class]) result.message = message;
    if ([lively isKindOfClass:NSNumber.class]) result.livelyVoice = [lively boolValue];
    if ([allowed isKindOfClass:NSNumber.class]) result.allowed = [allowed boolValue];
    if ([retry isKindOfClass:NSNumber.class]) result.shouldRetry = [retry integerValue];
    return result;
}

+ (NSData *)emptyAudioRequestWithURL:(NSString *)url
                       translationID:(NSString *)translationID
                              fileID:(NSString *)fileID {
    NSMutableData *audioInfo = [NSMutableData data];
    VOTWriteString(audioInfo, 1, fileID);
    VOTWriteBytes(audioInfo, 2, [NSData data]);

    NSMutableData *data = [NSMutableData data];
    VOTWriteString(data, 1, translationID);
    VOTWriteString(data, 2, url);
    VOTWriteBytes(data, 6, audioInfo);
    return data;
}

@end
