#import <UIKit/UIKit.h>

// 待办列表自定义单元格：左侧独立勾选按钮 + 正文（最多两行）+ 元信息行
@interface TodoTableViewCell : UITableViewCell

@property (nonatomic, strong, readonly) UIButton *checkButton;
@property (nonatomic, strong, readonly) UILabel *contentLabel;
@property (nonatomic, strong, readonly) UILabel *metaLabel;
@property (nonatomic, copy) void (^onToggle)(void);

- (void)setDone:(BOOL)done important:(BOOL)important overdue:(BOOL)overdue
        content:(NSString *)content meta:(NSString *)meta;

@end
