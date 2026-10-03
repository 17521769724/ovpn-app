//
//  RHInternal.h
//  SplitScreenRH —— 内部类声明（各 .mm 共享）
//

#ifndef RH_INTERNAL_H
#define RH_INTERNAL_H

#import "RHCommon.h"

#pragma mark - SpringBoard 侧：全局管理者

@interface RHSpringManager : NSObject
+ (instancetype)shared;
- (void)start;                 // 启动（创建边缘手势窗口、监听通知）
- (void)reloadEdgeWindows;     // 依据设置刷新/移除边缘手势窗口
- (void)presentPanel;          // 唤出 iWatch 表盘式应用面板
- (void)dismissPanel;
@end

#pragma mark - iWatch 表盘蜂窝面板

@interface RHWatchPanelController : UIViewController
@property (nonatomic, copy) NSArray<NSString *> *apps;      // 已添加应用 bundle id
@property (nonatomic, copy) void (^onSelect)(NSString *bundleID);
@property (nonatomic, copy) void (^onSettings)(void);
@property (nonatomic, copy) void (^onDismiss)(void);
- (void)animateIn;
- (void)animateOutWithCompletion:(void (^)(void))completion;
@end

#pragma mark - 设置界面

@interface RHSettingsRootVC : UITableViewController
@property (nonatomic, copy) void (^onClose)(void);
@end

#pragma mark - App 侧：小窗控制器

@interface RHFloatingController : NSObject
+ (instancetype)shared;
- (void)startMonitoring;   // 监听 App 生命周期，自动进入/退出小窗
@end

#endif /* RH_INTERNAL_H */