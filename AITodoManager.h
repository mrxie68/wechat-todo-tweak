#import <Foundation/Foundation.h>

// 待办事项：本地存储为主，供待办页 UI 调用，可同步到 Memos
@interface AITodoManager : NSObject

+ (NSArray<NSDictionary *> *)allTodos;         // [{id, content, created, done, doneAt}]
+ (NSUInteger)unfinishedCount;
+ (NSString *)addTodo:(NSString *)content;     // 新增，返回确认文本
+ (NSString *)markTodo:(NSInteger)todoId done:(BOOL)done;
+ (NSString *)deleteTodo:(NSInteger)todoId;
+ (NSString *)clearDone;                      // 清空所有已完成，返回提示文本
+ (NSString *)syncToMemosNow;                  // 同步，返回结果文本

@end
