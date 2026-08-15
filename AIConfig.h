#ifndef AIConfig_h
#define AIConfig_h

// 待办事项插件版本（设置页底部显示）
#define kAITodoVersion @"0.3.4"

// 旧版假联系人 ID（v0.2.0 已弃用，仅用于启动时一次性清理残留）
#define kAITodoChatId @"todo@local"

// 日志前缀
#define kAITodoLogPrefix @"[WeChatTodo] "

// 主题色：暖金（参考截图 #f9f9f9 底 + 琥珀金点缀）
#define kAITodoAccentColor  [UIColor colorWithRed:0.96 green:0.62 blue:0.20 alpha:1.0]
#define kAITodoAccentLight  [UIColor colorWithRed:0.99 green:0.70 blue:0.26 alpha:1.0]
#define kAITodoAccentDark   [UIColor colorWithRed:0.93 green:0.55 blue:0.16 alpha:1.0]

// 待办页出现/消失通知（底栏待办 tab 用来切换选中高亮）
#define kWeChatTodoPageAppearNotification @"WeChatTodoPageDidAppear"
#define kWeChatTodoPageDisappearNotification @"WeChatTodoPageWillDisappear"

#endif
