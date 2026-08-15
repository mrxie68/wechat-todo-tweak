#import "SubTaskItem.h"

@implementation SubTaskItem

+ (instancetype)subTaskWithTitle:(NSString *)title {
    SubTaskItem *s = [[SubTaskItem alloc] init];
    s.identifier = [NSUUID UUID].UUIDString;
    s.title = title;
    s.isCompleted = NO;
    return s;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _identifier = [coder decodeObjectOfClass:[NSString class] forKey:@"identifier"];
        _title = [coder decodeObjectOfClass:[NSString class] forKey:@"title"] ?: @"";
        _isCompleted = [coder decodeBoolForKey:@"isCompleted"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.identifier ?: @"" forKey:@"identifier"];
    [coder encodeObject:self.title ?: @"" forKey:@"title"];
    [coder encodeBool:self.isCompleted forKey:@"isCompleted"];
}

@end
