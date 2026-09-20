#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "VOT/VOTPreferences.h"
#import "VOT/VOTManager.h"

@interface YTSettingsCell : NSObject
@end

@interface YTIIcon : NSObject
@property(nonatomic, assign) NSInteger iconType;
@end

@interface YTSettingsSectionItem : NSObject
+ (instancetype)switchItemWithTitle:(NSString *)title
                   titleDescription:(NSString *)titleDescription
            accessibilityIdentifier:(NSString *)accessibilityIdentifier
                           switchOn:(BOOL)switchOn
                        switchBlock:(BOOL (^)(YTSettingsCell *, BOOL))switchBlock
                      settingItemId:(int)settingItemId;
+ (instancetype)itemWithTitle:(NSString *)title
      accessibilityIdentifier:(NSString *)accessibilityIdentifier
              detailTextBlock:(NSString *(^)(void))detailTextBlock
                  selectBlock:(BOOL (^)(YTSettingsCell *, NSUInteger))selectBlock;
+ (instancetype)checkmarkItemWithTitle:(NSString *)title
                      titleDescription:(NSString *)titleDescription
                           selectBlock:(BOOL (^)(YTSettingsCell *, NSUInteger))selectBlock;
@end

@interface YTSettingsViewController : UIViewController
- (void)setSectionItems:(NSMutableArray *)sectionItems
            forCategory:(NSInteger)category
                  title:(NSString *)title
                   icon:(YTIIcon *)icon
       titleDescription:(NSString *)titleDescription
           headerHidden:(BOOL)headerHidden;
- (void)setSectionItems:(NSMutableArray *)sectionItems
            forCategory:(NSInteger)category
                  title:(NSString *)title
       titleDescription:(NSString *)titleDescription
           headerHidden:(BOOL)headerHidden;
- (void)pushViewController:(UIViewController *)viewController;
- (void)reloadData;
@end

@interface YTSettingsPickerViewController : UIViewController
- (instancetype)initWithNavTitle:(NSString *)navTitle
              pickerSectionTitle:(NSString *)pickerSectionTitle
                            rows:(NSArray *)rows
               selectedItemIndex:(NSUInteger)selectedItemIndex
                 parentResponder:(id)parentResponder;
@end

@interface YTSettingsGroupData : NSObject
@property(nonatomic, readonly, assign) NSUInteger type;
- (NSArray<NSNumber *> *)orderedCategories;
@end

@interface YTSettingsSectionItemManager : NSObject
- (id)parentResponder;
- (void)updateYTFreePlusVOTSectionWithEntry:(id)entry;
@end

static const NSInteger YTFPVOTSection = 'yvot';
static const NSInteger YTFPTweaksGroup = 'psyt';

static NSArray<NSString *> *YTFPSourceCodes(void) {
    return @[@"auto", @"en", @"ru", @"de", @"fr", @"es", @"it", @"zh", @"ja", @"ko", @"ar", @"lt", @"lv"];
}

static NSArray<NSString *> *YTFPSourceNames(void) {
    return @[@"Авто", @"Английский", @"Русский", @"Немецкий", @"Французский", @"Испанский", @"Итальянский", @"Китайский", @"Японский", @"Корейский", @"Арабский", @"Литовский", @"Латышский"];
}

static NSArray<NSString *> *YTFPTargetCodes(void) {
    return @[@"ru", @"en", @"kk"];
}

static NSArray<NSString *> *YTFPTargetNames(void) {
    return @[@"Русский", @"Английский", @"Казахский"];
}

static NSArray<NSNumber *> *YTFPVolumeValues(void) {
    return @[@0.25f, @0.50f, @0.75f, @1.00f];
}

static NSArray<NSString *> *YTFPVolumeNames(void) {
    return @[@"25%", @"50%", @"75%", @"100%"];
}

static NSUInteger YTFPIndexForCode(NSArray<NSString *> *codes, NSString *code) {
    NSUInteger index = [codes indexOfObject:code ?: @""];
    return index == NSNotFound ? 0 : index;
}

static NSUInteger YTFPVolumeIndex(void) {
    float volume = VOTPreferencesTranslationVolume();
    NSArray<NSNumber *> *values = YTFPVolumeValues();
    NSUInteger best = 0;
    float bestDistance = FLT_MAX;
    for (NSUInteger i = 0; i < values.count; i++) {
        float distance = fabsf(values[i].floatValue - volume);
        if (distance < bestDistance) {
            bestDistance = distance;
            best = i;
        }
    }
    return best;
}

static NSString *YTFPNameForCode(NSArray<NSString *> *codes, NSArray<NSString *> *names, NSString *code) {
    NSUInteger index = YTFPIndexForCode(codes, code);
    return index < names.count ? names[index] : code;
}

static YTSettingsViewController *YTFPSettingsDelegate(id manager) {
    id delegate = nil;
    @try {
        delegate = [manager valueForKey:@"_dataDelegate"];
    } @catch (__unused NSException *exception) {}

    if (!delegate) {
        @try {
            delegate = [manager valueForKey:@"_settingsViewControllerDelegate"];
        } @catch (__unused NSException *exception) {}
    }

    return [delegate isKindOfClass:NSClassFromString(@"YTSettingsViewController")] ? delegate : delegate;
}

static id YTFPParentResponder(YTSettingsSectionItemManager *manager) {
    if ([manager respondsToSelector:@selector(parentResponder)]) {
        return [manager parentResponder];
    }
    return manager;
}

%hook YTSettingsGroupData

- (NSArray<NSNumber *> *)orderedCategories {
    NSArray<NSNumber *> *categories = %orig;
    BOOL isTweaksGroup = self.type == YTFPTweaksGroup;
    BOOL oldUngroupedFallback = self.type == 1 &&
        !class_getClassMethod(objc_getClass("YTSettingsGroupData"), @selector(tweaks));

    if (!isTweaksGroup && !oldUngroupedFallback) return categories;
    if ([categories containsObject:@(YTFPVOTSection)]) return categories;

    NSMutableArray<NSNumber *> *mutable = [categories mutableCopy] ?: [NSMutableArray array];
    [mutable insertObject:@(YTFPVOTSection) atIndex:0];
    return mutable.copy;
}

%end

%hook YTAppSettingsPresentationData

+ (NSArray<NSNumber *> *)settingsCategoryOrder {
    NSArray<NSNumber *> *order = %orig;
    if ([order containsObject:@(YTFPVOTSection)]) return order;

    NSMutableArray<NSNumber *> *mutable = [order mutableCopy];
    NSUInteger generalIndex = [mutable indexOfObject:@(1)];
    NSUInteger insertIndex = generalIndex == NSNotFound ? 0 : generalIndex + 1;
    [mutable insertObject:@(YTFPVOTSection) atIndex:MIN(insertIndex, mutable.count)];
    return mutable.copy;
}

%end

%hook YTSettingsSectionItemManager

%new(v@:@)
- (void)updateYTFreePlusVOTSectionWithEntry:(id)entry {
    YTSettingsViewController *settings = YTFPSettingsDelegate(self);
    if (!settings) return;

    Class Item = %c(YTSettingsSectionItem);
    NSMutableArray *items = [NSMutableArray array];

    [items addObject:[Item switchItemWithTitle:@"Включить Yandex VOT"
                              titleDescription:@"Голосовой перевод видео через Yandex."
                       accessibilityIdentifier:nil
                                      switchOn:VOTPreferencesEnabled()
                                   switchBlock:^BOOL(YTSettingsCell *cell, BOOL enabled) {
        VOTPreferencesSetEnabled(enabled);
        [[VOTManager shared] applyPreferences];
        return YES;
    }
                                 settingItemId:0]];

    [items addObject:[Item switchItemWithTitle:@"Показывать кнопку VOT"
                              titleDescription:@"Показывать кнопку перевода поверх видеоплеера."
                       accessibilityIdentifier:nil
                                      switchOn:VOTPreferencesShowButton()
                                   switchBlock:^BOOL(YTSettingsCell *cell, BOOL enabled) {
        VOTPreferencesSetShowButton(enabled);
        return YES;
    }
                                 settingItemId:0]];

    YTSettingsSectionItem *source = [Item itemWithTitle:@"Исходный язык"
                                accessibilityIdentifier:nil
                                        detailTextBlock:^NSString *{
        return YTFPNameForCode(YTFPSourceCodes(), YTFPSourceNames(), VOTPreferencesSourceLanguage());
    } selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
        NSArray<NSString *> *codes = YTFPSourceCodes();
        NSArray<NSString *> *names = YTFPSourceNames();
        NSMutableArray *rows = [NSMutableArray arrayWithCapacity:codes.count];

        for (NSUInteger i = 0; i < codes.count; i++) {
            NSString *code = codes[i];
            NSString *name = names[i];
            [rows addObject:[Item checkmarkItemWithTitle:name
                                        titleDescription:nil
                                             selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
                VOTPreferencesSetSourceLanguage(code);
                [settings reloadData];
                return YES;
            }]];
        }

        NSUInteger selected = YTFPIndexForCode(codes, VOTPreferencesSourceLanguage());
        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
            initWithNavTitle:@"Исходный язык"
            pickerSectionTitle:nil
            rows:rows
            selectedItemIndex:selected
            parentResponder:YTFPParentResponder(self)];
        [settings pushViewController:picker];
        return YES;
    }];
    [items addObject:source];

    YTSettingsSectionItem *target = [Item itemWithTitle:@"Язык перевода"
                                accessibilityIdentifier:nil
                                        detailTextBlock:^NSString *{
        return YTFPNameForCode(YTFPTargetCodes(), YTFPTargetNames(), VOTPreferencesTargetLanguage());
    } selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
        NSArray<NSString *> *codes = YTFPTargetCodes();
        NSArray<NSString *> *names = YTFPTargetNames();
        NSMutableArray *rows = [NSMutableArray arrayWithCapacity:codes.count];

        for (NSUInteger i = 0; i < codes.count; i++) {
            NSString *code = codes[i];
            NSString *name = names[i];
            [rows addObject:[Item checkmarkItemWithTitle:name
                                        titleDescription:nil
                                             selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
                VOTPreferencesSetTargetLanguage(code);
                [settings reloadData];
                return YES;
            }]];
        }

        NSUInteger selected = YTFPIndexForCode(codes, VOTPreferencesTargetLanguage());
        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
            initWithNavTitle:@"Язык перевода"
            pickerSectionTitle:nil
            rows:rows
            selectedItemIndex:selected
            parentResponder:YTFPParentResponder(self)];
        [settings pushViewController:picker];
        return YES;
    }];
    [items addObject:target];

    YTSettingsSectionItem *volume = [Item itemWithTitle:@"Громкость перевода"
                                accessibilityIdentifier:nil
                                        detailTextBlock:^NSString *{
        return YTFPVolumeNames()[YTFPVolumeIndex()];
    } selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
        NSArray<NSNumber *> *values = YTFPVolumeValues();
        NSArray<NSString *> *names = YTFPVolumeNames();
        NSMutableArray *rows = [NSMutableArray arrayWithCapacity:values.count];

        for (NSUInteger i = 0; i < values.count; i++) {
            NSNumber *value = values[i];
            NSString *name = names[i];
            [rows addObject:[Item checkmarkItemWithTitle:name
                                        titleDescription:nil
                                             selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
                VOTPreferencesSetTranslationVolume(value.floatValue);
                [[VOTManager shared] applyPreferences];
                [settings reloadData];
                return YES;
            }]];
        }

        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
            initWithNavTitle:@"Громкость перевода"
            pickerSectionTitle:nil
            rows:rows
            selectedItemIndex:YTFPVolumeIndex()
            parentResponder:YTFPParentResponder(self)];
        [settings pushViewController:picker];
        return YES;
    }];
    [items addObject:volume];

    [items addObject:[Item switchItemWithTitle:@"Диагностика ошибок"
                              titleDescription:@"Показывать окно с точной ошибкой Yandex VOT."
                       accessibilityIdentifier:nil
                                      switchOn:VOTPreferencesDiagnosticsEnabled()
                                   switchBlock:^BOOL(YTSettingsCell *cell, BOOL enabled) {
        VOTPreferencesSetDiagnosticsEnabled(enabled);
        return YES;
    }
                                 settingItemId:0]];

    [items addObject:[Item itemWithTitle:@"Сбросить настройки VOT"
                 accessibilityIdentifier:nil
                         detailTextBlock:nil
                             selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
        VOTPreferencesReset();
        [[VOTManager shared] applyPreferences];
        [settings reloadData];
        return YES;
    }]];

    YTIIcon *icon = [%c(YTIIcon) new];
    icon.iconType = 44;

    if ([settings respondsToSelector:@selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:)]) {
        [settings setSectionItems:items
                      forCategory:YTFPVOTSection
                            title:@"Yandex VOT"
                             icon:icon
                 titleDescription:@"YTFreePlus"
                     headerHidden:NO];
    } else {
        [settings setSectionItems:items
                      forCategory:YTFPVOTSection
                            title:@"Yandex VOT"
                 titleDescription:@"YTFreePlus"
                     headerHidden:NO];
    }
}

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    if (category == YTFPVOTSection) {
        [self updateYTFreePlusVOTSectionWithEntry:entry];
        return;
    }
    %orig;
}

%end
