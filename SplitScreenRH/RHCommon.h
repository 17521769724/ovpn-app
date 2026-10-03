//
//  RHCommon.h
//  SplitScreenRH —— iOS 16 小窗分屏插件（Dopamine / RootHide 兼容）
//
//  说明：
//    * 全工程使用 Objective-C++（.mm）+ -O2 编译，不依赖 Swift 运行时，性能开销极低。
//    * 本文件为跨进程（SpringBoard <-> 目标 App）共享的工具与常量声明。
//

#ifndef RH_COMMON_H
#define RH_COMMON_H

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#define RH_VERSION        @"1.0.0"
#define RH_PREFS_DOMAIN   @"com.roothide.splitscreenrh"
#define RH_NOTIFY_PREFIX  @"com.roothide.splitscreenrh"

// ---------- 偏好设置键 ----------
#define RH_KEY_ENABLED  @"enabled"        // 功能总开关（默认 YES）
#define RH_KEY_RADIUS   @"cornerRadius"   // 小窗圆角（默认 18）
#define RH_KEY_WIDTH    @"widthPercent"   // 小窗宽度占比（默认 0.62）
#define RH_KEY_HEIGHT   @"heightPercent"  // 小窗高度占比（默认 0.52）
#define RH_KEY_EDGE     @"triggerEdge"    // 触发边缘：0=双侧 1=左侧 2=右侧
#define RH_KEY_APPS     @"apps"           // 已添加应用 bundle id 数组

// ---------- 默认值 ----------
#define RH_DEF_RADIUS   18.0
#define RH_DEF_WIDTH    0.62
#define RH_DEF_HEIGHT   0.52
#define RH_DEF_EDGE     0

// ---------- 跨进程共享文件（沙盒外，SpringBoard 与 App 均可读写） ----------
#define RH_STATE_TMP_PATH  @"/var/tmp/com.roothide.splitscreenrh.state.plist"
#define RH_PREFS_MIRROR    @"/var/tmp/com.roothide.splitscreenrh.prefs.plist"
#define RH_SNAP_TMP_PATH   @"/var/tmp/com.roothide.splitscreenrh.snapshot.png"
#define RH_STATE_FILE_NAME @"com.roothide.splitscreenrh.state.plist"
#define RH_SNAP_FILE_NAME  @"com.roothide.splitscreenrh.snapshot.png"

typedef NS_ENUM(NSInteger, RHEdgeMode) {
    RHEdgeModeBoth  = 0,
    RHEdgeModeLeft  = 1,
    RHEdgeModeRight = 2,
};

#pragma mark - 跨进程 Darwin 通知

extern NSString *const RHNotifyAppActive;       // App -> SpringBoard：应用进入前台
extern NSString *const RHNotifyAppInactive;     // App -> SpringBoard：应用退到后台
extern NSString *const RHNotifyCloseFloat;      // App -> SpringBoard：小窗已关闭（附带 home）
extern NSString *const RHNotifyFloatDismissed;  // App -> SpringBoard：小窗异常消失，清理状态
extern NSString *const RHNotifySettingsChanged; // 设置变更：SpringBoard 重载边缘手势

void RHPostNotify(NSString *name, NSDictionary *userInfo);

#pragma mark - 偏好设置

BOOL RHIsEnabled(void);
void RHSetEnabled(BOOL enabled);

CGFloat RHCornerRadius(void);
void RHSetCornerRadius(CGFloat radius);

CGFloat RHWidthPercent(void);
void RHSetWidthPercent(CGFloat percent);

CGFloat RHHeightPercent(void);
void RHSetHeightPercent(CGFloat percent);

RHEdgeMode RHTriggerEdge(void);
void RHSetTriggerEdge(RHEdgeMode mode);

NSArray<NSString *> *RHAddedApps(void);
void RHSetAddedApps(NSArray<NSString *> *apps);

NSDictionary *RHPrefsSnapshot(void);
void RHResetDefaults(void);
void RHReloadPrefs(void);

#pragma mark - 环境 / 工具

BOOL RHIsSpringBoard(void);
BOOL RHIsApplicationProcess(void);
NSString *RHProcessBundleID(void);

UIWindowScene *RHMainWindowScene(void);
CGSize RHScreenSize(void);
BOOL RHIsDeviceLocked(void);

NSString *RHForegroundBundleID(void);
void RHSetForegroundBundleID(NSString *bundleID);
NSString *RHProbeForegroundBundleID(void);   // 私有 API 兜底探测

BOOL RHAppExists(NSString *bundleID);
BOOL RHLaunchApp(NSString *bundleID);
void RHSuspendSelf(void);

UIImage *RHCreateScreenImage(void);
UIImage *RHIconForBundle(NSString *bundleID, CGFloat size);
NSString *RHAppNameForBundle(NSString *bundleID);
NSString *RHContainerPathForBundle(NSString *bundleID);
NSArray<NSDictionary *> *RHInstalledApps(BOOL includeSystem);
NSString *RHBundleIDFromObject(id object);

CGRect RHDefaultFloatRect(void);
CGRect RHClampRectToScreen(CGRect rect);

#pragma mark - 小窗状态（SpringBoard 写入 / 目标 App 读取）

@interface RHFloatState : NSObject
@property (nonatomic, assign) BOOL floating;        // 是否处于小窗模式
@property (nonatomic, copy)   NSString *bundleID;   // 以小窗打开的应用
@property (nonatomic, copy)   NSString *homeBundleID; // 小窗背后的应用（nil = 桌面）
@property (nonatomic, assign) CGRect rect;          // 小窗在屏幕坐标系中的位置
@property (nonatomic, assign) CGFloat radius;       // 圆角
@property (nonatomic, assign) NSTimeInterval timestamp; // 版本号，用于选取最新状态

+ (instancetype)current;         // 读取最新状态（/var/tmp 与自身容器取最新）
+ (instancetype)currentForSelf;  // 仅当 bundleID 与当前进程匹配时返回，否则 nil
- (BOOL)isForSelf;
- (void)save;                    // 同时写入 /var/tmp 与目标 App 容器（双通道）
- (void)clear;
- (void)writeSnapshot:(UIImage *)image;
- (UIImage *)loadSnapshot;
@end

#endif /* RH_COMMON_H */