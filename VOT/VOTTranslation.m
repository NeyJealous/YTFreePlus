#import "VOTTranslation.h"
@implementation VOTTranslation
- (BOOL)isReady { return self.status == VOTTranslationStatusFinished || self.status == VOTTranslationStatusPartContent; }
- (BOOL)isComplete { return self.status == VOTTranslationStatusFinished; }
- (BOOL)isWaiting { return self.status == VOTTranslationStatusWaiting || self.status == VOTTranslationStatusLongWaiting; }
@end
