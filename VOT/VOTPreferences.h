#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const VOTPreferencesDidChangeNotification;

BOOL VOTPreferencesEnabled(void);
BOOL VOTPreferencesShowButton(void);
BOOL VOTPreferencesDiagnosticsEnabled(void);
NSString *VOTPreferencesSourceLanguage(void);
NSString *VOTPreferencesTargetLanguage(void);
float VOTPreferencesTranslationVolume(void);

void VOTPreferencesSetEnabled(BOOL enabled);
void VOTPreferencesSetShowButton(BOOL showButton);
void VOTPreferencesSetDiagnosticsEnabled(BOOL enabled);
void VOTPreferencesSetSourceLanguage(NSString *language);
void VOTPreferencesSetTargetLanguage(NSString *language);
void VOTPreferencesSetTranslationVolume(float volume);
void VOTPreferencesReset(void);

NS_ASSUME_NONNULL_END
