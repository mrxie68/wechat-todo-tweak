#import <UIKit/UIKit.h>

// 待办详情/编辑页：点击列表项进入，可看全文、编辑内容、备注、截止时间、重要标记
@interface TodoDetailViewController : UIViewController

- (instancetype)initWithTodo:(NSDictionary *)todo;

@end
