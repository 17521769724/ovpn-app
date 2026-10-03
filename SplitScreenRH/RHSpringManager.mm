//
//  RHSpringManager.mm
//  SplitScreenRH —— SpringBoard 侧核心：边缘手势、表盘面板调度、小窗会话管理
//

#import "RHInternal.h"
#import <objc/message.h>

#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static const CGFloat kRHEdgeStripWidth   = 10.0;      // 边缘热区宽度（pt）
static const CGFloat kRHEdgeTriggerDist  = 18.0;      // 触发所需横向滑动距离（pt）
static const CGFloat kRHEdgeWindowLevel  = 10000100;  // 边缘窗口层级（高于键盘/状态栏）
static const CGFloat kRHOverlayLevel     = 10000200;  // 面板/设置窗口层级

// Darwin 通知回调（跨进程）
static void RHDarwinNotifyCallback(CFNotificationCenterRef center,
                                   void *observer,
                                   CFNotificationName name,
                                   const void *object,
                                   CFDictionaryRef userInfo);

@interface RHSpringManager ()
@property (nonatomic, strong) NSMutableArray<UIWindow *> *edgeWindows;
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL edgeTriggered;
@property (nonatomic, assign) NSInteger sceneRetries;
@property (nonatomic, assign) BOOL panelVisible;
- (void)handleDarwinNotification:(NSString *)name userInfo:(NSDictionary *)userInfo;
@end

@implementation RHSpringManager

+ (instancetype)shared {
    static RHSpringManager *manager = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        manager = [[RHSpringManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _edgeWindows = [NSMutableArray array];
    }
    return self;
}

#pragma mark - 启动

- (void)start {
    if (self.started) return;
    self.started = YES;

    // 跨进程通知：App 上报前台状态 / 小窗关闭 / 设置变更
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    NSArray<NSString *> *notifications = @[RHNotifyAppActive, RHNotifyAppInactive,
                                           RHNotifyCloseFloat, RHNotifyFloatDismissed,
                                           RHNotifySettingsChanged];
    for (NSString *name in notifications) {
        CFNotificationCenterAddObserver(center,
                                        (__bridge const void *)self,
                                        RHDarwinNotifyCallback,
                                        (__bridge CFStringRef)name,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(orientationChanged)
                                                 name:UIApplicationDidChangeStatusBarOrientationNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(orientationChanged)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(settingsChangedInternal)
                                                 name:@"RHSettingsChangedInternal"
                                               object:nil];

    [self setupWhenReady];
}

// 等待 SpringBoard 的窗口场景就绪后再创建边缘手势窗口
- (void)setupWhenReady {
    if (RHMainWindowScene()) {
        self.sceneRetries = 0;
        [self reloadEdgeWindows];
        return;
    }
    if (self.sceneRetries++ > 60) return;   // 约 15 秒后放弃
    __weak typeof(self) wself = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [wself setupWhenReady];
    });
}

- (void)settingsChangedInternal {
    [self reloadEdgeWindows];
}

#pragma mark - 边缘手势

- (void)reloadEdgeWindows {
    UIWindowScene *scene = RHMainWindowScene();
    if (!scene) return;

    for (UIWindow *window in self.edgeWindows) {
        window.hidden = YES;
        window.rootViewController = nil;
    }
    [self.edgeWindows removeAllObjects];

    if (!RHIsEnabled()) {
        [self dismissPanel];
        return;
    }

    CGSize screen = scene.coordinateSpace.bounds.size;
    RHEdgeMode mode = RHTriggerEdge();
    NSMutableArray<NSNumber *> *sides = [NSMutableArray array];
    if (mode == RHEdgeModeBoth || mode == RHEdgeModeLeft)  [sides addObject:@(1)];
    if (mode == RHEdgeModeBoth || mode == RHEdgeModeRight) [sides addObject:@(2)];

    for (NSNumber *side in sides) {
        BOOL isLeft = side.integerValue == 1;
        UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
        window.frame = CGRectMake(isLeft ? 0 : screen.width - kRHEdgeStripWidth,
                                  0, kRHEdgeStripWidth, screen.height);
        window.windowLevel = kRHEdgeWindowLevel;
        window.backgroundColor = [UIColor clearColor];
        window.hidden = NO;

        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.backgroundColor = [UIColor clearColor];
        vc.view.tag = isLeft ? 1 : 2;
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                             action:@selector(handleEdgePan:)];
        [vc.view addGestureRecognizer:pan];
        window.rootViewController = vc;

        [self.edgeWindows addObject:window];
    }
}

- (void)handleEdgePan:(UIPanGestureRecognizer *)gesture {
    if (!RHIsEnabled()) return;
    UIView *strip = gesture.view;
    BOOL isLeft = (strip.tag == 1);

    if (gesture.state == UIGestureRecognizerStateChanged) {
        if (self.edgeTriggered) return;
        CGPoint translation = [gesture translationInView:strip.window];
        BOOL horizontal = fabs(translation.x) > fabs(translation.y) * 1.4;
        CGFloat inward = isLeft ? translation.x : -translation.x;
        if (horizontal && inward > kRHEdgeTriggerDist) {
            self.edgeTriggered = YES;
            [self presentPanel];
        }
    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled ||
               gesture.state == UIGestureRecognizerStateFailed) {
        self.edgeTriggered = NO;
    }
}

- (void)orientationChanged {
    UIWindowScene *scene = RHMainWindowScene();
    if (!scene) return;
    CGSize screen = scene.coordinateSpace.bounds.size;
    for (UIWindow *window in self.edgeWindows) {
        BOOL isLeft = (window.rootViewController.view.tag == 1);
        window.frame = CGRectMake(isLeft ? 0 : screen.width - kRHEdgeStripWidth,
                                  0, kRHEdgeStripWidth, screen.height);
    }
    if (self.overlayWindow) {
        self.overlayWindow.frame = CGRectMake(0, 0, screen.width, screen.height);
    }
}

#pragma mark - 面板

- (void)presentPanel {
    if (self.panelVisible) return;
    if (!RHIsEnabled() || RHIsDeviceLocked()) return;

    UIWindowScene *scene = RHMainWindowScene();
    if (!scene) return;

    RHWatchPanelController *panel = [[RHWatchPanelController alloc] init];
    panel.apps = RHAddedApps();

    __weak typeof(self) wself = self;
    panel.onSelect = ^(NSString *bundleID) {
        [wself openAppInFloating:bundleID];
    };
    panel.onSettings = ^{
        [wself presentSettings];
    };
    panel.onDismiss = ^{
        [wself dismissPanel];
    };

    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    window.frame = CGRectMake(0, 0, scene.coordinateSpace.bounds.size.width,
                              scene.coordinateSpace.bounds.size.height);
    window.windowLevel = kRHOverlayLevel;
    window.backgroundColor = [UIColor clearColor];
    window.rootViewController = panel;
    window.hidden = NO;
    self.overlayWindow = window;
    self.panelVisible = YES;

    [panel animateIn];
}

- (void)dismissPanel {
    if (!self.panelVisible || !self.overlayWindow) return;
    UIWindow *window = self.overlayWindow;
    self.panelVisible = NO;
    self.overlayWindow = nil;

    id rootVC = window.rootViewController;
    if ([rootVC isKindOfClass:[RHWatchPanelController class]]) {
        [(RHWatchPanelController *)rootVC animateOutWithCompletion:^{
            window.hidden = YES;
            window.rootViewController = nil;
        }];
    } else {
        window.hidden = YES;
        window.rootViewController = nil;
    }
}

- (void)presentSettings {
    UIWindowScene *scene = RHMainWindowScene();
    if (!scene) return;

    self.panelVisible = NO;

    UIWindow *window = self.overlayWindow;
    if (!window) {
        window = [[UIWindow alloc] initWithWindowScene:scene];
        window.frame = CGRectMake(0, 0, scene.coordinateSpace.bounds.size.width,
                                  scene.coordinateSpace.bounds.size.height);
        window.windowLevel = kRHOverlayLevel;
        window.backgroundColor = [UIColor clearColor];
        self.overlayWindow = window;
    }
    window.hidden = NO;

    RHSettingsRootVC *root = [[RHSettingsRootVC alloc] init];
    __weak typeof(self) wself = self;
    root.onClose = ^{
        [wself closeOverlayWindow];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    window.rootViewController = nav;
}

- (void)closeOverlayWindow {
    UIWindow *window = self.overlayWindow;
    self.overlayWindow = nil;
    self.panelVisible = NO;
    window.hidden = YES;
    window.rootViewController = nil;
}

#pragma mark - 打开 / 关闭小窗

// 打开应用：先截屏、写入会话状态，再交给系统启动目标应用；
// 目标应用内的注入代码读取状态后自动变成小窗，原应用保持后台不冲突。
- (void)openAppInFloating:(NSString *)bundleID {
    if (bundleID.length == 0) return;

    NSString *foreground = RHForegroundBundleID();
    if (foreground.length == 0) foreground = RHProbeForegroundBundleID();
    if ([foreground isEqualToString:bundleID]) {   // 已经在前台，无需分屏
        [self dismissPanel];
        return;
    }
    if (!RHAppExists(bundleID)) {
        [self dismissPanel];
        return;
    }

    UIImage *snapshot = RHCreateScreenImage();

    RHFloatState *state = [[RHFloatState alloc] init];
    state.floating     = YES;
    state.bundleID     = bundleID;
    state.homeBundleID = (foreground.length && ![foreground isEqualToString:bundleID]) ? foreground : nil;
    state.radius       = RHCornerRadius();
    state.rect         = RHDefaultFloatRect();

    [self dismissPanel];

    __weak typeof(self) wself = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [state save];
        if (snapshot) [state writeSnapshot:snapshot];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!RHLaunchApp(bundleID)) {
                [state clear];
            }
            (void)wself;
        });
    });
}

#pragma mark - 跨进程通知处理

- (void)handleDarwinNotification:(NSString *)name userInfo:(NSDictionary *)userInfo {
    if ([name isEqualToString:RHNotifyAppActive]) {
        NSString *bundleID = userInfo[@"bundle"];
        if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) return;
        RHSetForegroundBundleID(bundleID);

        // 小窗应用尚未就绪时，另一个应用抢占了前台：清掉过期会话
        RHFloatState *state = [RHFloatState current];
        if (state.floating && state.bundleID.length && ![state.bundleID isEqualToString:bundleID]) {
            [state clear];
        }
    } else if ([name isEqualToString:RHNotifyAppInactive]) {
        NSString *bundleID = userInfo[@"bundle"];
        if (![bundleID isKindOfClass:[NSString class]]) return;
        if ([RHForegroundBundleID() isEqualToString:bundleID]) RHSetForegroundBundleID(nil);
    } else if ([name isEqualToString:RHNotifyCloseFloat]) {
        // 小窗已关闭：需要把原应用拉回前台（或停留在桌面）
        NSString *home = userInfo[@"home"];
        RHFloatState *state = [RHFloatState current];
        [state clear];
        RHSetForegroundBundleID(nil);
        if ([home isKindOfClass:[NSString class]] && home.length > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                RHLaunchApp(home);
            });
        }
    } else if ([name isEqualToString:RHNotifyFloatDismissed]) {
        RHFloatState *state = [RHFloatState current];
        if (state.floating) [state clear];
    } else if ([name isEqualToString:RHNotifySettingsChanged]) {
        [self reloadEdgeWindows];
    }
}

static void RHDarwinNotifyCallback(CFNotificationCenterRef center,
                                   void *observer,
                                   CFNotificationName name,
                                   const void *object,
                                   CFDictionaryRef userInfo) {
    NSString *notificationName = (__bridge NSString *)name;
    NSDictionary *info = (__bridge NSDictionary *)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[RHSpringManager shared] handleDarwinNotification:notificationName userInfo:info];
    });
}

@end