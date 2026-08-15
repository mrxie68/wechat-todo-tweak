#ifndef AIConfig_h
#define AIConfig_h

// 待办事项插件版本（设置页底部显示）
#define kAITodoVersion @"0.2.10"

// 旧版假联系人 ID（v0.2.0 已弃用，仅用于启动时一次性清理残留）
#define kAITodoChatId @"todo@local"

// 日志前缀
#define kAITodoLogPrefix @"[WeChatTodo] "

// 待办页出现/消失通知（底栏待办 tab 用来切换选中高亮）
#define kWeChatTodoPageAppearNotification @"WeChatTodoPageDidAppear"
#define kWeChatTodoPageDisappearNotification @"WeChatTodoPageWillDisappear"

#endif
