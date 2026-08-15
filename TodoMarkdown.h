#import <UIKit/UIKit.h>

// 基础 Markdown 渲染：标题 # / 列表 - / 任务项 - [ ] - [x] / **加粗** / *斜体* / `代码` / ~~删除线~~
NSAttributedString *todoMarkdownString(NSString *raw, CGFloat baseSize);
