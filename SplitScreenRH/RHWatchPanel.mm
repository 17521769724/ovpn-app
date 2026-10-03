//
//  RHWatchPanel.mm
//  SplitScreenRH —— iWatch 表盘风格（蜂窝网格）应用选择面板
//
//  视觉结构：
//    · 中心是一块模拟表盘（指针时钟）
//    · 已添加应用按蜂窝（honeycomb）环状排列，离中心越远图标越小
//    · 支持拖动平移网格、点击空白/下滑关闭、⚙︎ 进入设置
//

#import "RHInternal.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - 表盘时钟视图

@interface RHWatchClockView : UIView
- (void)startTicking;
- (void)stopTicking;
@end

@implementation RHWatchClockView {
    CAShapeLayer *_hourHand;
    CAShapeLayer *_minuteHand;
    CAShapeLayer *_secondHand;
    NSTimer      *_timer;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        CGFloat side = MIN(frame.size.width, frame.size.height);
        self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.07];
        self.layer.cornerRadius = side / 2.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;

        // 表盘刻度
        CAShapeLayer *ticks = [CAShapeLayer layer];
        UIBezierPath *tickPath = [UIBezierPath bezierPath];
        CGFloat radius = side / 2.0 - 8.0;
        for (int i = 0; i < 12; i++) {
            CGFloat angle = (M_PI * 2.0 / 12.0) * i - M_PI_2;
            CGFloat len = (i % 3 == 0) ? 7.0 : 4.0;
            CGPoint outer = CGPointMake(side / 2.0 + cos(angle) * radius,
                                        side / 2.0 + sin(angle) * radius);
            CGPoint inner = CGPointMake(side / 2.0 + cos(angle) * (radius - len),
                                        side / 2.0 + sin(angle) * (radius - len));
            [tickPath moveToPoint:inner];
            [tickPath addLineToPoint:outer];
        }
        ticks.path = tickPath.CGPath;
        ticks.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.30].CGColor;
        ticks.lineWidth = 1.5;
        ticks.fillColor = [UIColor clearColor].CGColor;
        [self.layer addSublayer:ticks];

        CGFloat center = side / 2.0;
        _hourHand   = [self handLayerWithWidth:3.0 color:[UIColor colorWithWhite:1.0 alpha:0.92]];
        _minuteHand = [self handLayerWithWidth:2.0 color:[UIColor colorWithWhite:1.0 alpha:0.92]];
        _secondHand = [self handLayerWithWidth:1.0 color:[UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:0.95]];
        _hourHand.position   = CGPointMake(center, center);
        _minuteHand.position = CGPointMake(center, center);
        _secondHand.position = CGPointMake(center, center);
        [self updateHands];
    }
    return self;
}

- (CAShapeLayer *)handLayerWithWidth:(CGFloat)width color:(UIColor *)color {
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.strokeColor = color.CGColor;
    layer.lineWidth = width;
    layer.lineCap = kCALineCapRound;
    layer.fillColor = [UIColor clearColor].CGColor;
    layer.anchorPoint = CGPointMake(0.5, 0.5);
    [self.layer addSublayer:layer];
    return layer;
}

- (void)updateHands {
    CGFloat side = MIN(self.bounds.size.width, self.bounds.size.height);
    if (side <= 0) return;
    CGFloat center = side / 2.0;
    NSDateComponents *comp = [[NSCalendar currentCalendar]
                              components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
                              fromDate:[NSDate date]];
    CGFloat hourAngle   = (comp.hour % 12) / 12.0 * M_PI * 2.0 + comp.minute / 60.0 * M_PI / 6.0;
    CGFloat minuteAngle = comp.minute / 60.0 * M_PI * 2.0 + comp.second / 60.0 * M_PI / 30.0;
    CGFloat secondAngle = comp.second / 60.0 * M_PI * 2.0;

    _hourHand.path = [self pathFromCenter:CGPointMake(center, center)
                                   length:side * 0.26
                                    angle:hourAngle - M_PI_2].CGPath;
    _minuteHand.path = [self pathFromCenter:CGPointMake(center, center)
                                     length:side * 0.36
                                      angle:minuteAngle - M_PI_2].CGPath;
    _secondHand.path = [self pathFromCenter:CGPointMake(center, center)
                                     length:side * 0.40
                                      angle:secondAngle - M_PI_2].CGPath;
}

- (UIBezierPath *)pathFromCenter:(CGPoint)center length:(CGFloat)length angle:(CGFloat)angle {
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:center];
    [path addLineToPoint:CGPointMake(center.x + cos(angle) * length,
                                     center.y + sin(angle) * length)];
    return path;
}

- (void)startTicking {
    [self stopTicking];
    [self updateHands];
    _timer = [NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(updateHands)
                                   userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)stopTicking {
    if (_timer) { [_timer invalidate]; _timer = nil; }
}

- (void)didMoveToWindow {
    if (self.window) [self startTicking];
    else [self stopTicking];
}

@end

#pragma mark - 蜂窝布局数学（环形六边形排布）

static NSArray<NSValue *> *RHHoneycombPositions(NSInteger count, CGFloat spacing) {
    NSMutableArray<NSValue *> *points = [NSMutableArray arrayWithCapacity:count];
    if (count <= 0) return points;
    [points addObject:[NSValue valueWithCGPoint:CGPointZero]];
    NSInteger placed = 1;
    NSInteger ring = 1;
    while (placed < count && ring < 24) {
        NSInteger slots = 6 * ring;
        CGFloat phase = M_PI / (6.0 * (CGFloat)ring);   // 相邻环错开半格，形成蜂窝
        for (NSInteger i = 0; i < slots && placed < count; i++) {
            CGFloat angle = 2.0 * M_PI * (CGFloat)i / (CGFloat)slots + phase;
            CGFloat radius = ring * spacing;
            CGPoint point = CGPointMake(cos(angle) * radius, sin(angle) * radius);
            [points addObject:[NSValue valueWithCGPoint:point]];
            placed++;
        }
        ring++;
    }
    return points;
}

#pragma mark - 面板

@interface RHWatchPanelController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *gridView;
@property (nonatomic, strong) RHWatchClockView *clockView;
@property (nonatomic, strong) NSMutableArray<UIButton *> *iconButtons;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property (nonatomic, assign) CGPoint panStartOffset;
@property (nonatomic, assign) BOOL panMovesGrid;
@end

@implementation RHWatchPanelController

- (instancetype)init {
    self = [super init];
    if (self) {
        _iconButtons = [NSMutableArray array];
        _apps = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    // 背景：深色毛玻璃 + 压暗
    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
    _blurView = [[UIVisualEffectView alloc] initWithEffect:effect];
    _blurView.frame = self.view.bounds;
    _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _blurView.alpha = 0.96;
    [self.view addSubview:_blurView];

    UIView *dim = [[UIView alloc] initWithFrame:self.view.bounds];
    dim.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.28];
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    dim.userInteractionEnabled = NO;
    [self.view addSubview:dim];

    // 蜂窝网格容器（透明，仅用于承载图标）
    _gridView = [[UIView alloc] initWithFrame:CGRectZero];
    _gridView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_gridView];

    [self buildIcons];

    // 底部提示 + 设置按钮
    _hintLabel = [[UILabel alloc] init];
    _hintLabel.text = _apps.count ? @"点击图标以小窗打开 · 边缘拖动可缩放小窗" : @"还没有添加应用，点 ⚙︎ 进入设置添加";
    _hintLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _hintLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    _hintLabel.textAlignment = NSTextAlignmentCenter;
    [_hintLabel sizeToFit];
    [self.view addSubview:_hintLabel];

    _settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *gear = [UIImage systemImageNamed:@"gearshape.fill"];
    if (gear) {
        [_settingsButton setImage:gear forState:UIControlStateNormal];
    } else {
        [_settingsButton setTitle:@"设置" forState:UIControlStateNormal];
    }
    _settingsButton.tintColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    _settingsButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    _settingsButton.layer.cornerRadius = 24.0;
    _settingsButton.layer.borderWidth = 1.0;
    _settingsButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
    [_settingsButton addTarget:self action:@selector(settingsTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_settingsButton];

    // 手势
    _tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    _tapGesture.delegate = self;
    [self.view addGestureRecognizer:_tapGesture];

    _panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    _panGesture.delegate = self;
    [self.view addGestureRecognizer:_panGesture];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;

    _blurView.frame = self.view.bounds;
    _hintLabel.center = CGPointMake(size.width / 2.0, size.height - 118.0);
    _settingsButton.frame = CGRectMake(size.width / 2.0 - 24.0, size.height - 92.0, 48.0, 48.0);

    [self layoutHoneycomb];
}

#pragma mark - 构建图标

- (void)buildIcons {
    for (UIButton *button in _iconButtons) [button removeFromSuperview];
    [_iconButtons removeAllObjects];
    [_clockView removeFromSuperview];
    _clockView = nil;

    CGFloat iconSize = 62.0;
    _clockView = [[RHWatchClockView alloc] initWithFrame:CGRectMake(0, 0, iconSize * 1.1, iconSize * 1.1)];
    [_gridView addSubview:_clockView];

    for (NSString *bundleID in self.apps) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(0, 0, iconSize, iconSize);
        button.layer.cornerRadius = iconSize / 2.0;
        button.layer.cornerCurve = kCACornerCurveContinuous;
        button.clipsToBounds = YES;
        button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
        button.layer.borderWidth = 1.0;
        button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;

        UIImage *icon = RHIconForBundle(bundleID, iconSize);
        if (icon) {
            [button setImage:icon forState:UIControlStateNormal];
            button.imageView.contentMode = UIViewContentModeScaleAspectFill;
            button.imageView.layer.cornerRadius = iconSize / 2.0;   // 图片圆形裁切
            button.imageView.clipsToBounds = YES;
            button.backgroundColor = [UIColor clearColor];
            // 阴影增强立体感（iWatch 蜂窝质感）
            button.layer.masksToBounds = NO;
            button.layer.shadowColor = [UIColor blackColor].CGColor;
            button.layer.shadowOpacity = 0.35;
            button.layer.shadowRadius = 9.0;
            button.layer.shadowOffset = CGSizeMake(0, 3);
        } else {
            NSString *name = RHAppNameForBundle(bundleID);
            [button setTitle:[name substringToIndex:MIN((NSUInteger)2, name.length)]
                    forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
        }

        button.accessibilityIdentifier = bundleID;
        [button addTarget:self action:@selector(iconTapped:) forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:self action:@selector(iconTouchDown:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(iconTouchUp:) forControlEvents:(UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel)];
        [_gridView addSubview:button];
        [_iconButtons addObject:button];
    }
}

// 计算蜂窝坐标：中心留作表盘，应用从第一环开始
- (void)layoutHoneycomb {
    CGSize size = self.view.bounds.size;
    if (size.width <= 0) return;

    CGFloat iconSize = 62.0;
    CGFloat spacing = 68.0;

    NSInteger total = (NSInteger)self.apps.count + 1;   // +1：中心表盘占位
    if (total <= 1) {
        _gridView.frame = CGRectMake(0, 0, size.width, size.height);
        _clockView.center = CGPointMake(size.width / 2.0, size.height / 2.0 - 20.0);
        return;
    }

    NSArray<NSValue *> *positions = RHHoneycombPositions(total, spacing);
    CGFloat maxRadius = 1.0;
    for (NSValue *value in positions) {
        maxRadius = MAX(maxRadius, hypot(value.CGPointValue.x, value.CGPointValue.y));
    }
    CGFloat gridSide = (maxRadius + iconSize) * 2.0 + 40.0;

    CGFloat centerX = size.width / 2.0;
    CGFloat centerY = size.height / 2.0 - 20.0;
    // 中心适当放大网格空间，保证第一屏尽可能展示完整
    _gridView.frame = CGRectMake(centerX - gridSide / 2.0, centerY - gridSide / 2.0, gridSide, gridSide);

    CGPoint gridCenter = CGPointMake(_gridView.bounds.size.width / 2.0, _gridView.bounds.size.height / 2.0);

    for (NSInteger index = 0; index < (NSInteger)positions.count; index++) {
        CGPoint offset = positions[index].CGPointValue;
        CGPoint point = CGPointMake(gridCenter.x + offset.x, gridCenter.y + offset.y);
        CGFloat distance = hypot(offset.x, offset.y);
        if (index == 0) {
            _clockView.center = point;
            continue;
        }
        NSInteger appIndex = index - 1;
        if (appIndex >= (NSInteger)_iconButtons.count) break;
        UIButton *button = _iconButtons[appIndex];
        button.center = point;
        CGFloat scale = 1.0 - 0.42 * MIN(1.0, distance / MAX(maxRadius, 1.0));
        button.transform = CGAffineTransformMakeScale(scale, scale);
        button.alpha = 1.0 - 0.25 * MIN(1.0, distance / MAX(maxRadius, 1.0));
    }
}

#pragma mark - 交互

- (void)iconTapped:(UIButton *)button {
    NSString *bundleID = button.accessibilityIdentifier;
    if (bundleID.length == 0) return;
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    if (self.onSelect) self.onSelect(bundleID);
}

- (void)iconTouchDown:(UIButton *)button {
    [UIView animateWithDuration:0.12 animations:^{
        button.transform = CGAffineTransformScale(button.transform, 0.90, 0.90);
    }];
}

- (void)iconTouchUp:(UIButton *)button {
    [UIView animateWithDuration:0.16 animations:^{
        button.transform = CGAffineTransformScale(button.transform, 1.0 / 0.90, 1.0 / 0.90);
    }];
}

- (void)settingsTapped {
    if (self.onSettings) self.onSettings();
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    UIView *touched = [gesture.view hitTest:[gesture locationInView:gesture.view] withEvent:nil];
    // 点在图标/设置按钮上时不处理（由控件自身处理）
    if ([touched isKindOfClass:[UIButton class]]) return;
    if ([touched isKindOfClass:[UIControl class]]) return;
    if (self.onDismiss) self.onDismiss();
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.view];
    CGPoint translation = [gesture translationInView:self.view];

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.panStartOffset = _gridView.center;
        self.panMovesGrid = CGRectContainsPoint(_gridView.frame, location);
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        if (self.panMovesGrid) {
            CGPoint center = CGPointMake(self.panStartOffset.x + translation.x,
                                         self.panStartOffset.y + translation.y);
            _gridView.center = center;
        } else if (translation.y > 90.0 && fabs(translation.y) > fabs(translation.x)) {
            // 空白区域下滑关闭
            if (self.onDismiss) self.onDismiss();
        }
    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled) {
        self.panMovesGrid = NO;
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isKindOfClass:[UIControl class]];
}

#pragma mark - 动画

- (void)animateIn {
    self.view.alpha = 0.0;
    _gridView.transform = CGAffineTransformMakeScale(0.84, 0.84);
    _hintLabel.alpha = 0.0;
    _settingsButton.alpha = 0.0;

    [UIView animateWithDuration:0.32 delay:0.0
         usingSpringWithDamping:0.82 initialSpringVelocity:0.4
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.view.alpha = 1.0;
        self.gridView.transform = CGAffineTransformIdentity;
        self.hintLabel.alpha = 1.0;
        self.settingsButton.alpha = 1.0;
    } completion:nil];
}

- (void)animateOutWithCompletion:(void (^)(void))completion {
    [UIView animateWithDuration:0.20 animations:^{
        self.view.alpha = 0.0;
        self.gridView.transform = CGAffineTransformMakeScale(0.88, 0.88);
    } completion:^(BOOL finished) {
        if (completion) completion();
    }];
}

@end