//
//  RHInit.mm
//  SplitScreenRH —— 注入入口（SpringBoard 与 所有 App 共用同一个 dylib）
//

#import "RHInternal.h"

static void RHBootstrap(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        RHReloadPrefs();

        if (RHIsSpringBoard()) {
            // SpringBoard 侧：边缘手势 + 面板 + 小窗会话调度
            [[RHSpringManager shared] start];
        } else if (RHIsApplicationProcess()) {
            // 普通 App 侧：监听生命周期，按会话状态自动进入/退出小窗
            [[RHFloatingController shared] startMonitoring];
        }
    });
}

__attribute__((constructor)) static void RHInitConstructor(void) {
    // 推迟到主线程执行，确保 UIKit / UIApplication 已可用
    dispatch_async(dispatch_get_main_queue(), ^{
        RHBootstrap();
    });
}