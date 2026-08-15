#import <Foundation/Foundation.h>
#import "MainTodoItem.h"

// 待办数据层：本地模型化存储（NSCoding），旧字典数据自动迁移
@interface AITodoManager : NSObject

+ (NSArray<MainTodoItem *> *)allTodos;                 // 全部（按 identifier 倒序）
+ (NSUInteger)unfinishedCount;
+ (MainTodoItem *)addTodo:(NSString *)content;         // 新增到当前时间
+ (MainTodoItem *)addTodo:(NSString *)content atDate:(NSDate *)date; // 新增到指定日期（时间用 date）
+ (BOOL)markTodo:(NSInteger)todoId done:(BOOL)done;
+ (BOOL)deleteTodo:(NSInteger)todoId;
+ (BOOL)updateTodo:(NSInteger)todoId title:(NSString *)title note:(NSString *)note
                due:(NSDate *)due bookmarked:(BOOL)bookmarked;
+ (BOOL)addSubTask:(NSString *)subTitle toTodo:(NSInteger)todoId;
+ (BOOL)toggleSubTask:(NSString *)subId inTodo:(NSInteger)todoId;
+ (BOOL)setTodo:(NSInteger)todoId selected:(BOOL)selected;
+ (BOOL)toggleBookmarkForTodo:(NSInteger)todoId;
+ (NSUInteger)clearDone;

// 某一天的任务（按 createTime 正序）
+ (NSArray<MainTodoItem *> *)todosOnDay:(NSDate *)day;

+ (NSString *)syncToMemosNow;                          // 同步未完成到 Memos

@end
