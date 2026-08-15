#import <Foundation/Foundation.h>

// 子任务模型
@interface SubTaskItem : NSObject <NSCoding>

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) BOOL isCompleted;

+ (instancetype)subTaskWithTitle:(NSString *)title;

@end
