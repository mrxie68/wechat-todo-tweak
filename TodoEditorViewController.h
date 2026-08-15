#import <UIKit/UIKit.h>

// 简洁漂亮的编辑页：大圆角文本框 + 占位提示 + 字数统计
@interface TodoEditorViewController : UIViewController

- (instancetype)initWithTitle:(NSString *)title
                  initialText:(NSString *)text
                   completion:(void (^)(NSString *text))completion;

@end
