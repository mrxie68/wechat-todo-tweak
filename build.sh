#!/bin/bash
# 在 macOS runner 上编译 iOS arm64 dylib
set -euo pipefail

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
echo "iOS SDK: $SDK"

set +e
clang \
  -arch arm64 \
  -isysroot "$SDK" \
  -miphoneos-version-min=13.0 \
  -fobjc-arc \
  -fobjc-exceptions \
  -Wno-deprecated-declarations \
  -Wl,-install_name,@executable_path/wechat-todo.dylib \
  -dynamiclib \
  -framework Foundation \
  -framework UIKit \
  -framework CoreGraphics \
  -framework QuartzCore \
  -lsqlite3 \
  -o wechat-todo.dylib \
  AISettings.m AITodoManager.m SubTaskItem.m MainTodoItem.m \
  TodoEditorViewController.m \
  TodoSettingsViewController.m CustomCalendarTodoViewController.m CustomTodoTableViewCell.m WeChatTodoTweak.m \
  > build.log 2>&1
RC=$?
set -e
cat build.log
if [ $RC -ne 0 ]; then
  echo "编译失败，退出码 $RC"
  exit $RC
fi

codesign -f -s - wechat-todo.dylib || true

file wechat-todo.dylib
echo "构建完成: $(pwd)/wechat-todo.dylib"
