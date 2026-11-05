#import "YTLite.h"

@interface YTSettingsSectionItemManager (YTLite)
- (void)updateYTLiteSectionWithEntry:(id)entry;
- (YTSettingsViewController *)ytl_settingsViewController;
@end

static const NSInteger YTLiteSection = 789;

static NSString *GetCacheSize() {
    NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *filesArray = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:cachePath error:nil];

    unsigned long long int folderSize = 0;
    for (NSString *fileName in filesArray) {
        NSString *filePath = [cachePath stringByAppendingPathComponent:fileName];
        NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
        folderSize += [fileAttributes fileSize];
    }

    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;

    return [formatter stringFromByteCount:folderSize];
}

// Settings
%hook YTAppSettingsPresentationData
+ (NSArray *)settingsCategoryOrder {
    NSArray *order = %orig;
    NSMutableArray *mutableOrder = [order mutableCopy];
    NSUInteger insertIndex = [order indexOfObject:@(1)];
    if (insertIndex != NSNotFound)
        [mutableOrder insertObject:@(YTLiteSection) atIndex:insertIndex + 1];
    else if ([mutableOrder count] > 0)
        [mutableOrder insertObject:@(YTLiteSection) atIndex:0];
    else
        [mutableOrder addObject:@(YTLiteSection)];
    return mutableOrder;
}
%end

// Grouped Settings (CairoSettings & YouGroupSettings compatibility)
%hook YTSettingsGroupData

+ (NSMutableArray <NSNumber *> *)tweaks {
    NSMutableArray <NSNumber *> *tweaks = %orig;
    if (tweaks && ![tweaks containsObject:@(YTLiteSection)]) {
        [tweaks insertObject:@(YTLiteSection) atIndex:0];
    }
    return tweaks;
}

- (NSArray <NSNumber *> *)orderedCategoriesForGroupType:(NSUInteger)type {
    if ([%c(YTSettingsGroupData) respondsToSelector:@selector(tweaks)]) {
        NSMutableArray *tweaks = [%c(YTSettingsGroupData) tweaks];
        if (tweaks && ![tweaks containsObject:@(YTLiteSection)]) {
            [tweaks insertObject:@(YTLiteSection) atIndex:0];
        }
    }
    NSArray *categories = %orig;
    if ((type == 'psyt' || type == 1) && categories && ![categories containsObject:@(YTLiteSection)]) {
        NSMutableArray *mutable = [categories mutableCopy];
        [mutable insertObject:@(YTLiteSection) atIndex:0];
        return mutable;
    }
    return categories;
}

- (NSArray <NSNumber *> *)orderedCategories {
    if (self.type != 1 && self.type != 'psyt') return %orig;
    NSArray *categories = %orig;
    if (categories && ![categories containsObject:@(YTLiteSection)]) {
        NSMutableArray *mutable = [categories mutableCopy];
        [mutable insertObject:@(YTLiteSection) atIndex:0];
        return mutable;
    }
    return categories;
}

%end

%hook YTSettingsSectionController
- (void)setSelectedItem:(NSUInteger)selectedItem {
    if (selectedItem != NSNotFound) %orig;
}
%end

%hook YTSettingsCell
- (void)layoutSubviews {
    %orig;

    BOOL isYTLite = [self.accessibilityIdentifier isEqualToString:@"YTLiteSectionItem"];
    YTTouchFeedbackController *feedback = [self valueForKey:@"_touchFeedbackController"];
    ABCSwitch *abcSwitch = [self valueForKey:@"_switch"];

    if (isYTLite) {
        feedback.feedbackColor = [UIColor colorWithRed:0.75 green:0.50 blue:0.90 alpha:1.0];
        abcSwitch.onTintColor = [UIColor colorWithRed:0.75 green:0.50 blue:0.90 alpha:1.0];
    }
}
%end

static void YTLitePushPicker(YTSettingsSectionItemManager *manager, YTSettingsPickerViewController *picker) {
    UIViewController *targetVC = nil;
    if ([manager respondsToSelector:@selector(ytl_settingsViewController)]) {
        targetVC = [manager ytl_settingsViewController];
    }
    if (!targetVC && manager) {
        @try { targetVC = [manager valueForKey:@"_dataDelegate"]; } @catch (NSException *e) {}
        if (!targetVC) {
            @try { targetVC = [manager valueForKey:@"_settingsViewControllerDelegate"]; } @catch (NSException *e) {}
        }
    }
    if (targetVC && [targetVC respondsToSelector:@selector(pushViewController:)]) {
        [(YTSettingsViewController *)targetVC pushViewController:picker];
    } else if (targetVC.navigationController) {
        [targetVC.navigationController pushViewController:picker animated:YES];
    } else {
        UIViewController *top = [%c(YTUIUtils) topViewControllerForPresenting];
        if (top.navigationController) {
            [top.navigationController pushViewController:picker animated:YES];
        } else {
            [top presentViewController:picker animated:YES completion:nil];
        }
    }
}

%hook YTSettingsSectionItemManager
%new
- (YTSettingsViewController *)ytl_settingsViewController {
    YTSettingsViewController *vc = nil;
    @try { vc = [self valueForKey:@"_dataDelegate"]; } @catch (NSException *e) {}
    if (!vc) {
        @try { vc = [self valueForKey:@"_settingsViewControllerDelegate"]; } @catch (NSException *e) {}
    }
    if (!vc) {
        @try { vc = [self valueForKey:@"_delegate"]; } @catch (NSException *e) {}
    }
    if (!vc) {
        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList([self class], &ivarCount);
        for (unsigned int i = 0; i < ivarCount; i++) {
            id val = object_getIvar(self, ivars[i]);
            if ([val isKindOfClass:%c(YTSettingsViewController)]) {
                vc = val;
                break;
            }
        }
        free(ivars);
    }
    return vc;
}

%new
- (YTSettingsSectionItem *)switchWithTitle:(NSString *)title key:(NSString *)key {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);
    Class YTAlertViewClass = %c(YTAlertView);
    NSString *titleDesc = [NSString stringWithFormat:@"%@Desc", title];
    NSString *desc = LOC(titleDesc);
    if ([desc isEqualToString:titleDesc]) desc = nil;

    YTSettingsSectionItem *item = [YTSettingsSectionItemClass switchItemWithTitle:LOC(title)
    titleDescription:desc
    accessibilityIdentifier:@"YTLiteSectionItem"
    switchOn:ytlBool(key)
    switchBlock:^BOOL(YTSettingsCell *cell, BOOL enabled) {
        if ([key isEqualToString:@"shortsOnlyMode"]) {
            YTAlertView *alertView = [YTAlertViewClass confirmationDialogWithAction:^{
                ytlSetBool(enabled, @"shortsOnlyMode");
            }
            actionTitle:LOC(@"Yes")
            cancelAction:^{
                [cell setSwitchOn:!enabled animated:YES];
            }
            cancelTitle:LOC(@"No")];
            alertView.title = LOC(@"Warning");
            alertView.subtitle = LOC(@"ShortsOnlyWarning");
            [alertView show];
        }

        else {
            ytlSetBool(enabled, key);

            NSArray *keys = @[@"removeLabels", @"removeIndicators", @"reExplore", @"addExplore", @"removeShorts", @"removeSubscriptions", @"removeUploads", @"removeLibrary"];
            if ([keys containsObject:key]) {
                [[[%c(YTHeaderContentComboViewController) alloc] init] refreshPivotBar];
            }
        }

        return YES;
    }
    settingItemId:0];

    return item;
}

%new
- (YTSettingsSectionItem *)linkWithTitle:(NSString *)title description:(NSString *)description link:(NSString *)link {
    return [%c(YTSettingsSectionItem) itemWithTitle:title
    titleDescription:description
    accessibilityIdentifier:@"YTLiteSectionItem"
    detailTextBlock:nil
    selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
        return [%c(YTUIUtils) openURL:[NSURL URLWithString:link]];
    }];
}

%new(v@:@)
- (void)updateYTLiteSectionWithEntry:(id)entry {
    NSMutableArray *sectionItems = [NSMutableArray array];
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);
    YTSettingsViewController *settingsViewController = [self ytl_settingsViewController];

    YTSettingsSectionItem *space = [%c(YTSettingsSectionItem) itemWithTitle:nil accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:nil selectBlock:nil];

    // 1. General
    YTSettingsSectionItem *general = [YTSettingsSectionItemClass itemWithTitle:LOC(@"General")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() { return @"‣"; }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"RemoveAds" key:@"noAds"],
                [self switchWithTitle:@"BackgroundPlayback" key:@"backgroundPlayback"],
                [self switchWithTitle:@"ClearCacheAtStart" key:@"clearCacheAtStart"],
                [self switchWithTitle:@"FixPlayback" key:@"fixPlayback"],
                [self switchWithTitle:@"AudioDRC" key:@"audioDRC"],
                [self switchWithTitle:@"SuppressUnmute" key:@"suppressUnmute"],
                [self switchWithTitle:@"NoLinkTracking" key:@"noLinkTracking"],
                [self switchWithTitle:@"NoShareChunk" key:@"noShareChunk"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"General") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:general];

    // 2. Appearance & Theme
    YTSettingsSectionItem *appearance = [YTSettingsSectionItemClass itemWithTitle:LOC(@"OledTheme")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() { return @"‣"; }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"OledTheme" key:@"oledTheme"],
                [self switchWithTitle:@"OledKeyboard" key:@"oledKeyboard"],
                [self switchWithTitle:@"FloatingKeyboard" key:@"floatingKeyboard"],
                [self switchWithTitle:@"LiquidGlass" key:@"liquidGlass"],
                [self switchWithTitle:@"CompactToast" key:@"compactToast"],
                [self switchWithTitle:@"OldYTUI" key:@"oldYTUI"],
                [self switchWithTitle:@"DisableAmbientMode" key:@"disableAmbientMode"],
                [self switchWithTitle:@"StickyNavbar" key:@"stickyNavbar"],
                [self switchWithTitle:@"NoSubbar" key:@"noSubbar"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"OledTheme") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:appearance];

    // 3. Download Manager
    YTSettingsSectionItem *downloads = [YTSettingsSectionItemClass itemWithTitle:LOC(@"DownloadManager")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() { return @"‣"; }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            YTPDownloadsVC *downloadsVC = [[YTPDownloadsVC alloc] init];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:downloadsVC];
            [[%c(YTUIUtils) topViewControllerForPresenting] presentViewController:nav animated:YES completion:nil];
            return YES;
        }];
    [sectionItems addObject:downloads];

    // 4. Navbar
    YTSettingsSectionItem *navbar = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Navbar")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() { return @"‣"; }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"RemoveCast" key:@"noCast"],
                [self switchWithTitle:@"RemoveNotifications" key:@"noNotifsButton"],
                [self switchWithTitle:@"RemoveMessages" key:@"noMessagesButton"],
                [self switchWithTitle:@"RemoveSearch" key:@"noSearchButton"],
                [self switchWithTitle:@"RemoveVoiceSearch" key:@"noVoiceSearchButton"],
                [self switchWithTitle:@"StickyNavbar" key:@"stickyNavbar"],
                [self switchWithTitle:@"NoSubbar" key:@"noSubbar"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Navbar") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:navbar];

    // 5. Player
    YTSettingsSectionItem *player = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Player")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() { return @"‣"; }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"Miniplayer" key:@"miniplayer"],
                [self switchWithTitle:@"PortraitFullscreen" key:@"portraitFullscreen"],
                [self switchWithTitle:@"CopyWithTimestamp" key:@"copyWithTimestamp"],
                [self switchWithTitle:@"PreserveSpeed" key:@"preserveSpeed"],
                [self switchWithTitle:@"NoSharePlayPrompt" key:@"noSharePlayPrompt"],
                [self switchWithTitle:@"DisableAutoplay" key:@"disableAutoplay"],
                [self switchWithTitle:@"DisableAutoCaptions" key:@"disableAutoCaptions"],
                [self switchWithTitle:@"NoContentWarning" key:@"noContentWarning"],
                [self switchWithTitle:@"ClassicQuality" key:@"classicQuality"],
                [self switchWithTitle:@"DontSnap2Chapter" key:@"dontSnapToChapter"],
                [self switchWithTitle:@"NoTwoFingerSnapToChapter" key:@"noTwoFingerSnapToChapter"],
                [self switchWithTitle:@"AutoFullscreen" key:@"autoFullscreen"],
                [self switchWithTitle:@"ExitFullscreen" key:@"exitFullscreen"],
                [self switchWithTitle:@"SleepTimer" key:@"sleepTimer"],
                [self switchWithTitle:@"IgnoreAutoDub" key:@"ignoreAutoDub"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Player") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:player];

    // 6. Player Actions (Buttons under player)
    YTSettingsSectionItem *playerActions = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Player.Actions")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() { return @"‣"; }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"PlayerNoAsk" key:@"playerNoAsk"],
                [self switchWithTitle:@"PlayerNoClip" key:@"noPlayerClipButton"],
                [self switchWithTitle:@"PlayerNoDownload" key:@"noPlayerDownloadButton"],
                [self switchWithTitle:@"PlayerNoHype" key:@"playerNoHype"],
                [self switchWithTitle:@"PlayerNoRemix" key:@"noPlayerRemixButton"],
                [self switchWithTitle:@"PlayerNoReport" key:@"playerNoReport"],
                [self switchWithTitle:@"PlayerNoSave" key:@"playerNoSave"],
                [self switchWithTitle:@"PlayerNoShare" key:@"playerNoShare"],
                [self switchWithTitle:@"PlayerNoStopAds" key:@"playerNoStopAds"],
                [self switchWithTitle:@"PlayerNoThanks" key:@"playerNoThanks"],
                [self switchWithTitle:@"NoSubUnderPlayer" key:@"noSubUnderPlayer"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Player.Actions") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:playerActions];

    // 7. Overlay
    YTSettingsSectionItem *overlay = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Overlay")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() { return @"‣"; }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"HideAutoplay" key:@"hideAutoplay"],
                [self switchWithTitle:@"HideSubs" key:@"hideSubs"],
                [self switchWithTitle:@"NoHudMsgs" key:@"noHUDMsgs"],
                [self switchWithTitle:@"HidePrevNext" key:@"hidePrevNext"],
                [self switchWithTitle:@"ReplacePrevNext" key:@"replacePrevNext"],
                [self switchWithTitle:@"LoopButton" key:@"loopButton"],
                [self switchWithTitle:@"PiPButton" key:@"pipButton"],
                [self switchWithTitle:@"MuteButton" key:@"muteButton"],
                [self switchWithTitle:@"LockButton" key:@"lockButton"],
                [self switchWithTitle:@"FullscreenButton" key:@"fullscreenButton"],
                [self switchWithTitle:@"HideOverlayTitle" key:@"hideOverlayTitle"],
                [self switchWithTitle:@"NoDarkBg" key:@"noDarkBg"],
                [self switchWithTitle:@"NoEndScreenCards" key:@"endScreenCards"],
                [self switchWithTitle:@"NoAutonavEndScreenCards" key:@"noAutonavEndScreenCards"],
                [self switchWithTitle:@"NoFullscreenActions" key:@"noFullscreenActions"],
                [self switchWithTitle:@"PersistentProgressBar" key:@"persistentProgressBar"],
                [self switchWithTitle:@"RedProgressBar" key:@"redProgressBar"],
                [self switchWithTitle:@"StockVolumeHUD" key:@"stockVolumeHUD"],
                [self switchWithTitle:@"NoRelatedVids" key:@"noRelatedVids"],
                [self switchWithTitle:@"NoPromotionCards" key:@"noPromotionCards"],
                [self switchWithTitle:@"NoWatermarks" key:@"noWatermarks"],
                [self switchWithTitle:@"VideoEndTime" key:@"videoEndTime"],
                [self switchWithTitle:@"24hrFormat" key:@"24hrFormat"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Overlay") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:overlay];

    // 8. Gestures
    YTSettingsSectionItem *gestures = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Player.Gestures")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() { return @"‣"; }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"SeekAnywhere" key:@"seekAnywhere"],
                [self switchWithTitle:@"SeekAnywhereFeed" key:@"seekAnywhereFeed"],
                [self switchWithTitle:@"TapToSeek" key:@"tapToSeek"],
                [self switchWithTitle:@"NoDoubleTap2Seek" key:@"noDoubleTapToSeek"],
                [self switchWithTitle:@"AdjustWithFinger" key:@"adjustWithFinger"],
                [self switchWithTitle:@"TwoFingerPanToBrightness" key:@"twoFingerPanToBrightness"],
                [self switchWithTitle:@"TwoFingerTapToPause" key:@"twoFingerTapToPause"],
                [self switchWithTitle:@"PauseOnOverlay" key:@"pauseOnOverlay"],
                [self switchWithTitle:@"NoFreeZoom" key:@"noFreeZoom"],
                [self switchWithTitle:@"NoHints" key:@"noHints"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Player.Gestures") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:gestures];

    // 9. Shorts
    YTSettingsSectionItem *shorts = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Shorts")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() { return @"‣"; }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"ShortsOnlyMode" key:@"shortsOnlyMode"],
                [self switchWithTitle:@"AutoSkipShorts" key:@"autoSkipShorts"],
                [self switchWithTitle:@"SpeedByLongTap" key:@"speedByLongTap"],
                [self switchWithTitle:@"HideShorts" key:@"hideShorts"],
                [self switchWithTitle:@"HideShortsSubscribe" key:@"hideShortsSubscribe"],
                [self switchWithTitle:@"HideShortsLike" key:@"hideShortsLike"],
                [self switchWithTitle:@"HideShortsComments" key:@"hideShortsComments"],
                [self switchWithTitle:@"HideShortsRemix" key:@"hideShortsRemix"],
                [self switchWithTitle:@"HideShortsShare" key:@"hideShortsShare"],
                [self switchWithTitle:@"HideShortsDownload" key:@"hideShortsDownload"],
                [self switchWithTitle:@"HideShortsMute" key:@"hideShortsMute"],
                [self switchWithTitle:@"HideShortsAudio" key:@"hideShortsAudio"],
                [self switchWithTitle:@"HideShortsAudioButton" key:@"hideShortsAudioButton"],
                [self switchWithTitle:@"HideShortsCommentBar" key:@"hideShortsCommentBar"],
                [self switchWithTitle:@"HideShortsProducts" key:@"hideShortsProducts"],
                [self switchWithTitle:@"HideShortsSuggestion" key:@"hideShortsSuggestion"],
                [self switchWithTitle:@"HideShortsUsername" key:@"hideShortsUsername"],
                [self switchWithTitle:@"HideShortsDescription" key:@"hideShortsDescription"],
                [self switchWithTitle:@"HideShortsLogo" key:@"hideShortsLogo"],
                [self switchWithTitle:@"HideShortsSearch" key:@"hideShortsSearch"],
                [self switchWithTitle:@"HideShortsMore" key:@"hideShortsMore"],
                [self switchWithTitle:@"RemoveShortsLive" key:@"removeShortsLive"],
                [self switchWithTitle:@"RemoveShortsPosts" key:@"removeShortsPosts"],
                [self switchWithTitle:@"ShortsProgress" key:@"shortsProgress"],
                [self switchWithTitle:@"PinchToFullscreenShorts" key:@"pinchToFullscreenShorts"],
                [self switchWithTitle:@"ShortsToRegular" key:@"shortsToRegular"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Shorts") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:shorts];

    // 10. Tabbar
    YTSettingsSectionItem *tabbar = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Tabbar")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() { return @"‣"; }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"RemoveLabels" key:@"removeLabels"],
                [self switchWithTitle:@"RemoveIndicators" key:@"removeIndicators"],
                [self switchWithTitle:@"RemoveShorts" key:@"removeShorts"],
                [self switchWithTitle:@"RemoveSubscriptions" key:@"removeSubscriptions"],
                [self switchWithTitle:@"RemoveUploads" key:@"removeUploads"],
                [self switchWithTitle:@"RemoveLibrary" key:@"removeLibrary"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Tabbar") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:tabbar];

    // 11. Feed & Content Filter
    YTSettingsSectionItem *feed = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Feed")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() { return @"‣"; }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"RemovePlayables" key:@"removePlayables"],
                [self switchWithTitle:@"RemoveMembersOnly" key:@"removeMembersOnly"],
                [self switchWithTitle:@"RemoveUpcomingLives" key:@"removeUpcomingLives"],
                [self switchWithTitle:@"RemoveLiveVids" key:@"removeLiveVids"],
                [self switchWithTitle:@"RemovePlaylists" key:@"removePlaylists"],
                [self switchWithTitle:@"RemoveMixPlaylists" key:@"removeMixPlaylists"],
                [self switchWithTitle:@"KeepPlaylistsInSubscriptions" key:@"keepPlaylistsInSubscriptions"],
                [self switchWithTitle:@"KeepSubsShorts" key:@"keepSubsShorts"],
                [self switchWithTitle:@"RemoveHorizontalFeeds" key:@"removeHorizontalFeeds"],
                [self switchWithTitle:@"RemoveCommunityPosts" key:@"removeCommunityPosts"],
                [self switchWithTitle:@"RemoveInlineComment" key:@"removeInlineComment"],
                [self switchWithTitle:@"RemoveCommentGuidelines" key:@"removeCommentGuidelines"],
                [self switchWithTitle:@"RemoveMoreTopics" key:@"removeMoreTopics"],
                [self switchWithTitle:@"NoMoreVideosButton" key:@"noMoreVideosButton"],
                [self switchWithTitle:@"NoSearchHistory" key:@"noSearchHistory"],
                [self switchWithTitle:@"NoRelatedWatchNexts" key:@"noRelatedWatchNexts"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Feed") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:feed];

    // 12. SponsorBlock
    YTSettingsSectionItem *sb = [YTSettingsSectionItemClass itemWithTitle:LOC(@"EnableSponsorBlock")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() { return @"‣"; }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"EnableSponsorBlock" key:@"enableSponsorBlock"],
                [self switchWithTitle:@"Sponsor" key:@"sbSponsor"],
                [self switchWithTitle:@"Intro" key:@"sbIntro"],
                [self switchWithTitle:@"Endcards" key:@"sbEndcards"],
                [self switchWithTitle:@"SelfPromo" key:@"sbSelfPromo"],
                [self switchWithTitle:@"Interaction" key:@"sbInteraction"],
                [self switchWithTitle:@"Jokes" key:@"sbJokes"],
                [self switchWithTitle:@"MusicOfftopic" key:@"sbMusicOfftopic"],
                [self switchWithTitle:@"Highlight" key:@"sbHighlight"],
                [self switchWithTitle:@"SegmentSkipAudio" key:@"segmentSkipAudio"],
                [self switchWithTitle:@"SegmentSkipFeedback" key:@"segmentSkipFeedback"],
                [self switchWithTitle:@"DurationWithoutSegments" key:@"durationWithoutSegments"],
                [self switchWithTitle:@"SbPlayerButton" key:@"sbPlayerButton"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"EnableSponsorBlock") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:sb];

    // 13. Other
    YTSettingsSectionItem *other = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Other")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() { return @"‣"; }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"PostManager" key:@"postManager"],
                [self switchWithTitle:@"SaveProfilePhoto" key:@"saveProfilePhoto"],
                [self switchWithTitle:@"CommentManager" key:@"commentManager"],
                [self switchWithTitle:@"FixAlbums" key:@"fixAlbums"],
                [self switchWithTitle:@"NativeShare" key:@"nativeShare"],
                [self switchWithTitle:@"RemoveRemixMenu" key:@"removeRemixMenu"],
                [self switchWithTitle:@"RemoveYTMMenu" key:@"removeYTMMenu"],
                [self switchWithTitle:@"RemoveFeedbackMenu" key:@"removeFeedbackMenu"],
                [self switchWithTitle:@"RemovePlayLast" key:@"removePlayLast"],
                [self switchWithTitle:@"RemovePlayOnDifferent" key:@"removePlayOnDifferent"],
                [self switchWithTitle:@"RemovePlayNext" key:@"removePlayNext"],
                [self switchWithTitle:@"RemoveDownloadMenu" key:@"removeDownloadMenu"],
                [self switchWithTitle:@"RemoveWatchLaterMenu" key:@"removeWatchLaterMenu"],
                [self switchWithTitle:@"RemoveSaveToPlaylistMenu" key:@"removeSaveToPlaylistMenu"],
                [self switchWithTitle:@"RemoveShareMenu" key:@"removeShareMenu"],
                [self switchWithTitle:@"RemoveNotInterestedMenu" key:@"removeNotInterestedMenu"],
                [self switchWithTitle:@"RemoveDontRecommendMenu" key:@"removeDontRecommendMenu"],
                [self switchWithTitle:@"RemoveReportMenu" key:@"removeReportMenu"],
                [self switchWithTitle:@"StickSortComments" key:@"stickSortComments"],
                [self switchWithTitle:@"HideSortComments" key:@"hideSortComments"],
                [self switchWithTitle:@"PlaylistOldMinibar" key:@"playlistOldMinibar"],
                [self switchWithTitle:@"DisableRTL" key:@"disableRTL"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Other") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:other];

    [sectionItems addObject:space];

    // Numerical / Choice pickers
    YTSettingsSectionItem *speed = [YTSettingsSectionItemClass itemWithTitle:LOC(@"HoldToSpeed")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            NSArray *speedLabels = @[LOC(@"Disabled"), LOC(@"Default"), @"0.25×", @"0.5×", @"0.75×", @"1.0×", @"1.25×", @"1.5×", @"1.75×", @"2.0×", @"3.0×", @"4.0×", @"5.0×"];
            return speedLabels[ytlInt(@"speedIndex")];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            NSArray *speedLabels = @[LOC(@"Disable"), LOC(@"Default"), @"0.25×", @"0.5×", @"0.75×", @"1.0×", @"1.25×", @"1.5×", @"1.75×", @"2.0×", @"3.0×", @"4.0×", @"5.0×"];

            for (NSUInteger i = 0; i < speedLabels.count; i++) {
                NSString *title = speedLabels[i];
                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    [[self ytl_settingsViewController] reloadData];
                    ytlSetInt((int)arg1, @"speedIndex");
                    return YES;
                }];
                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"HoldToSpeed") pickerSectionTitle:nil rows:rows selectedItemIndex:ytlInt(@"speedIndex") parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:speed];

    YTSettingsSectionItem *autoSpeed = [YTSettingsSectionItemClass itemWithTitle:LOC(@"DefaultPlaybackRate")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            NSArray *speedLabels = @[@"0.25×", @"0.5×", @"0.75×", @"1.0×", @"1.25×", @"1.5×", @"1.75×", @"2.0×", @"3.0×", @"4.0×", @"5.0×"];
            return speedLabels[ytlInt(@"autoSpeedIndex")];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            NSArray *speedLabels = @[@"0.25×", @"0.5×", @"0.75×", @"1.0×", @"1.25×", @"1.5×", @"1.75×", @"2.0×", @"3.0×", @"4.0×", @"5.0×"];

            for (NSUInteger i = 0; i < speedLabels.count; i++) {
                NSString *title = speedLabels[i];
                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    [[self ytl_settingsViewController] reloadData];
                    ytlSetInt((int)arg1, @"autoSpeedIndex");
                    return YES;
                }];
                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"DefaultPlaybackRate") pickerSectionTitle:nil rows:rows selectedItemIndex:ytlInt(@"autoSpeedIndex") parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:autoSpeed];

    YTSettingsSectionItem *wifiQuality = [YTSettingsSectionItemClass itemWithTitle:LOC(@"PlaybackQualityOnWiFi")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            NSArray *qualityLabels = @[LOC(@"Default"), LOC(@"Best"), @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60", @"1080p", @"720p60", @"720p", @"480p", @"360p"];
            return qualityLabels[ytlInt(@"wiFiQualityIndex")];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            NSArray *qualityLabels = @[LOC(@"Default"), LOC(@"Best"), @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60", @"1080p", @"720p60", @"720p", @"480p", @"360p"];

            for (NSUInteger i = 0; i < qualityLabels.count; i++) {
                NSString *title = qualityLabels[i];
                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    [[self ytl_settingsViewController] reloadData];
                    ytlSetInt((int)arg1, @"wiFiQualityIndex");
                    return YES;
                }];
                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"SelectQuality") pickerSectionTitle:nil rows:rows selectedItemIndex:ytlInt(@"wiFiQualityIndex") parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:wifiQuality];

    YTSettingsSectionItem *cellQuality = [YTSettingsSectionItemClass itemWithTitle:LOC(@"PlaybackQualityOnCellular")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            NSArray *qualityLabels = @[LOC(@"Default"), LOC(@"Best"), @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60", @"1080p", @"720p60", @"720p", @"480p", @"360p"];
            return qualityLabels[ytlInt(@"cellQualityIndex")];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            NSArray *qualityLabels = @[LOC(@"Default"), LOC(@"Best"), @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60", @"1080p", @"720p60", @"720p", @"480p", @"360p"];

            for (NSUInteger i = 0; i < qualityLabels.count; i++) {
                NSString *title = qualityLabels[i];
                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    [[self ytl_settingsViewController] reloadData];
                    ytlSetInt((int)arg1, @"cellQualityIndex");
                    return YES;
                }];
                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"SelectQuality") pickerSectionTitle:nil rows:rows selectedItemIndex:ytlInt(@"cellQualityIndex") parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:cellQuality];

    YTSettingsSectionItem *startup = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Startup")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            NSArray *tabLabels = @[LOC(@"Home"), LOC(@"Explore"), LOC(@"ShortsTab"), LOC(@"Subscriptions"), LOC(@"Library")];
            return tabLabels[ytlInt(@"pivotIndex")];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            NSArray *tabLabels = @[LOC(@"Home"), LOC(@"Explore"), LOC(@"ShortsTab"), LOC(@"Subscriptions"), LOC(@"Library")];

            for (NSUInteger i = 0; i < tabLabels.count; i++) {
                NSString *title = tabLabels[i];
                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    [[self ytl_settingsViewController] reloadData];
                    ytlSetInt((int)arg1, @"pivotIndex");
                    return YES;
                }];
                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Startup") pickerSectionTitle:nil rows:rows selectedItemIndex:ytlInt(@"pivotIndex") parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:startup];

    [sectionItems addObject:space];

    YTSettingsSectionItem *thanks = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Contributors")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() { return @"‣"; }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self linkWithTitle:@"Dayanch96" description:LOC(@"Developer") link:@"https://github.com/Dayanch96/"],
                [self linkWithTitle:@"Dan Pashin" description:LOC(@"SpecialThanks") link:@"https://github.com/danpashin/"],
                space,
                [self linkWithTitle:@"Stalker" description:LOC(@"ChineseSimplified") link:@"https://github.com/xiangfeidexiaohuo"],
                [self linkWithTitle:@"Clement" description:LOC(@"ChineseTraditional") link:@"https://twitter.com/a100900900"],
                [self linkWithTitle:@"Balackburn" description:LOC(@"French") link:@"https://github.com/Balackburn"],
                [self linkWithTitle:@"DeciBelioS" description:LOC(@"Spanish") link:@"https://github.com/Deci8BelioS"],
                [self linkWithTitle:@"SKEIDs" description:LOC(@"Japanese") link:@"https://github.com/SKEIDs"],
                [self linkWithTitle:@"Hiepvk" description:LOC(@"Vietnamese") link:@"https://github.com/hiepvk"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"About") pickerSectionTitle:LOC(@"Credits") rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:thanks];

    YTSettingsSectionItem *sources = [YTSettingsSectionItemClass itemWithTitle:LOC(@"OpenSourceLibs")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() { return @"‣"; }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self linkWithTitle:@"PoomSmart" description:@"YouTube-X, YTNoPremium, YTClassicVideoQuality, YTShortsProgress, YTReExplore, SkipContentWarning, YTAutoFullscreen, YouTubeHeaders" link:@"https://github.com/PoomSmart/"],
                [self linkWithTitle:@"MiRO92" description:@"YTNoShorts" link:@"https://github.com/MiRO92/YTNoShorts"],
                [self linkWithTitle:@"Tony Million" description:@"Reachability" link:@"https://github.com/tonymillion/Reachability"],
                [self linkWithTitle:@"jkhsjdhjs" description:@"YouTube Native Share" link:@"https://github.com/jkhsjdhjs/youtube-native-share"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"About") pickerSectionTitle:LOC(@"Credits") rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:sources];

    YTSettingsSectionItem *version = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Version")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() { return @(OS_STRINGIFY(TWEAK_VERSION)); }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"Advanced" key:@"advancedMode"],

                [%c(YTSettingsSectionItem) itemWithTitle:LOC(@"ClearCache") titleDescription:nil accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:^NSString *() { return GetCacheSize(); } selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
                        [[NSFileManager defaultManager] removeItemAtPath:cachePath error:nil];
                    });
                    [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Done") firstResponder:[self parentResponder]] send];
                    return YES;
                }],

                [%c(YTSettingsSectionItem) itemWithTitle:LOC(@"ResetSettings") titleDescription:nil accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    YTAlertView *alertView = [%c(YTAlertView) confirmationDialogWithAction:^{
                        [YTLUserDefaults resetUserDefaults];
                        [[UIApplication sharedApplication] performSelector:@selector(suspend)];
                        [NSThread sleepForTimeInterval:1.0];
                        exit(0);
                    }
                    actionTitle:LOC(@"Yes")
                    cancelTitle:LOC(@"No")];
                    alertView.title = LOC(@"Warning");
                    alertView.subtitle = LOC(@"ResetMessage");
                    [alertView show];
                    return YES;
                }]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"About") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            YTLitePushPicker(self, picker);
            return YES;
        }];
    [sectionItems addObject:version];

    YTSettingsViewController *settingsVC = settingsViewController ?: [self ytl_settingsViewController];
    id settingsIcon = nil;
    if (%c(YTIIcon)) {
        id ytIcon = [%c(YTIIcon) new];
        if ([ytIcon respondsToSelector:@selector(setIconType:)]) {
            [ytIcon setValue:@(44) forKey:@"iconType"];
        }
        settingsIcon = ytIcon;
    }

    if ([settingsVC respondsToSelector:@selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:)]) {
        [settingsVC setSectionItems:sectionItems forCategory:YTLiteSection title:@"YTLite" icon:settingsIcon titleDescription:nil headerHidden:NO];
    } else if ([settingsVC respondsToSelector:@selector(setSectionItems:forCategory:title:titleDescription:headerHidden:)]) {
        [settingsVC setSectionItems:sectionItems forCategory:YTLiteSection title:@"YTLite" titleDescription:nil headerHidden:NO];
    }
}

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    if (category == YTLiteSection) {
        [self updateYTLiteSectionWithEntry:entry];
        return;
    } %orig;
}

%new
- (UIImage *)resizedImageNamed:(NSString *)iconName {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32, 32)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        UIView *imageView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 32, 32)];
        UIImageView *iconImageView = [[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:[NSBundle.ytl_defaultBundle pathForResource:iconName ofType:@"png"]]];
        iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        iconImageView.clipsToBounds = YES;
        iconImageView.frame = imageView.bounds;
        [imageView addSubview:iconImageView];
        [imageView.layer renderInContext:rendererContext.CGContext];
    }];
    return image;
}
%end

%hook YTSettingsViewController

- (void)setSectionItems:(NSMutableArray *)sectionItems forCategory:(NSInteger)category title:(NSString *)title icon:(id)icon titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden {
    if (category == YTLiteSection && icon == nil && %c(YTIIcon)) {
        id ytIcon = [%c(YTIIcon) new];
        if ([ytIcon respondsToSelector:@selector(setIconType:)]) {
            [ytIcon setValue:@(44) forKey:@"iconType"];
        }
        icon = ytIcon;
    }
    %orig(sectionItems, category, title, icon, titleDescription, headerHidden);
}

%end

%ctor {
    %init;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        if ([%c(YTSettingsGroupData) respondsToSelector:@selector(tweaks)]) {
            NSMutableArray *tweaks = [%c(YTSettingsGroupData) tweaks];
            if (tweaks && ![tweaks containsObject:@(YTLiteSection)]) {
                [tweaks insertObject:@(YTLiteSection) atIndex:0];
            }
        }
    }];
}
