#import <UIKit/UIKit.h>

// 待办二级页：全部待办 / 全部书签（跨日期汇总列表）
@interface TodoListViewController : UIViewController

+ (instancetype)allPage;
+ (instancetype)bookmarkPage;

@end
