#import <Foundation/Foundation.h>
#import "SubTaskItem.h"

// 主任务模型：标题 + 创建时间（显示/排序）+ 子任务 + 选中态（展开/棕色卡片）+ 书签
// 必须声明 NSSecureCoding，否则 secure archiver 归档会抛异常
@interface MainTodoItem : NSObject <NSSecureCoding>

@property (nonatomic, assign) NSInteger identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSDate *createTime;   // 用于显示时间和按天排序
@property (nonatomic, strong) NSMutableArray<SubTaskItem *> *subTasks;
@property (nonatomic, assign) BOOL isSelected;      // 控制卡片背景色与展开
@property (nonatomic, assign) BOOL isBookmarked;    // 金色书签
@property (nonatomic, assign) BOOL done;
@property (nonatomic, strong) NSDate *doneAt;
@property (nonatomic, copy) NSString *note;
@property (nonatomic, strong) NSDate *dueDate;

- (BOOL)hasSubtasks;

@end
