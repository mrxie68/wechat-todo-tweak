#import "MainTodoItem.h"

@implementation MainTodoItem

- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = 0;
        _title = @"";
        _createTime = [NSDate date];
        _subTasks = [NSMutableArray array];
        _isSelected = NO;
        _isBookmarked = NO;
        _done = NO;
    }
    return self;
}

- (BOOL)hasSubtasks {
    return self.subTasks.count > 0;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _identifier = [[coder decodeObjectOfClass:[NSNumber class] forKey:@"identifier"] integerValue];
        _title = [coder decodeObjectOfClass:[NSString class] forKey:@"title"] ?: @"";
        _createTime = [coder decodeObjectOfClass:[NSDate class] forKey:@"createTime"] ?: [NSDate date];
        NSSet *subClasses = [NSSet setWithObjects:[NSArray class], [NSMutableArray class], [SubTaskItem class], nil];
        NSArray *subs = [coder decodeObjectOfClasses:subClasses forKey:@"subTasks"];
        _subTasks = [NSMutableArray arrayWithArray:subs ?: @[]];
        _isBookmarked = [coder decodeBoolForKey:@"isBookmarked"];
        _done = [coder decodeBoolForKey:@"done"];
        _doneAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"doneAt"];
        _note = [coder decodeObjectOfClass:[NSString class] forKey:@"note"];
        _dueDate = [coder decodeObjectOfClass:[NSDate class] forKey:@"dueDate"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:@(self.identifier) forKey:@"identifier"];
    [coder encodeObject:self.title ?: @"" forKey:@"title"];
    [coder encodeObject:self.createTime ?: [NSDate date] forKey:@"createTime"];
    [coder encodeObject:self.subTasks ?: @[] forKey:@"subTasks"];
    [coder encodeBool:self.isBookmarked forKey:@"isBookmarked"];
    [coder encodeBool:self.done forKey:@"done"];
    [coder encodeObject:self.doneAt forKey:@"doneAt"];
    [coder encodeObject:self.note forKey:@"note"];
    [coder encodeObject:self.dueDate forKey:@"dueDate"];
}

@end
