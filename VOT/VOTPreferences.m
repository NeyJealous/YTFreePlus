#import "VOTPreferences.h"
#import <math.h>

NSNotificationName const VOTPreferencesDidChangeNotification = @"YTFreePlus.VOTPreferencesDidChange";

static NSString * const VOTEnabledKey = @"YTFreePlus.VOT.Enabled";
static NSString * const VOTShowButtonKey = @"YTFreePlus.VOT.ShowButton";
static NSString * const VOTDiagnosticsKey = @"YTFreePlus.VOT.Diagnostics";
static NSString * const VOTSourceLanguageKey = @"YTFreePlus.VOT.SourceLanguage";
static NSString * const VOTTargetLanguageKey = @"YTFreePlus.VOT.TargetLanguage";
static NSString * const VOTTranslationVolumeKey = @"YTFreePlus.VOT.TranslationVolume";

static NSDictionary *VOTDefaultPreferences(void) {
    return @{
        VOTEnabledKey: @YES,
        VOTShowButtonKey: @YES,
        VOTDiagnosticsKey: @YES,
        VOTSourceLanguageKey: @"auto",
        VOTTargetLanguageKey: @"ru",
        VOTTranslationVolumeKey: @1.0f,
    };
}

static NSUserDefaults *VOTDefaults(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [defaults registerDefaults:VOTDefaultPreferences()];
    });
    return defaults;
}

static void VOTNotifyPreferenceChange(void) {
    [[NSNotificationCenter defaultCenter] postNotificationName:VOTPreferencesDidChangeNotification object:nil];
}

BOOL VOTPreferencesEnabled(void) {
    return [VOTDefaults() boolForKey:VOTEnabledKey];
}

BOOL VOTPreferencesShowButton(void) {
    return [VOTDefaults() boolForKey:VOTShowButtonKey];
}

BOOL VOTPreferencesDiagnosticsEnabled(void) {
    return [VOTDefaults() boolForKey:VOTDiagnosticsKey];
}

NSString *VOTPreferencesSourceLanguage(void) {
    NSString *value = [VOTDefaults() stringForKey:VOTSourceLanguageKey];
    return value.length ? value : @"auto";
}

NSString *VOTPreferencesTargetLanguage(void) {
    NSString *value = [VOTDefaults() stringForKey:VOTTargetLanguageKey];
    return value.length ? value : @"ru";
}

float VOTPreferencesTranslationVolume(void) {
    float value = [VOTDefaults() floatForKey:VOTTranslationVolumeKey];
    return fmaxf(0.0f, fminf(1.0f, value));
}

void VOTPreferencesSetEnabled(BOOL enabled) {
    [VOTDefaults() setBool:enabled forKey:VOTEnabledKey];
    VOTNotifyPreferenceChange();
}

void VOTPreferencesSetShowButton(BOOL showButton) {
    [VOTDefaults() setBool:showButton forKey:VOTShowButtonKey];
    VOTNotifyPreferenceChange();
}

void VOTPreferencesSetDiagnosticsEnabled(BOOL enabled) {
    [VOTDefaults() setBool:enabled forKey:VOTDiagnosticsKey];
    VOTNotifyPreferenceChange();
}

void VOTPreferencesSetSourceLanguage(NSString *language) {
    if (language.length == 0) language = @"auto";
    [VOTDefaults() setObject:language forKey:VOTSourceLanguageKey];
    VOTNotifyPreferenceChange();
}

void VOTPreferencesSetTargetLanguage(NSString *language) {
    if (language.length == 0) language = @"ru";
    [VOTDefaults() setObject:language forKey:VOTTargetLanguageKey];
    VOTNotifyPreferenceChange();
}

void VOTPreferencesSetTranslationVolume(float volume) {
    volume = fmaxf(0.0f, fminf(1.0f, volume));
    [VOTDefaults() setFloat:volume forKey:VOTTranslationVolumeKey];
    VOTNotifyPreferenceChange();
}

void VOTPreferencesReset(void) {
    NSUserDefaults *defaults = VOTDefaults();
    for (NSString *key in VOTDefaultPreferences()) {
        [defaults removeObjectForKey:key];
    }
    [defaults registerDefaults:VOTDefaultPreferences()];
    VOTNotifyPreferenceChange();
}
