#!/bin/bash
# 在 macOS runner 上编译 iOS arm64 dylib
set -euo pipefail

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
echo "iOS SDK: $SDK"

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
  TodoSettingsViewController.m CustomCalendarTodoViewController.m CustomTodoTableViewCell.m WeChatTodoTweak.m

codesign -f -s - wechat-todo.dylib || true

file wechat-todo.dylib
echo "构建完成: $(pwd)/wechat-todo.dylib"
