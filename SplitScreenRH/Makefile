TARGET = iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SplitScreenRH

SplitScreenRH_FILES = \
	RHInit.mm \
	RHCommon.mm \
	RHSpringManager.mm \
	RHWatchPanel.mm \
	RHSettings.mm \
	RHFloating.mm

# Objective-C++ + -O2：无 Swift 运行时依赖，注入体积极小、性能开销低
SplitScreenRH_CFLAGS = -fobjc-arc -O2 -fno-objc-arc-exceptions -I$(THEOS_PROJECT_DIR)
SplitScreenRH_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"