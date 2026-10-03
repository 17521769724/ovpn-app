#!/bin/bash
#
# build-deb.sh —— 在 Linux 上编译并打包 SplitScreenRH.deb（rootless / Dopamine & RootHide）
#
# 依赖：
#   1. iOS SDK           ：theos/sdks 的 iPhoneOS16.5.sdk
#   2. iOS 工具链        ：theos 的 Linux 工具链（含 clang / ld64 / lipo / ldid）
#                          也可用 macOS 上的 Xcode + Theos，直接执行 `make package` 即可
#   3. clang / dpkg-deb
#
# 用法示例：
#   SDK_ROOT=/path/to/sdks TOOLCHAIN_BIN=/path/to/toolchain/linux/iphone/bin ./build-deb.sh
#
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SDK_ROOT="${SDK_ROOT:-/opt/iosbuild/sdks}"
SDK="${SDK:-$SDK_ROOT/iPhoneOS16.5.sdk}"
TOOLCHAIN_BIN="${TOOLCHAIN_BIN:-/opt/iosbuild/toolchain/linux/iphone/bin}"
CLANG="${CLANG:-clang++}"

LD64="$TOOLCHAIN_BIN/ld"
LIPO="$TOOLCHAIN_BIN/lipo"
LDID="$TOOLCHAIN_BIN/ldid"

OUT="$PROJECT_DIR/build"
PKG="$OUT/pkg"
DYLIB_NAME="SplitScreenRH.dylib"

MIN_IOS="15.0"
SDK_VER="16.5"

FILES="RHInit RHCommon RHSpringManager RHWatchPanel RHSettings RHFloating"

rm -rf "$OUT"
mkdir -p "$OUT/obj" "$PKG/DEBIAN" "$PKG/var/jb/Library/MobileSubstrate/DynamicLibraries"

# ---------- 1. 编译（arm64 + arm64e） ----------
for arch in arm64 arm64e; do
    for name in $FILES; do
        "$CLANG" -target "$arch-apple-ios$MIN_IOS" -isysroot "$SDK" \
            -fobjc-arc -O2 -fno-objc-arc-exceptions -Wall \
            -I"$PROJECT_DIR" -c "$PROJECT_DIR/$name.mm" -o "$OUT/obj/$name.$arch.o"
    done

    # ---------- 2. 链接（必须使用 Apple ld64：LLD 不支持 arm64e 指针认证重定位） ----------
    "$LD64" -arch "$arch" -platform_version ios "$MIN_IOS" "$SDK_VER" -dylib \
        -install_name "/var/jb/Library/MobileSubstrate/DynamicLibraries/$DYLIB_NAME" \
        -syslibroot "$SDK" -L"$SDK/usr/lib" -F"$SDK/System/Library/Frameworks" \
        -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics \
        -undefined dynamic_lookup \
        -o "$OUT/$DYLIB_NAME.$arch" \
        "$OUT/obj/RHInit.$arch.o" "$OUT/obj/RHCommon.$arch.o" "$OUT/obj/RHSpringManager.$arch.o" \
        "$OUT/obj/RHWatchPanel.$arch.o" "$OUT/obj/RHSettings.$arch.o" "$OUT/obj/RHFloating.$arch.o"
done

# ---------- 3. 合成胖二进制并签名 ----------
"$LIPO" -create "$OUT/$DYLIB_NAME.arm64" "$OUT/$DYLIB_NAME.arm64e" -output "$OUT/$DYLIB_NAME"
"$LDID" -S "$OUT/$DYLIB_NAME"

# ---------- 4. 打包 deb ----------
cp "$OUT/$DYLIB_NAME" "$PKG/var/jb/Library/MobileSubstrate/DynamicLibraries/$DYLIB_NAME"
cp "$PROJECT_DIR/layout/Library/MobileSubstrate/DynamicLibraries/SplitScreenRH.plist" \
   "$PKG/var/jb/Library/MobileSubstrate/DynamicLibraries/SplitScreenRH.plist"

VERSION=$(grep -m1 '^Version:' "$PROJECT_DIR/control" | awk '{print $2}')
SIZE=$(( ( $(stat -c%s "$PKG/var/jb/Library/MobileSubstrate/DynamicLibraries/$DYLIB_NAME") \
        + $(stat -c%s "$PKG/var/jb/Library/MobileSubstrate/DynamicLibraries/SplitScreenRH.plist") \
        + 1023 ) / 1024 ))

CONTROL=$(cat "$PROJECT_DIR/control")
CONTROL=$(printf '%s\n' "$CONTROL" | sed "s/^Installed-Size:.*/Installed-Size: $SIZE/")
printf '%s\n' "$CONTROL" > "$PKG/DEBIAN/control"

dpkg-deb --root-owner-group -Zxz -b "$PKG" "$OUT/SplitScreenRH_${VERSION}_iphoneos-arm64.deb"

echo
echo "构建完成： $OUT/SplitScreenRH_${VERSION}_iphoneos-arm64.deb"
"$LIPO" -info "$OUT/$DYLIB_NAME"
dpkg-deb -c "$OUT/SplitScreenRH_${VERSION}_iphoneos-arm64.deb" | tail -3