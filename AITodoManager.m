#import "AITodoManager.h"
#import "AISettings.h"
#import "AIConfig.h"

static NSString * const kAITodoOldListKey = @"WeChatAITodoList_";
static NSString * const kAITodoModelListKey = @"WeChatTodoModels_";

@implementation AITodoManager

+ (NSString *)oldListKey {
    NSString *acc = [AISettings currentAccount];
    if (acc.length == 0) return kAITodoOldListKey;
    return [kAITodoOldListKey stringByAppendingString:acc];
}

+ (NSString *)modelListKey {
    NSString *acc = [AISettings currentAccount];
    if (acc.length == 0) return kAITodoModelListKey;
    return [kAITodoModelListKey stringByAppendingString:acc];
}

+ (NSMutableArray<MainTodoItem *> *)loadTodos {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSData *data = [defaults dataForKey:[self modelListKey]];
    if (data) {
        @try {
            NSSet *classes = [NSSet setWithObjects:[NSArray class], [NSMutableArray class],
                              [MainTodoItem class], [SubTaskItem class], nil];
            NSError *err = nil;
            NSArray *arr = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:&err];
            if (arr) {
                return [NSMutableArray arrayWithArray:arr];
            }
            NSLog(kAITodoLogPrefix "模型反序列化失败: %@", err);
        } @catch (NSException *e) {
            NSLog(kAITodoLogPrefix "模型反序列化异常: %@", e);
        }
    }
    // 迁移旧版字典数据
    NSArray *old = [defaults arrayForKey:[self oldListKey]];
    NSMutableArray *models = [NSMutableArray array];
    for (NSDictionary *t in old ?: @[]) {
        MainTodoItem *m = [[MainTodoItem alloc] init];
        m.identifier = [t[@"id"] integerValue];
        m.title = t[@"content"] ?: @"";
        double created = [t[@"created"] doubleValue];
        m.createTime = created > 0 ? [NSDate dateWithTimeIntervalSince1970:created] : [NSDate date];
        m.done = [t[@"done"] boolValue];
        double doneAt = [t[@"doneAt"] doubleValue];
        m.doneAt = doneAt > 0 ? [NSDate dateWithTimeIntervalSince1970:doneAt] : nil;
        m.note = t[@"note"];
        double due = [t[@"due"] doubleValue];
        m.dueDate = due > 0 ? [NSDate dateWithTimeIntervalSince1970:due] : nil;
        m.isBookmarked = [t[@"important"] boolValue];
        m.subTasks = [NSMutableArray array];
        [models addObject:m];
    }
    [self saveTodos:models];
    return models;
}

+ (BOOL)saveTodos:(NSArray<MainTodoItem *> *)todos {
    @try {
        NSError *error = nil;
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:todos
                                             requiringSecureCoding:YES
                                                             error:&error];
        if (data) {
            [[NSUserDefaults standardUserDefaults] setObject:data forKey:[self modelListKey]];
            [[NSUserDefaults standardUserDefaults] synchronize];
            return YES;
        } else {
            NSLog(kAITodoLogPrefix "保存失败: %@", error);
        }
    } @catch (NSException *e) {
        NSLog(kAITodoLogPrefix "保存异常: %@", e);
    }
    return NO;
}

+ (MainTodoItem *)todoWithId:(NSInteger)todoId inList:(NSArray *)list {
    for (MainTodoItem *m in list) {
        if (m.identifier == todoId) return m;
    }
    return nil;
}

+ (NSArray<MainTodoItem *> *)allTodos {
    NSArray *list = [self loadTodos];
    return [list sortedArrayUsingComparator:^NSComparisonResult(MainTodoItem *a, MainTodoItem *b) {
        if (a.identifier > b.identifier) return NSOrderedAscending;
        if (a.identifier < b.identifier) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

+ (NSUInteger)unfinishedCount {
    NSUInteger n = 0;
    for (MainTodoItem *m in [self loadTodos]) {
        if (!m.done) n++;
    }
    return n;
}

+ (MainTodoItem *)addTodo:(NSString *)content {
    return [self addTodo:content atDate:[NSDate date]];
}

+ (MainTodoItem *)addTodo:(NSString *)content atDate:(NSDate *)date {
    NSMutableArray *list = [self loadTodos];
    NSInteger nextId = 1;
    for (MainTodoItem *m in list) {
        if (m.identifier >= nextId) nextId = m.identifier + 1;
    }
    MainTodoItem *item = [[MainTodoItem alloc] init];
    item.identifier = nextId;
    item.title = content;
    item.createTime = date ?: [NSDate date];
    [list addObject:item];
    if (![self saveTodos:list]) return nil;
    [self syncToMemosAsync];
    return item;
}

+ (BOOL)markTodo:(NSInteger)todoId done:(BOOL)done {
    NSMutableArray *list = [self loadTodos];
    MainTodoItem *m = [self todoWithId:todoId inList:list];
    if (!m) return NO;
    m.done = done;
    m.doneAt = done ? [NSDate date] : nil;
    [self saveTodos:list];
    if (done) [self syncToMemosAsync];
    return YES;
}

+ (BOOL)deleteTodo:(NSInteger)todoId {
    NSMutableArray *list = [self loadTodos];
    MainTodoItem *m = [self todoWithId:todoId inList:list];
    if (!m) return NO;
    [list removeObject:m];
    [self saveTodos:list];
    return YES;
}

+ (BOOL)updateTodo:(NSInteger)todoId title:(NSString *)title note:(NSString *)note
                due:(NSDate *)due bookmarked:(BOOL)bookmarked {
    NSMutableArray *list = [self loadTodos];
    MainTodoItem *m = [self todoWithId:todoId inList:list];
    if (!m) return NO;
    NSString *trimmed = [title stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length > 0) m.title = trimmed;
    NSString *trimmedNote = [note stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    m.note = trimmedNote.length > 0 ? trimmedNote : nil;
    m.dueDate = due;
    m.isBookmarked = bookmarked;
    [self saveTodos:list];
    return YES;
}

+ (BOOL)addSubTask:(NSString *)subTitle toTodo:(NSInteger)todoId {
    NSString *trimmed = [subTitle stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return NO;
    NSMutableArray *list = [self loadTodos];
    MainTodoItem *m = [self todoWithId:todoId inList:list];
    if (!m) return NO;
    [m.subTasks addObject:[SubTaskItem subTaskWithTitle:trimmed]];
    [self saveTodos:list];
    return YES;
}

+ (BOOL)toggleSubTask:(NSString *)subId inTodo:(NSInteger)todoId {
    NSMutableArray *list = [self loadTodos];
    MainTodoItem *m = [self todoWithId:todoId inList:list];
    if (!m) return NO;
    for (SubTaskItem *s in m.subTasks) {
        if ([s.identifier isEqualToString:subId]) {
            s.isCompleted = !s.isCompleted;
            [self saveTodos:list];
            return YES;
        }
    }
    return NO;
}

+ (BOOL)setTodo:(NSInteger)todoId selected:(BOOL)selected {
    NSMutableArray *list = [self loadTodos];
    MainTodoItem *m = [self todoWithId:todoId inList:list];
    if (!m) return NO;
    m.isSelected = selected;
    [self saveTodos:list];
    return YES;
}

+ (BOOL)toggleBookmarkForTodo:(NSInteger)todoId {
    NSMutableArray *list = [self loadTodos];
    MainTodoItem *m = [self todoWithId:todoId inList:list];
    if (!m) return NO;
    m.isBookmarked = !m.isBookmarked;
    [self saveTodos:list];
    return YES;
}

+ (NSUInteger)clearDone {
    NSMutableArray *list = [self loadTodos];
    NSMutableArray *kept = [NSMutableArray array];
    NSUInteger removed = 0;
    for (MainTodoItem *m in list) {
        if (m.done) removed++;
        else [kept addObject:m];
    }
    [self saveTodos:kept];
    return removed;
}

+ (NSArray<MainTodoItem *> *)todosOnDay:(NSDate *)day {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *start = [cal startOfDayForDate:day];
    NSDate *end = [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:start options:0];
    NSMutableArray *out = [NSMutableArray array];
    for (MainTodoItem *m in [self loadTodos]) {
        if ([m.createTime compare:start] != NSOrderedAscending &&
            [m.createTime compare:end] == NSOrderedAscending) {
            [out addObject:m];
        }
    }
    [out sortUsingComparator:^NSComparisonResult(MainTodoItem *a, MainTodoItem *b) {
        return [a.createTime compare:b.createTime];
    }];
    return out;
}

// ===== Memos 同步（尽力而为：失败不影响本地） =====

+ (NSString *)memosBaseURL {
    NSString *url = [AISettings memosURL];
    url = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (url.length == 0) return @"";
    if ([url hasSuffix:@"/"]) url = [url substringToIndex:url.length - 1];
    return url;
}

+ (void)syncToMemosAsync {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSString *result = [self syncToMemosNow];
        NSLog(kAITodoLogPrefix "Memos 后台同步结果: %@", result);
    });
}

+ (NSString *)syncToMemosNow {
    NSString *base = [self memosBaseURL];
    NSString *token = [AISettings memosToken];
    if (base.length == 0) return @"⚠️ 还没配置 Memos 地址：设置 → Memos 地址。";
    if (token.length == 0) return @"⚠️ 还没配置 Access Token：设置 → Token。";

    NSMutableArray *unfinished = [NSMutableArray array];
    for (MainTodoItem *m in [self loadTodos]) {
        if (!m.done) [unfinished addObject:m.title];
    }
    if (unfinished.count == 0) return @"暂无未完成待办可同步。";

    NSString *urlStr = [base stringByAppendingString:@"/api/v1/memos"];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return @"⚠️ Memos 地址格式不对，IPv6 请用 http://[地址]:端口 的格式。";

    __block NSInteger okCount = 0;
    __block NSInteger failCount = 0;
    __block BOOL done = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSString *visibility = [AISettings memosVisibility];

    for (NSString *content in unfinished) {
        NSString *memoContent = [NSString stringWithFormat:@"📌 待办：%@", content];
        NSDictionary *body = @{ @"content": memoContent, @"visibility": visibility };
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token]
       forHTTPHeaderField:@"Authorization"];
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        [request setTimeoutInterval:10];
        NSURLSessionDataTask *task = [[NSURLSession sharedSession]
                                      dataTaskWithRequest:request
                                      completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
            if (!err && http.statusCode >= 200 && http.statusCode < 300) {
                okCount++;
            } else {
                failCount++;
                NSLog(kAITodoLogPrefix "Memos 同步失败: %@ (%ld)",
                      err ?: @"非2xx", (long)http.statusCode);
            }
            if (okCount + failCount == unfinished.count) {
                done = YES;
                dispatch_semaphore_signal(sem);
            }
        }];
        [task resume];
    }
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    if (!done) return @"⏳ Memos 同步超时，请检查地址和网络（IPv6 是否可达）。";
    return [NSString stringWithFormat:@"☁️ Memos 同步完成：成功 %ld 条，失败 %ld 条。",
            (long)okCount, (long)failCount];
}

@end
