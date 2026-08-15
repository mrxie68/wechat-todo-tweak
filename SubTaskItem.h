#import <Foundation/Foundation.h>

// 子任务模型
// 必须声明 NSSecureCoding（NSCoding 不包含它），否则 secure archiver 归档会抛异常
@interface SubTaskItem : NSObject <NSSecureCoding>

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) BOOL isCompleted;

+ (instancetype)subTaskWithTitle:(NSString *)title;

@end
