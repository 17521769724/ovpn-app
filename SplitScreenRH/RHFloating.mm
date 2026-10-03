//
//  RHFloating.mm
//  SplitScreenRH —— 目标 App 内的小窗控制器
//
//  工作原理（与前台应用互不冲突）：
//    1. 触发分屏前，SpringBoard 已对当前屏幕截图并写入会话状态；
//    2. 目标 App 启动/唤起后，本控制器把 App 主窗口缩小并圆角化为“小窗”；
//    3. 小窗之下新建一个背景窗口显示原应用快照（原应用仅被挂起，状态完整保留）；
//    4. 边缘拖动缩放、标题栏拖动移动、点击小窗下方/外部关闭；
//    5. 关闭后通过 Darwin 通知让 SpringBoard 把原应用拉回前台，小窗应用保留在后台。
//

#import "RHInternal.h"
#import <QuartzCore/QuartzCore.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// 拖拽类型
typedef NS_ENUM(NSInteger, RHDragMode) {
    RHDragModeNone = 0,
    RHDragModeMove,
    RHDragModeResizeLeft,
    RHDragModeResizeRight,
    RHDragModeResizeTop,
    RHDragModeResizeBottom,
    RHDragModeResizeTopLeft,
    RHDragModeResizeTopRight,
    RHDragModeResizeBottomLeft,
    RHDragModeResizeBottomRight,
};

static const CGFloat kRHHandleThickness = 16.0;   // 边缘缩放手柄厚度
static const CGFloat kRHCornerSize      = 32.0;   // 角落缩放手柄尺寸
static const CGFloat kRHTopBarHeight    = 22.0;   // 顶部拖动条高度
static const CGFloat kRHMinWidth        = 150.0;
static const CGFloat kRHMinHeight       = 200.0;

// 设置变更回调（跨进程 Darwin 通知）
static void RHFloatSettingsCallback(CFNotificationCenterRef center,
                                    void *observer,
                                    CFNotificationName name,
                                    const void *object,
                                    CFDictionaryRef userInfo);

@interface RHFloatingController ()
@property (nonatomic, assign) BOOL active;

@property (nonatomic, strong) UIWindow *appWindow;
@property (nonatomic, assign) CGRect savedFrame;
@property (nonatomic, assign) BOOL savedClips;
@property (nonatomic, assign) CGFloat savedRadius;
@property (nonatomic, assign) CGFloat savedBorderWidth;
@property (nonatomic, assign) CGFloat savedLevel;

@property (nonatomic, strong) UIWindow *backdropWindow;
@property (nonatomic, strong) UIWindow *controlWindow;
@property (nonatomic, strong) UIView *controlRoot;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIView *closePill;
@property (nonatomic, strong) NSMutableArray<UIView *> *handles;

@property (nonatomic, assign) CGRect floatRect;
@property (nonatomic, assign) CGFloat radius;
@property (nonatomic, assign) NSInteger activateRetries;
@property (nonatomic, assign) BOOL activating;   // 防止重复进入小窗流程

@property (nonatomic, assign) RHDragMode dragMode;
@property (nonatomic, assign) CGRect dragStartRect;
- (void)handleSettingsChanged;
@end

// 设置变更回调（跨进程 Darwin 通知）
static void RHFloatSettingsCallback(CFNotificationCenterRef center,
                                    void *observer,
                                    CFNotificationName name,
                                    const void *object,
                                    CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[RHFloatingController shared] handleSettingsChanged];
    });
}

// 触摸穿透容器：只有落在手柄/按钮上的触摸才被拦截，
// 其余触摸直接透传给下方的小窗应用，保证应用可正常操作。
@interface RHHitPassView : UIView
@end

@implementation RHHitPassView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}
@end

@implementation RHFloatingController

+ (instancetype)shared {
    static RHFloatingController *controller = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        controller = [[RHFloatingController alloc] init];
    });
    return controller;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _handles = [NSMutableArray array];
    }
    return self;
}

#pragma mark - 监听生命周期

- (void)startMonitoring {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(appDidBecomeActive)
                   name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(appDidEnterBackground)
                   name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(screenGeometryChanged)
                   name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    [center addObserver:self selector:@selector(screenGeometryChanged)
                   name:UIDeviceOrientationDidChangeNotification object:nil];
    // 冷启动时主窗口可能晚于 didBecomeActive 出现，用窗口通知补齐
    [center addObserver:self selector:@selector(windowAppeared)
                   name:UIWindowDidBecomeKeyNotification object:nil];
    [center addObserver:self selector:@selector(windowAppeared)
                   name:UIWindowDidBecomeVisibleNotification object:nil];

    // 监听设置变更（总开关关闭时立即回收小窗）
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)self,
                                    RHFloatSettingsCallback,
                                    (__bridge CFStringRef)RHNotifySettingsChanged,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    UIApplicationState appState = [UIApplication sharedApplication].applicationState;
    [self reportActive:(appState == UIApplicationStateActive)];
}

- (void)handleSettingsChanged {
    // 总开关被关闭：回收小窗，应用恢复全屏并留在后台
    if (!RHIsEnabled() && self.active) {
        RHFloatState *state = [RHFloatState current];
        if (state.floating) {
            state.floating = NO;
            [state save];
        }
        [self dismissLocal];
    }
}

- (void)windowAppeared {
    if (self.active || self.activating) return;
    [self activateIfNeededFromState];
}

- (void)appDidBecomeActive {
    __weak typeof(self) wself = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [wself reconcile];
        [wself reportActive:YES];
    });
}

- (void)appDidEnterBackground {
    [self reportActive:NO];
    if (!self.active) return;

    RHFloatState *state = [RHFloatState current];
    BOOL stillOurs = state.floating && [state.bundleID isEqualToString:RHProcessBundleID()];
    [self dismissLocal];
    if (stillOurs) {
        // 用户用 Home 手势等方式离开了小窗：清理会话，保留应用后台
        [state clear];
        RHPostNotify(RHNotifyFloatDismissed, nil);
    }
}

- (void)screenGeometryChanged {
    if (!self.active) return;
    CGRect rect = RHClampRectToScreen(self.floatRect);
    if (!CGRectEqualToRect(rect, self.floatRect)) {
        self.floatRect = rect;
        [self applyFloatGeometry];
    }
}

// 上报前台状态（写入容器文件，供 SpringBoard 读取），并发出信号
- (void)reportActive:(BOOL)active {
    NSString *bundleID = RHProcessBundleID();
    if (bundleID.length == 0) return;
    RHReportForegroundState(bundleID, active);
    RHPostNotify(active ? RHNotifyAppActive : RHNotifyAppInactive, nil);
}

#pragma mark - 状态同步（进入 / 退出小窗）

- (void)reconcile {
    RHFloatState *state = [RHFloatState current];
    BOOL shouldFloat = state.floating && state.bundleID.length > 0 &&
                       [state.bundleID isEqualToString:RHProcessBundleID()];

    if (shouldFloat && !self.active) {
        [self activateIfNeededFromState];
    } else if (shouldFloat && self.active) {
        // 已经在小窗模式：重新套用几何，防止 App 自行改回全屏
        [self applyFloatGeometry];
    } else if (!shouldFloat && self.active) {
        [self dismissLocal];
    }
}

- (void)activateIfNeededFromState {
    if (self.active || self.activating) return;
    RHFloatState *state = [RHFloatState current];
    if (!state.floating || ![state.bundleID isEqualToString:RHProcessBundleID()]) return;
    self.activating = YES;
    [self activateWithState:state];
}

- (void)activateWithState:(RHFloatState *)state {
    if (self.active) {          // 已完成激活，避免重复创建窗口
        self.activating = NO;
        return;
    }
    self.activating = YES;
    UIWindow *mainWindow = [self findAppMainWindow];
    if (!mainWindow || !mainWindow.windowScene) {
        if (self.activateRetries++ < 16) {
            __weak typeof(self) wself = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (!wself.active) [wself activateWithState:state];
            });
        } else {
            self.activating = NO;
            self.activateRetries = 0;
        }
        return;
    }
    self.activateRetries = 0;

    self.appWindow = mainWindow;
    self.savedFrame = mainWindow.frame;
    self.savedClips = mainWindow.clipsToBounds;
    self.savedRadius = mainWindow.layer.cornerRadius;
    self.savedBorderWidth = mainWindow.layer.borderWidth;
    self.savedLevel = mainWindow.windowLevel;

    self.radius = state.radius > 0 ? state.radius : RH_DEF_RADIUS;
    CGRect rect = state.rect;
    if (CGRectIsEmpty(rect)) rect = RHDefaultFloatRect();
    self.floatRect = RHClampRectToScreen(rect);

    UIWindowScene *scene = mainWindow.windowScene;
    CGSize screen = scene.coordinateSpace.bounds.size;
    CGRect full = CGRectMake(0, 0, screen.width, screen.height);

    // 抬高应用主窗口层级：背景窗 = 原层级（一定在小窗之下），控制窗 = 原层级 +2
    mainWindow.windowLevel = self.savedLevel + 1.0;

    // ---- 背景窗口：显示原应用快照，位于小窗之下 ----
    self.backdropWindow = [[UIWindow alloc] initWithWindowScene:scene];
    self.backdropWindow.frame = full;
    self.backdropWindow.windowLevel = self.savedLevel;
    self.backdropWindow.backgroundColor = [UIColor blackColor];

    UIView *backdropRoot = [[UIView alloc] initWithFrame:full];
    backdropRoot.backgroundColor = [UIColor blackColor];
    backdropRoot.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    UIImage *snapshot = [state loadSnapshot];
    if (snapshot) {
        UIImageView *imageView = [[UIImageView alloc] initWithImage:snapshot];
        imageView.frame = backdropRoot.bounds;
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.clipsToBounds = YES;
        imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [backdropRoot addSubview:imageView];
    } else {
        backdropRoot.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    }

    UIView *dimView = [[UIView alloc] initWithFrame:backdropRoot.bounds];
    dimView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.40];
    dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [backdropRoot addSubview:dimView];

    // 点击小窗之外的任意位置 = 关闭小窗（保留应用后台）
    UITapGestureRecognizer *backdropTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                action:@selector(closeFloatingAnimated)];
    [backdropRoot addGestureRecognizer:backdropTap];

    UIViewController *backdropVC = [[UIViewController alloc] init];
    backdropVC.view.backgroundColor = [UIColor clearColor];
    [backdropVC.view addSubview:backdropRoot];
    self.backdropWindow.rootViewController = backdropVC;
    self.backdropWindow.hidden = NO;

    // ---- 控制窗口：拖动条 / 缩放手柄 / 关闭按钮 ----
    self.controlWindow = [[UIWindow alloc] initWithWindowScene:scene];
    self.controlWindow.frame = full;
    self.controlWindow.windowLevel = self.savedLevel + 2.0;
    self.controlWindow.backgroundColor = [UIColor clearColor];

    UIViewController *controlVC = [[UIViewController alloc] init];
    controlVC.view = [[RHHitPassView alloc] initWithFrame:full];
    controlVC.view.backgroundColor = [UIColor clearColor];
    self.controlRoot = controlVC.view;
    [self buildControls];
    self.controlWindow.rootViewController = controlVC;
    self.controlWindow.hidden = NO;

    // ---- 应用主窗口 -> 小窗 ----
    self.active = YES;
    [self applyFloatGeometry];

    // 兜底：部分 App 启动瞬间会重设窗口 frame，稍后二次校正
    __weak typeof(self) wself = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (wself.active) [wself applyFloatGeometry];
    });
}

#pragma mark - 构建控件

- (UIView *)handleViewWithMode:(RHDragMode)mode {
    UIView *view = [[UIView alloc] init];
    view.backgroundColor = [UIColor clearColor];
    view.tag = mode;
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(handlePan:)];
    [view addGestureRecognizer:pan];
    return view;
}

- (void)buildControls {
    for (UIView *view in self.handles) [view removeFromSuperview];
    [self.handles removeAllObjects];
    [self.topBar removeFromSuperview];
    [self.closePill removeFromSuperview];

    // 顶部拖动条（移动小窗）
    self.topBar = [[UIView alloc] init];
    self.topBar.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    self.topBar.tag = RHDragModeMove;
    UIPanGestureRecognizer *movePan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                             action:@selector(handlePan:)];
    [self.topBar addGestureRecognizer:movePan];
    UIView *grabber = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 34, 4)];
    grabber.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.35];
    grabber.layer.cornerRadius = 2.0;
    grabber.userInteractionEnabled = NO;
    grabber.tag = 999;
    [self.topBar addSubview:grabber];
    [self.controlRoot addSubview:self.topBar];

    // 缩放手柄：四边 + 四角
    NSArray<NSNumber *> *modes = @[@(RHDragModeResizeLeft), @(RHDragModeResizeRight),
                                   @(RHDragModeResizeTop), @(RHDragModeResizeBottom),
                                   @(RHDragModeResizeTopLeft), @(RHDragModeResizeTopRight),
                                   @(RHDragModeResizeBottomLeft), @(RHDragModeResizeBottomRight)];
    for (NSNumber *mode in modes) {
        UIView *handle = [self handleViewWithMode:(RHDragMode)mode.integerValue];
        [self.controlRoot addSubview:handle];
        [self.handles addObject:handle];
    }

    // 小窗下方“关闭”胶囊：点击关闭并保留应用后台
    self.closePill = [[UIView alloc] init];
    self.closePill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    self.closePill.layer.cornerRadius = 13.0;
    self.closePill.layer.borderWidth = 1.0;
    self.closePill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    UILabel *closeLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 52, 26)];
    closeLabel.text = @"✕";
    closeLabel.textAlignment = NSTextAlignmentCenter;
    closeLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.8];
    closeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [self.closePill addSubview:closeLabel];
    UITapGestureRecognizer *closeTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                             action:@selector(closeFloatingAnimated)];
    [self.closePill addGestureRecognizer:closeTap];
    [self.controlRoot addSubview:self.closePill];
}

#pragma mark - 几何应用

- (void)applyFloatGeometry {
    UIWindow *window = self.appWindow;
    if (!window) return;

    window.frame = self.floatRect;
    window.clipsToBounds = YES;
    window.layer.cornerRadius = self.radius;
    window.layer.cornerCurve = kCACornerCurveContinuous;
    window.layer.masksToBounds = YES;
    window.layer.borderWidth = 1.0;
    window.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;

    [self layoutControls];
}

- (void)layoutControls {
    CGRect rect = self.floatRect;
    CGFloat thickness = kRHHandleThickness;
    CGFloat corner = kRHCornerSize;

    self.topBar.frame = CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, kRHTopBarHeight);
    self.topBar.layer.cornerRadius = MIN(self.radius, kRHTopBarHeight / 2.0);
    if ([self.topBar viewWithTag:999]) {
        [self.topBar viewWithTag:999].center = CGPointMake(self.topBar.bounds.size.width / 2.0,
                                                           self.topBar.bounds.size.height / 2.0);
    }

    self.closePill.frame = CGRectMake(CGRectGetMidX(rect) - 26.0, CGRectGetMaxY(rect) + 8.0, 52.0, 26.0);

    CGFloat midY = CGRectGetMidY(rect);
    NSArray<NSNumber *> *modes = @[@(RHDragModeResizeLeft), @(RHDragModeResizeRight),
                                   @(RHDragModeResizeTop), @(RHDragModeResizeBottom),
                                   @(RHDragModeResizeTopLeft), @(RHDragModeResizeTopRight),
                                   @(RHDragModeResizeBottomLeft), @(RHDragModeResizeBottomRight)];
    for (NSUInteger i = 0; i < self.handles.count && i < modes.count; i++) {
        UIView *handle = self.handles[i];
        switch ((RHDragMode)modes[i].integerValue) {
            case RHDragModeResizeLeft:
                handle.frame = CGRectMake(CGRectGetMinX(rect), midY - rect.size.height / 2.0 + corner,
                                          thickness, rect.size.height - corner * 2.0);
                break;
            case RHDragModeResizeRight:
                handle.frame = CGRectMake(CGRectGetMaxX(rect) - thickness, midY - rect.size.height / 2.0 + corner,
                                          thickness, rect.size.height - corner * 2.0);
                break;
            case RHDragModeResizeTop:
                handle.frame = CGRectMake(CGRectGetMinX(rect) + corner, CGRectGetMinY(rect),
                                          rect.size.width - corner * 2.0, thickness);
                break;
            case RHDragModeResizeBottom:
                handle.frame = CGRectMake(CGRectGetMinX(rect) + corner, CGRectGetMaxY(rect) - thickness,
                                          rect.size.width - corner * 2.0, thickness);
                break;
            case RHDragModeResizeTopLeft:
                handle.frame = CGRectMake(CGRectGetMinX(rect), CGRectGetMinY(rect), corner, corner);
                break;
            case RHDragModeResizeTopRight:
                handle.frame = CGRectMake(CGRectGetMaxX(rect) - corner, CGRectGetMinY(rect), corner, corner);
                break;
            case RHDragModeResizeBottomLeft:
                handle.frame = CGRectMake(CGRectGetMinX(rect), CGRectGetMaxY(rect) - corner, corner, corner);
                break;
            case RHDragModeResizeBottomRight:
                handle.frame = CGRectMake(CGRectGetMaxX(rect) - corner, CGRectGetMaxY(rect) - corner, corner, corner);
                break;
            default:
                break;
        }
    }
}

#pragma mark - 拖动 / 缩放

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *handle = gesture.view;
    CGPoint translation = [gesture translationInView:self.controlRoot];

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.dragMode = (RHDragMode)handle.tag;
        self.dragStartRect = self.floatRect;
        return;
    }
    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled ||
        gesture.state == UIGestureRecognizerStateFailed) {
        self.dragMode = RHDragModeNone;
        self.floatRect = RHClampRectToScreen(self.floatRect);
        [self applyFloatGeometry];
        [self persistRect];
        return;
    }
    if (gesture.state != UIGestureRecognizerStateChanged) return;

    CGRect rect = self.dragStartRect;
    CGFloat dx = translation.x;
    CGFloat dy = translation.y;

    switch (self.dragMode) {
        case RHDragModeMove: {
            rect.origin.x += dx;
            rect.origin.y += dy;
            CGSize screen = self.controlRoot.bounds.size;
            rect.origin.x = MAX(0.0, MIN(rect.origin.x, screen.width - rect.size.width));
            rect.origin.y = MAX(0.0, MIN(rect.origin.y, screen.height - rect.size.height));
            break;
        }
        case RHDragModeResizeLeft:
        case RHDragModeResizeTopLeft:
        case RHDragModeResizeBottomLeft: {
            CGFloat newX = rect.origin.x + dx;
            CGFloat newWidth = rect.size.width - dx;
            if (newWidth >= kRHMinWidth && newX >= 0) {
                rect.origin.x = newX;
                rect.size.width = newWidth;
            }
            break;
        }
        default:
            break;
    }
    switch (self.dragMode) {
        case RHDragModeResizeRight:
        case RHDragModeResizeTopRight:
        case RHDragModeResizeBottomRight: {
            CGFloat newWidth = rect.size.width + dx;
            CGSize screen = self.controlRoot.bounds.size;
            if (newWidth >= kRHMinWidth && rect.origin.x + newWidth <= screen.width) {
                rect.size.width = newWidth;
            }
            break;
        }
        default:
            break;
    }
    switch (self.dragMode) {
        case RHDragModeResizeTop:
        case RHDragModeResizeTopLeft:
        case RHDragModeResizeTopRight: {
            CGFloat newY = rect.origin.y + dy;
            CGFloat newHeight = rect.size.height - dy;
            if (newHeight >= kRHMinHeight && newY >= 0) {
                rect.origin.y = newY;
                rect.size.height = newHeight;
            }
            break;
        }
        default:
            break;
    }
    switch (self.dragMode) {
        case RHDragModeResizeBottom:
        case RHDragModeResizeBottomLeft:
        case RHDragModeResizeBottomRight: {
            CGFloat newHeight = rect.size.height + dy;
            CGSize screen = self.controlRoot.bounds.size;
            if (newHeight >= kRHMinHeight && rect.origin.y + newHeight <= screen.height) {
                rect.size.height = newHeight;
            }
            break;
        }
        default:
            break;
    }

    self.floatRect = rect;
    [self applyFloatGeometry];
}

// 记录最新尺寸，下次打开同一应用时沿用
- (void)persistRect {
    RHFloatState *state = [RHFloatState current];
    if (!state.floating) return;
    state.rect = self.floatRect;
    state.radius = self.radius;
    [state save];
}

#pragma mark - 关闭

- (void)closeFloatingAnimated {
    [self closeFloating];
}

- (void)closeFloating {
    if (!self.active) return;

    RHFloatState *state = [RHFloatState current];
    NSString *home = state.homeBundleID;

    state.floating = NO;
    [state save];

    [self dismissLocal];

    // 通知 SpringBoard：小窗已关闭；背后应用/桌面信息从会话状态文件中读取
    RHPostNotify(RHNotifyCloseFloat, nil);

    if (home.length == 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            RHSuspendSelf();   // 背后是桌面：让应用自己退到后台，回到桌面
        });
    }
}

- (void)dismissLocal {
    if (!self.active) return;
    self.active = NO;
    self.activating = NO;
    self.dragMode = RHDragModeNone;

    UIWindow *window = self.appWindow;
    if (window) {
        window.clipsToBounds = self.savedClips;
        window.layer.cornerRadius = self.savedRadius;
        window.layer.masksToBounds = self.savedRadius > 0 ? YES : self.savedClips;
        window.layer.borderWidth = self.savedBorderWidth;
        window.layer.borderColor = nil;
        window.frame = self.savedFrame;
        window.windowLevel = self.savedLevel;
    }

    self.backdropWindow.hidden = YES;
    self.backdropWindow = nil;
    self.controlWindow.hidden = YES;
    self.controlWindow = nil;

    for (UIView *view in self.handles) [view removeFromSuperview];
    [self.handles removeAllObjects];
    [self.topBar removeFromSuperview];
    [self.closePill removeFromSuperview];
    self.topBar = nil;
    self.closePill = nil;
    self.controlRoot = nil;
    self.appWindow = nil;
}

#pragma mark - 主窗口查找

- (UIWindow *)findAppMainWindow {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return nil;

    UIWindowScene *scene = nil;
    for (UIScene *candidate in app.connectedScenes) {
        if (![candidate isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)candidate;
        if (windowScene.activationState == UISceneActivationStateForegroundActive) {
            scene = windowScene;
            break;
        }
        if (!scene) scene = windowScene;
    }
    if (!scene) return nil;

    UIWindow *largestNormal = nil;
    CGFloat largestArea = 0;
    for (UIWindow *window in scene.windows) {
        if (window.windowLevel != UIWindowLevelNormal) continue;
        CGFloat area = window.frame.size.width * window.frame.size.height;
        if (window.isKeyWindow) return window;
        if (area > largestArea) { largestArea = area; largestNormal = window; }
    }
    if (largestNormal) return largestNormal;

    // 极端情况下退化为场景内任意窗口
    for (UIWindow *window in scene.windows) {
        if (window.hidden) continue;
        CGFloat area = window.frame.size.width * window.frame.size.height;
        if (area > largestArea) { largestArea = area; largestNormal = window; }
    }
    return largestNormal;
}

@end