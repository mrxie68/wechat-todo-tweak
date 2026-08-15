#import <Foundation/Foundation.h>

// 待办事项：本地存储为主，命令式对话操作，可同步到 Memos
@interface AITodoManager : NSObject

+ (NSString *)handleCommand:(NSString *)text;  // 解析对话命令，返回要回复的文本
+ (NSString *)usageText;
+ (NSArray<NSDictionary *> *)allTodos;         // [{id, content, created, done, doneAt}]
+ (NSUInteger)unfinishedCount;

// Memos 同步：返回结果文本（同步成功/失败原因）
+ (NSString *)syncToMemosNow;

@end
