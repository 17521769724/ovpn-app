//
//  RHCommon.mm
//  SplitScreenRH —— 公共工具实现（Objective-C++）
//

#import "RHCommon.h"
#import <objc/message.h>
#import <dlfcn.h>

#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

NSString *const RHNotifyAppActive       = @"com.roothide.splitscreenrh.appactive";
NSString *const RHNotifyAppInactive     = @"com.roothide.splitscreenrh.appinactive";
NSString *const RHNotifyCloseFloat      = @"com.roothide.splitscreenrh.closefloat";
NSString *const RHNotifyFloatDismissed  = @"com.roothide.splitscreenrh.floatdismissed";
NSString *const RHNotifySettingsChanged = @"com.roothide.splitscreenrh.settingschanged";

#pragma mark - 私有 API 辅助

// 以正确签名调用 objc_msgSend（避免在 ARC 下产生泄漏警告）
#define RH_MSG_ID(obj, sel)              ((id (*)(id, SEL))objc_msgSend)((obj), (sel))
#define RH_MSG_ID_ARG(obj, sel, a)       ((id (*)(id, SEL, id))objc_msgSend)((obj), (sel), (a))
#define RH_MSG_BOOL(obj, sel)            ((BOOL (*)(id, SEL))objc_msgSend)((obj), (sel))

static id RHClassMsgId(Class cls, NSString *selName) {
    if (!cls) return nil;
    SEL sel = NSSelectorFromString(selName);
    if (![cls respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(cls, sel);
}

static id RHInstanceMsgId(id obj, NSString *selName) {
    if (!obj) return nil;
    SEL sel = NSSelectorFromString(selName);
    if (![obj respondsToSelector:sel]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static BOOL RHInstanceMsgBool(id obj, NSString *selName) {
    if (!obj) return NO;
    SEL sel = NSSelectorFromString(selName);
    if (![obj respondsToSelector:sel]) return NO;
    @try {
        return ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel);
    } @catch (__unused NSException *e) {
        return NO;
    }
}

#pragma mark - Darwin 通知

void RHPostNotify(NSString *name, NSDictionary *userInfo) {
    if (name.length == 0) return;
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(center,
                                         (__bridge CFNotificationName)name,
                                         NULL,
                                         (__bridge CFDictionaryRef)userInfo,
                                         true);
}

#pragma mark - 偏好设置

static NSUserDefaults *RHPrefs(void) {
    static NSUserDefaults *defaults = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defaults = [[NSUserDefaults alloc] initWithSuiteName:RH_PREFS_DOMAIN];
    });
    return defaults;
}

// 读取偏好：NSUserDefaults -> /var/tmp 镜像 -> 直接读 plist（兼容 RootHide 沙盒）
static id RHPrefValue(NSString *key) {
    if (key.length == 0) return nil;
    @try {
        id v = [RHPrefs() objectForKey:key];
        if (v) return v;
    } @catch (__unused NSException *e) {}

    NSDictionary *mirror = [NSDictionary dictionaryWithContentsOfFile:RH_PREFS_MIRROR];
    if (mirror[key]) return mirror[key];

    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:
                           [@"/var/mobile/Library/Preferences" stringByAppendingPathComponent:
                            [RH_PREFS_DOMAIN stringByAppendingPathExtension:@"plist"]]];
    if (plist[key]) return plist[key];

    return nil;
}

static void RHPrefSet(NSString *key, id value) {
    if (key.length == 0) return;
    @try {
        NSUserDefaults *d = RHPrefs();
        if (value) {
            [d setObject:value forKey:key];
        } else {
            [d removeObjectForKey:key];
        }
        [d synchronize];
    } @catch (__unused NSException *e) {}
    // 同步到 /var/tmp 镜像，保证 App 进程可读到最新设置
    NSDictionary *snap = RHPrefsSnapshot();
    if (snap) [snap writeToFile:RH_PREFS_MIRROR atomically:YES];
}

void RHReloadPrefs(void) {
    @try {
        [RHPrefs() synchronize];
    } @catch (__unused NSException *e) {}
}

NSDictionary *RHPrefsSnapshot(void) {
    return @{
        RH_KEY_ENABLED: @(RHIsEnabled()),
        RH_KEY_RADIUS:  @(RHCornerRadius()),
        RH_KEY_WIDTH:   @(RHWidthPercent()),
        RH_KEY_HEIGHT:  @(RHHeightPercent()),
        RH_KEY_EDGE:    @(RHTriggerEdge()),
        RH_KEY_APPS:    RHAddedApps() ?: @[],
    };
}

void RHResetDefaults(void) {
    RHPrefSet(RH_KEY_ENABLED, @(YES));
    RHPrefSet(RH_KEY_RADIUS,  @(RH_DEF_RADIUS));
    RHPrefSet(RH_KEY_WIDTH,   @(RH_DEF_WIDTH));
    RHPrefSet(RH_KEY_HEIGHT,  @(RH_DEF_HEIGHT));
    RHPrefSet(RH_KEY_EDGE,    @(RH_DEF_EDGE));
}

BOOL RHIsEnabled(void) {
    id v = RHPrefValue(RH_KEY_ENABLED);
    return v ? [v boolValue] : YES;
}
void RHSetEnabled(BOOL enabled) { RHPrefSet(RH_KEY_ENABLED, @(enabled)); }

CGFloat RHCornerRadius(void) {
    id v = RHPrefValue(RH_KEY_RADIUS);
    CGFloat r = v ? [v doubleValue] : RH_DEF_RADIUS;
    return (CGFloat)MAX(0.0, MIN(60.0, r));
}
void RHSetCornerRadius(CGFloat radius) { RHPrefSet(RH_KEY_RADIUS, @(radius)); }

CGFloat RHWidthPercent(void) {
    id v = RHPrefValue(RH_KEY_WIDTH);
    CGFloat p = v ? [v doubleValue] : RH_DEF_WIDTH;
    return (CGFloat)MAX(0.3, MIN(0.95, p));
}
void RHSetWidthPercent(CGFloat percent) { RHPrefSet(RH_KEY_WIDTH, @(percent)); }

CGFloat RHHeightPercent(void) {
    id v = RHPrefValue(RH_KEY_HEIGHT);
    CGFloat p = v ? [v doubleValue] : RH_DEF_HEIGHT;
    return (CGFloat)MAX(0.3, MIN(0.95, p));
}
void RHSetHeightPercent(CGFloat percent) { RHPrefSet(RH_KEY_HEIGHT, @(percent)); }

RHEdgeMode RHTriggerEdge(void) {
    id v = RHPrefValue(RH_KEY_EDGE);
    NSInteger m = v ? [v integerValue] : RH_DEF_EDGE;
    if (m < 0 || m > 2) m = RH_DEF_EDGE;
    return (RHEdgeMode)m;
}
void RHSetTriggerEdge(RHEdgeMode mode) { RHPrefSet(RH_KEY_EDGE, @(mode)); }

NSArray<NSString *> *RHAddedApps(void) {
    id v = RHPrefValue(RH_KEY_APPS);
    if (![v isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (id item in (NSArray *)v) {
        if ([item isKindOfClass:[NSString class]] && [item length] > 0) {
            [result addObject:item];
        }
    }
    return result;
}
void RHSetAddedApps(NSArray<NSString *> *apps) {
    RHPrefSet(RH_KEY_APPS, apps ?: @[]);
}

#pragma mark - 环境判断

NSString *RHProcessBundleID(void) {
    static NSString *bid = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bid = [NSBundle mainBundle].bundleIdentifier ?: @"";
    });
    return bid;
}

BOOL RHIsSpringBoard(void) {
    return [RHProcessBundleID() isEqualToString:@"com.apple.springboard"];
}

BOOL RHIsApplicationProcess(void) {
    NSString *bid  = RHProcessBundleID();
    NSString *path = [NSBundle mainBundle].bundlePath ?: @"";
    if (bid.length == 0) return NO;
    if (RHIsSpringBoard()) return NO;
    if ([path hasSuffix:@".appex"]) return NO;          // 扩展进程（键盘等）不处理
    if ([path hasPrefix:@"/Applications/"] ||
        [path hasPrefix:@"/var/containers/Bundle/Application/"] ||
        [path hasPrefix:@"/private/var/containers/Bundle/Application/"]) {
        return YES;
    }
    // RootHide 等路径重映射环境下退化为“存在 UIApplication 即视为应用”
    return (NSClassFromString(@"UIApplication") != nil && [bid containsString:@"."]);
}

UIWindowScene *RHMainWindowScene(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return nil;
    UIWindowScene *fallback = nil;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.screen == [UIScreen mainScreen]) {
            if (ws.activationState == UISceneActivationStateForegroundActive) return ws;
            if (!fallback) fallback = ws;
        }
        if (!fallback) fallback = ws;
    }
    return fallback;
}

CGSize RHScreenSize(void) {
    UIWindowScene *scene = RHMainWindowScene();
    if (scene) {
        CGSize size = scene.coordinateSpace.bounds.size;
        if (size.width > 0 && size.height > 0) return size;
    }
    return [UIScreen mainScreen].bounds.size;
}

BOOL RHIsDeviceLocked(void) {
    id lockManager = RHClassMsgId(NSClassFromString(@"SBLockScreenManager"), @"sharedInstance");
    if (!lockManager) return NO;
    for (NSString *selName in @[@"isLockScreenActive", @"isLockScreenShowing", @"isUILockedActual"]) {
        if ([lockManager respondsToSelector:NSSelectorFromString(selName)]) {
            return RHInstanceMsgBool(lockManager, selName);
        }
    }
    return NO;
}

static NSString *gForegroundBundleID = nil;
NSString *RHForegroundBundleID(void) { return gForegroundBundleID; }
void RHSetForegroundBundleID(NSString *bundleID) {
    gForegroundBundleID = [bundleID copy];
}

NSString *RHBundleIDFromObject(id object) {
    if (!object) return nil;
    if ([object isKindOfClass:[NSString class]]) {
        NSString *s = (NSString *)object;
        if ([s containsString:@"."] && ![s containsString:@" "]) return s;
        return nil;
    }
    for (NSString *selName in @[@"application", @"workspaceEntity", @"entity",
                                @"applicationSceneHandle", @"sceneHandle"]) {
        id v = RHInstanceMsgId(object, selName);
        NSString *r = RHBundleIDFromObject(v);
        if (r.length) return r;
    }
    id bid = RHInstanceMsgId(object, @"bundleIdentifier");
    if ([bid isKindOfClass:[NSString class]]) return bid;
    return nil;
}

// 私有 API 兜底探测前台应用（不同版本方法名不一致，逐个 try）
NSString *RHProbeForegroundBundleID(void) {
    id coordinator = RHClassMsgId(NSClassFromString(@"SBSceneManagerCoordinator"), @"sharedInstance");
    id sceneManager = RHInstanceMsgId(coordinator, @"mainDisplaySceneManager");
    if (!sceneManager) sceneManager = RHInstanceMsgId(coordinator, @"_mainDisplaySceneManager");
    if (sceneManager) {
        for (NSString *selName in @[@"foregroundApplicationSceneHandle",
                                    @"currentForegroundApplicationSceneHandle",
                                    @"_foregroundApplicationSceneHandle",
                                    @"lastForegroundApplicationSceneHandle"]) {
            id handle = RHInstanceMsgId(sceneManager, selName);
            NSString *bid = RHBundleIDFromObject(handle);
            if (bid.length) return bid;
        }
    }
    // 再尝试直接从 SBApplicationController 取前台应用
    id appController = RHClassMsgId(NSClassFromString(@"SBApplicationController"), @"sharedInstance");
    if (appController) {
        for (NSString *selName in @[@"frontmostApplication", @"_frontmostApplication"]) {
            id app = RHInstanceMsgId(appController, selName);
            NSString *bid = RHBundleIDFromObject(app);
            if (bid.length) return bid;
        }
    }
    return nil;
}

#pragma mark - 应用查询 / 启动

BOOL RHAppExists(NSString *bundleID) {
    if (bundleID.length == 0) return NO;
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL sel = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (!proxyClass || ![proxyClass respondsToSelector:sel]) return YES; // 探测失败时不阻塞
    @try {
        id proxy = RH_MSG_ID_ARG(proxyClass, sel, bundleID);
        return proxy != nil;
    } @catch (__unused NSException *e) {
        return YES;
    }
}

BOOL RHLaunchApp(NSString *bundleID) {
    if (bundleID.length == 0) return NO;

    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (wsClass) {
        id workspace = RHClassMsgId(wsClass, @"defaultWorkspace");
        SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
        if (workspace && [workspace respondsToSelector:openSel]) {
            @try {
                BOOL ok = ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, openSel, bundleID);
                if (ok) return YES;
            } @catch (__unused NSException *e) {}
        }
    }

    // 兜底：SpringBoardServices 私有函数
    typedef Boolean (*RHLaunchFn)(CFStringRef, Boolean);
    static RHLaunchFn launchFn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        launchFn = (RHLaunchFn)dlsym(RTLD_DEFAULT, "SBSLaunchApplicationWithIdentifier");
        if (!launchFn) {
            void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
            if (handle) launchFn = (RHLaunchFn)dlsym(handle, "SBSLaunchApplicationWithIdentifier");
        }
    });
    if (launchFn) {
        launchFn((__bridge CFStringRef)bundleID, false);
        return YES;
    }
    return NO;
}

// 让当前 App 主动退到后台（回桌面），用于小窗背后是桌面时“关闭小窗”
void RHSuspendSelf(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return;
    for (NSString *selName in @[@"suspend", @"_suspend"]) {
        SEL sel = NSSelectorFromString(selName);
        if ([app respondsToSelector:sel]) {
            @try {
                ((void (*)(id, SEL))objc_msgSend)(app, sel);
                return;
            } @catch (__unused NSException *e) {}
        }
    }
}

#pragma mark - 截图 / 图标

UIImage *RHCreateScreenImage(void) {
    typedef UIImage *(*RHScreenImageFn)(void);
    static RHScreenImageFn fn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (RHScreenImageFn)dlsym(RTLD_DEFAULT, "_UICreateScreenUIImage");
        if (!fn) {
            void *handle = dlopen("/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore", RTLD_LAZY);
            if (handle) fn = (RHScreenImageFn)dlsym(handle, "_UICreateScreenUIImage");
        }
    });
    if (!fn) return nil;
    @try {
        return fn();
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static NSCache *RHIconCache(void) {
    static NSCache *cache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 200;
    });
    return cache;
}

UIImage *RHIconForBundle(NSString *bundleID, CGFloat size) {
    if (bundleID.length == 0) return nil;
    NSString *key = [NSString stringWithFormat:@"%@-%.0f", bundleID, size];
    UIImage *cached = [RHIconCache() objectForKey:key];
    if (cached) return cached;

    UIImage *icon = nil;

    // 途径 1：UIKit 私有 API（性能最好，直接返回渲染好的图标）
    SEL iconSel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if ([[UIImage class] respondsToSelector:iconSel]) {
        @try {
            typedef UIImage *(*RHIconFn)(id, SEL, NSString *, NSInteger, CGFloat);
            icon = ((RHIconFn)objc_msgSend)([UIImage class], iconSel, bundleID, 0,
                                            [UIScreen mainScreen].scale);
        } @catch (__unused NSException *e) {}
    }

    // 途径 2：LSApplicationProxy 图标数据
    if (!icon) {
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        SEL proxySel = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if (proxyClass && [proxyClass respondsToSelector:proxySel]) {
            @try {
                id proxy = RH_MSG_ID_ARG(proxyClass, proxySel, bundleID);
                SEL dataSel = NSSelectorFromString(@"iconDataForVariant:");
                if (proxy && [proxy respondsToSelector:dataSel]) {
                    typedef NSData *(*RHDataFn)(id, SEL, NSInteger);
                    NSData *data = ((RHDataFn)objc_msgSend)(proxy, dataSel, 2);
                    if ([data isKindOfClass:[NSData class]] && data.length > 0) {
                        icon = [UIImage imageWithData:data];
                    }
                }
            } @catch (__unused NSException *e) {}
        }
    }

    if (icon) [RHIconCache() setObject:icon forKey:key];
    return icon;
}

NSString *RHAppNameForBundle(NSString *bundleID) {
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL sel = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (!proxyClass || ![proxyClass respondsToSelector:sel]) return bundleID;
    @try {
        id proxy = RH_MSG_ID_ARG(proxyClass, sel, bundleID);
        for (NSString *selName in @[@"localizedName", @"itemName", @"bundleIdentifier"]) {
            id v = RHInstanceMsgId(proxy, selName);
            if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return v;
        }
    } @catch (__unused NSException *e) {}
    return bundleID ?: @"";
}

NSString *RHContainerPathForBundle(NSString *bundleID) {
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL sel = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (!proxyClass || ![proxyClass respondsToSelector:sel] || bundleID.length == 0) return nil;
    @try {
        id proxy = RH_MSG_ID_ARG(proxyClass, sel, bundleID);
        id url = RHInstanceMsgId(proxy, @"dataContainerURL");
        if ([url isKindOfClass:[NSURL class]]) {
            NSString *path = [(NSURL *)url path];
            if (path.length) return path;
        }
        // 兜底：从容器路径构造
        id containerURL = RHInstanceMsgId(proxy, @"containerURL");
        if ([containerURL isKindOfClass:[NSURL class]]) return [(NSURL *)containerURL path];
    } @catch (__unused NSException *e) {}
    return nil;
}

NSArray<NSDictionary *> *RHInstalledApps(BOOL includeSystem) {
    NSMutableArray *result = [NSMutableArray array];
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = RHClassMsgId(wsClass, @"defaultWorkspace");
    SEL allSel = NSSelectorFromString(@"allInstalledApplications");
    if (!workspace || ![workspace respondsToSelector:allSel]) return result;

    @try {
        NSArray *proxies = RH_MSG_ID(workspace, allSel);
        for (id proxy in proxies) {
            @try {
                NSString *bid = RHInstanceMsgId(proxy, @"bundleIdentifier");
                if (![bid isKindOfClass:[NSString class]] || bid.length == 0) continue;
                if ([bid isEqualToString:@"com.apple.springboard"]) continue;
                if ([bid hasPrefix:@"com.apple.WebKit"]) continue;
                if (RHInstanceMsgBool(proxy, @"isHidden")) continue;
                if (RHInstanceMsgBool(proxy, @"isPlaceholder")) continue;

                BOOL isSystem = [bid hasPrefix:@"com.apple."];
                id type = RHInstanceMsgId(proxy, @"applicationType");
                if ([type isKindOfClass:[NSString class]]) {
                    isSystem = [(NSString *)type isEqualToString:@"System"];
                } else if ([type isKindOfClass:[NSNumber class]]) {
                    isSystem = ([(NSNumber *)type integerValue] != 1); // 1 = User
                }
                if (isSystem && !includeSystem) continue;

                NSString *name = RHAppNameForBundle(bid) ?: bid;
                [result addObject:@{ @"bundleID": bid,
                                     @"name": name,
                                     @"system": @(isSystem) }];
            } @catch (__unused NSException *e) {}
        }
    } @catch (__unused NSException *e) {}

    [result sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return result;
}

#pragma mark - 小窗几何

CGRect RHDefaultFloatRect(void) {
    CGSize screen = RHScreenSize();
    CGFloat w = floor(screen.width  * RHWidthPercent());
    CGFloat h = floor(screen.height * RHHeightPercent());
    CGFloat x = floor(screen.width - w - 14.0);
    CGFloat y = floor(screen.height * 0.16);
    return CGRectMake(x, y, w, h);
}

CGRect RHClampRectToScreen(CGRect rect) {
    CGSize screen = RHScreenSize();
    CGFloat minW = 150.0, minH = 200.0;
    rect.size.width  = MAX(minW, MIN(rect.size.width,  screen.width));
    rect.size.height = MAX(minH, MIN(rect.size.height, screen.height));
    rect.origin.x = MAX(0.0, MIN(rect.origin.x, screen.width  - rect.size.width));
    rect.origin.y = MAX(0.0, MIN(rect.origin.y, screen.height - rect.size.height));
    return rect;
}

#pragma mark - RHFloatState

@implementation RHFloatState {
    NSString *_snapshotPath;   // 运行时记录快照实际路径
}

+ (NSString *)selfContainerStatePath {
    if (RHIsSpringBoard()) return nil;
    NSString *home = NSHomeDirectory();
    if (home.length == 0) return nil;
    return [[home stringByAppendingPathComponent:@"Library/Caches"]
            stringByAppendingPathComponent:RH_STATE_FILE_NAME];
}

+ (NSString *)selfContainerSnapPath {
    if (RHIsSpringBoard()) return nil;
    NSString *home = NSHomeDirectory();
    if (home.length == 0) return nil;
    return [[home stringByAppendingPathComponent:@"Library/Caches"]
            stringByAppendingPathComponent:RH_SNAP_FILE_NAME];
}

+ (instancetype)current {
    NSDictionary *best = nil;
    NSTimeInterval bestTime = -1;

    // 1) /var/tmp（SpringBoard 优先写入）
    NSDictionary *tmp = [NSDictionary dictionaryWithContentsOfFile:RH_STATE_TMP_PATH];
    if ([tmp isKindOfClass:[NSDictionary class]]) {
        best = tmp;
        bestTime = [tmp[@"timestamp"] doubleValue];
    }
    // 2) 自身容器（RootHide 等环境兜底）
    NSString *selfPath = [self selfContainerStatePath];
    NSDictionary *own = selfPath ? [NSDictionary dictionaryWithContentsOfFile:selfPath] : nil;
    if ([own isKindOfClass:[NSDictionary class]]) {
        NSTimeInterval t = [own[@"timestamp"] doubleValue];
        if (!best || t > bestTime) { best = own; bestTime = t; }
    }
    if (!best) return nil;

    RHFloatState *state = [[RHFloatState alloc] init];
    state.floating     = [best[@"floating"] boolValue];
    state.bundleID     = best[@"bundleID"];
    state.homeBundleID = [best[@"homeBundleID"] isKindOfClass:[NSString class]] ? best[@"homeBundleID"] : nil;
    state.radius       = [best[@"radius"] doubleValue];
    state.timestamp    = [best[@"timestamp"] doubleValue];
    NSDictionary *rectDict = best[@"rect"];
    if ([rectDict isKindOfClass:[NSDictionary class]]) {
        state.rect = CGRectMake([rectDict[@"x"] doubleValue], [rectDict[@"y"] doubleValue],
                                [rectDict[@"w"] doubleValue], [rectDict[@"h"] doubleValue]);
    }
    NSString *snap = best[@"snapshotPath"];
    if ([snap isKindOfClass:[NSString class]]) [state setSnapshotPath:snap];
    return state;
}

+ (instancetype)currentForSelf {
    RHFloatState *state = [self current];
    if (state && [state isForSelf]) return state;
    return nil;
}

- (BOOL)isForSelf {
    if (!self.floating || self.bundleID.length == 0) return NO;
    return [self.bundleID isEqualToString:RHProcessBundleID()];
}

- (NSDictionary *)dictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"floating"]    = @(self.floating);
    dict[@"bundleID"]    = self.bundleID ?: @"";
    if (self.homeBundleID) dict[@"homeBundleID"] = self.homeBundleID;
    dict[@"radius"]      = @(self.radius > 0 ? self.radius : RH_DEF_RADIUS);
    dict[@"timestamp"]   = @([[NSDate date] timeIntervalSince1970]);
    if (!CGRectIsEmpty(self.rect)) {
        dict[@"rect"] = @{ @"x": @(self.rect.origin.x), @"y": @(self.rect.origin.y),
                           @"w": @(self.rect.size.width), @"h": @(self.rect.size.height) };
    }
    return dict;
}

- (void)save {
    if (self.bundleID.length == 0) return;
    self.timestamp = [[NSDate date] timeIntervalSince1970];
    NSMutableDictionary *dict = [[self dictionary] mutableCopy];
    dict[@"timestamp"] = @(self.timestamp);
    if (_snapshotPath.length) dict[@"snapshotPath"] = _snapshotPath;

    [dict writeToFile:RH_STATE_TMP_PATH atomically:YES];

    NSString *container = RHContainerPathForBundle(self.bundleID);
    if (container.length) {
        NSString *dir = [container stringByAppendingPathComponent:@"Library/Caches"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [dict writeToFile:[dir stringByAppendingPathComponent:RH_STATE_FILE_NAME] atomically:YES];
    }
}

- (void)clear {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"floating"]  = @(NO);
    dict[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    [dict writeToFile:RH_STATE_TMP_PATH atomically:YES];

    if (self.bundleID.length) {
        NSString *container = RHContainerPathForBundle(self.bundleID);
        if (container.length) {
            NSString *path = [[container stringByAppendingPathComponent:@"Library/Caches"]
                              stringByAppendingPathComponent:RH_STATE_FILE_NAME];
            [dict writeToFile:path atomically:YES];
        }
    }
    _snapshotPath = nil;
}

- (void)writeSnapshot:(UIImage *)image {
    if (!image) return;
    NSData *png = UIImagePNGRepresentation(image);
    if (png.length == 0) return;

    _snapshotPath = RH_SNAP_TMP_PATH;
    [png writeToFile:RH_SNAP_TMP_PATH atomically:YES];

    if (self.bundleID.length) {
        NSString *container = RHContainerPathForBundle(self.bundleID);
        if (container.length) {
            NSString *dir = [container stringByAppendingPathComponent:@"Library/Caches"];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                      withIntermediateDirectories:YES attributes:nil error:NULL];
            NSString *path = [dir stringByAppendingPathComponent:RH_SNAP_FILE_NAME];
            if ([png writeToFile:path atomically:YES]) _snapshotPath = path;
        }
    }
}

- (UIImage *)loadSnapshot {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    if (_snapshotPath.length) [paths addObject:_snapshotPath];
    NSString *own = [RHFloatState selfContainerSnapPath];
    if (own.length) [paths addObject:own];
    [paths addObject:RH_SNAP_TMP_PATH];
    for (NSString *path in paths) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data.length == 0) continue;
        UIImage *image = [UIImage imageWithData:data];
        if (image) return image;
    }
    return nil;
}

- (void)setSnapshotPath:(NSString *)path {
    _snapshotPath = [path copy];
}

@end