#import <UIKit/UIKit.h>

// Markdown 编辑页：大文本框 + 格式工具条 + 预览
@interface TodoEditorViewController : UIViewController

- (instancetype)initWithTitle:(NSString *)title
                  initialText:(NSString *)text
                   completion:(void (^)(NSString *text))completion;

@end
