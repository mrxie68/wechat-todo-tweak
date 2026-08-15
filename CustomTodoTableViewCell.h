#import <UIKit/UIKit.h>
#import "MainTodoItem.h"

// 高度定制待办卡片：左侧时间 + 右侧圆角任务卡（主任务行 + 子任务列表）
@interface CustomTodoTableViewCell : UITableViewCell

@property (nonatomic, copy) void (^onToggleSelect)(void);   // 点卡片：展开/收起（棕/浅色切换）
@property (nonatomic, copy) void (^onToggleBookmark)(void); // 书签
@property (nonatomic, copy) void (^onAddSubTask)(void);     // 加子任务
@property (nonatomic, copy) void (^onToggleSubTask)(SubTaskItem *sub);
@property (nonatomic, copy) void (^onEditSubTask)(SubTaskItem *sub);
@property (nonatomic, copy) void (^onLongPress)(void);

@property (nonatomic, strong) MainTodoItem *todo;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *iconBg;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *bookmarkButton;
@property (nonatomic, strong) UIButton *plusButton;
@property (nonatomic, strong) NSMutableArray *subRows;
@property (nonatomic, strong) UIView *headerBar;
@property (nonatomic, strong) UITapGestureRecognizer *cardTapGesture;
@property (nonatomic, strong) UILongPressGestureRecognizer *cardLongPressGesture;

- (void)configureWithTodo:(MainTodoItem *)todo;
+ (CGFloat)heightForTodo:(MainTodoItem *)todo width:(CGFloat)width;

@end
