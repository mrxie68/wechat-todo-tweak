#import "AITodoManager.h"
#import "AISettings.h"
#import "AIConfig.h"

static NSString * const kAITodoListKey = @"WeChatAITodoList_";

@implementation AITodoManager

+ (NSString *)todoListKey {
    NSString *acc = [AISettings currentAccount];
    if (acc.length == 0) return kAITodoListKey;
    return [kAITodoListKey stringByAppendingString:acc];
}

+ (NSMutableArray *)loadTodos {
    NSMutableArray *list = [[[NSUserDefaults standardUserDefaults]
                             arrayForKey:[self todoListKey]] mutableCopy];
    return list ?: [NSMutableArray array];
}

+ (void)saveTodos:(NSArray *)todos {
    [[NSUserDefaults standardUserDefaults] setObject:todos forKey:[self todoListKey]];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSArray<NSDictionary *> *)allTodos {
    return [self loadTodos];
}

+ (NSUInteger)unfinishedCount {
    NSUInteger n = 0;
    for (NSDictionary *t in [self loadTodos]) {
        if (![t[@"done"] boolValue]) n++;
    }
    return n;
}

+ (NSString *)usageText {
    return @"📋 待办事项用法：\n直接发文字 = 记一条待办\n“待办/列表” = 查看未完成\n“完成 1” = 勾选完成\n“取消 1” = 标回未完成\n“删除 1” = 删除\n“历史” = 查看全部\n“同步” = 同步到 Memos\n“帮助” = 显示这个";
}

// 解析“完成/取消/删除 数字”
+ (BOOL)parseNumberAfter:(NSString *)prefix inText:(NSString *)text value:(NSInteger *)value {
    if (text.length <= prefix.length) return NO;
    if (![text hasPrefix:prefix]) return NO;
    NSString *tail = [text substringFromIndex:prefix.length];
    tail = [tail stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (tail.length == 0) return NO;
    NSInteger v = 0;
    BOOL any = NO;
    for (NSUInteger i = 0; i < tail.length; i++) {
        unichar ch = [tail characterAtIndex:i];
        if (ch >= '0' && ch <= '9') {
            v = v * 10 + (ch - '0');
            any = YES;
        } else {
            break;
        }
    }
    if (any && value) *value = v;
    return any;
}

+ (NSString *)listText {
    NSMutableArray *list = [self loadTodos];
    NSMutableArray *unfinished = [NSMutableArray array];
    for (NSDictionary *t in list) {
        if (![t[@"done"] boolValue]) [unfinished addObject:t];
    }
    if (unfinished.count == 0) return @"📋 暂无待办，直接发文字就能记一条。";
    NSMutableString *s = [NSMutableString stringWithFormat:@"📋 待办（%lu 条未完成）", (unsigned long)unfinished.count];
    for (NSDictionary *t in unfinished) {
        [s appendFormat:@"\n%@. %@", t[@"id"], t[@"content"]];
    }
    return s;
}

+ (NSString *)historyText {
    NSArray *list = [self loadTodos];
    if (list.count == 0) return @"还没有任何待办记录。";
    NSMutableString *s = [NSMutableString stringWithFormat:@"🗂 全部记录（%lu 条）", (unsigned long)list.count];
    for (NSDictionary *t in list) {
        BOOL done = [t[@"done"] boolValue];
        [s appendFormat:@"\n%@ %@. %@%@", done ? @"✅" : @"⬜", t[@"id"], t[@"content"],
         done ? @"（已完成）" : @""];
    }
    return s;
}

+ (NSString *)addTodo:(NSString *)content {
    NSMutableArray *list = [self loadTodos];
    NSInteger nextId = 1;
    for (NSDictionary *t in list) {
        NSInteger tid = [t[@"id"] integerValue];
        if (tid >= nextId) nextId = tid + 1;
    }
    [list addObject:@{
        @"id": @(nextId),
        @"content": content,
        @"created": @([[NSDate date] timeIntervalSince1970]),
        @"done": @NO,
        @"doneAt": @0,
    }];
    [self saveTodos:list];
    // 同步到 Memos（后台异步、尽力而为，失败不影响本地）
    [self syncToMemosAsync];
    return [NSString stringWithFormat:@"✅ 已记录 #%ld：%@\n（回复“待办”可查看，发“帮助”看全部命令）",
            (long)nextId, content];
}

+ (NSString *)markTodo:(NSInteger)todoId done:(BOOL)done {
    NSMutableArray *list = [self loadTodos];
    for (NSDictionary *t in list) {
        if ([t[@"id"] integerValue] == todoId) {
            NSMutableDictionary *m = [t mutableCopy];
            m[@"done"] = @(done);
            m[@"doneAt"] = @([[NSDate date] timeIntervalSince1970]);
            [list replaceObjectAtIndex:[list indexOfObject:t] withObject:m];
            [self saveTodos:list];
            if (done) [self syncToMemosAsync];
            return done
                ? [NSString stringWithFormat:@"✅ #%ld 已完成：%@", (long)todoId, t[@"content"]]
                : [NSString stringWithFormat:@"↩️ #%ld 已标回未完成：%@", (long)todoId, t[@"content"]];
        }
    }
    return [NSString stringWithFormat:@"⚠️ 没有找到 #%ld", (long)todoId];
}

+ (NSString *)deleteTodo:(NSInteger)todoId {
    NSMutableArray *list = [self loadTodos];
    for (NSDictionary *t in list) {
        if ([t[@"id"] integerValue] == todoId) {
            [list removeObject:t];
            [self saveTodos:list];
            return [NSString stringWithFormat:@"🗑 已删除 #%ld：%@", (long)todoId, t[@"content"]];
        }
    }
    return [NSString stringWithFormat:@"⚠️ 没有找到 #%ld", (long)todoId];
}

+ (NSString *)clearDone {
    NSMutableArray *list = [self loadTodos];
    NSMutableArray *kept = [NSMutableArray array];
    NSUInteger removed = 0;
    for (NSDictionary *t in list) {
        if ([t[@"done"] boolValue]) {
            removed++;
        } else {
            [kept addObject:t];
        }
    }
    [self saveTodos:kept];
    return removed > 0
        ? [NSString stringWithFormat:@"🧹 已清空 %lu 条已完成记录", (unsigned long)removed]
        : @"没有已完成的记录可清空。";
}

+ (NSString *)handleCommand:(NSString *)text {
    NSString *t = [text stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length == 0) return [self usageText];
    NSString *lower = [t lowercaseString];

    if ([t isEqualToString:@"帮助"] || [t isEqualToString:@"?"] ||
        [lower isEqualToString:@"help"]) {
        return [self usageText];
    }
    if ([t isEqualToString:@"待办"] || [t isEqualToString:@"列表"] ||
        [lower isEqualToString:@"list"]) {
        return [self listText];
    }
    if ([t isEqualToString:@"历史"] || [t isEqualToString:@"全部"] ||
        [lower isEqualToString:@"history"]) {
        return [self historyText];
    }
    if ([t isEqualToString:@"清空"] || [t isEqualToString:@"清空已完成"]) {
        return [self clearDone];
    }
    if ([t isEqualToString:@"同步"] || [lower isEqualToString:@"sync"]) {
        return [self syncToMemosNow];
    }

    NSInteger num = 0;
    if ([self parseNumberAfter:@"完成" inText:t value:&num] && num > 0) {
        return [self markTodo:num done:YES];
    }
    if ([self parseNumberAfter:@"取消" inText:t value:&num] && num > 0) {
        return [self markTodo:num done:NO];
    }
    if ([self parseNumberAfter:@"删除" inText:t value:&num] && num > 0) {
        return [self deleteTodo:num];
    }

    // 其余都当作新增
    if (t.length >= 2) {
        return [self addTodo:t];
    }
    return [self usageText];
}

// ===== Memos 同步（尽力而为：失败不影响本地） =====

+ (NSString *)memosBaseURL {
    NSString *url = [AISettings memosURL];
    url = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (url.length == 0) return @"";
    if ([url hasSuffix:@"/"]) url = [url substringToIndex:url.length - 1];
    return url;
}

// 后台异步同步（聊天流程里调用，不阻塞主线程）
+ (void)syncToMemosAsync {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSString *result = [self syncToMemosNow];
        NSLog(kAITodoLogPrefix "Memos 后台同步结果: %@", result);
    });
}

+ (NSString *)syncToMemosNow {
    NSString *base = [self memosBaseURL];
    NSString *token = [AISettings memosToken];
    if (base.length == 0) {
        return @"⚠️ 还没配置 Memos 地址：设置页 → 待办事项 → Memos 地址。";
    }
    if (token.length == 0) {
        return @"⚠️ 还没配置 Access Token：设置页 → 待办事项 → Token。";
    }

    NSMutableArray *list = [self loadTodos];
    NSMutableArray *unfinished = [NSMutableArray array];
    for (NSDictionary *t in list) {
        if (![t[@"done"] boolValue]) {
            [unfinished addObject:t[@"content"]];
        }
    }
    if (unfinished.count == 0) {
        return @"暂无未完成待办可同步。";
    }

    NSString *urlStr = [base stringByAppendingString:@"/api/v1/memos"];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        return @"⚠️ Memos 地址格式不对，IPv6 请用 http://[地址]:端口 的格式。";
    }

    __block NSInteger okCount = 0;
    __block NSInteger failCount = 0;
    __block BOOL done = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSString *visibility = [AISettings memosVisibility];

    for (NSString *content in unfinished) {
        NSString *memoContent = [NSString stringWithFormat:@"📌 待办：%@", content];
        NSDictionary *body = @{
            @"content": memoContent,
            @"visibility": visibility,
        };
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token]
       forHTTPHeaderField:@"Authorization"];
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        [request setTimeoutInterval:10];

        [[NSURLSession sharedSession] dataTaskWithRequest:request
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
        }] resume];
    }
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    if (!done) {
        return @"⏳ Memos 同步超时，请检查地址和网络（IPv6 是否可达）。";
    }
    return [NSString stringWithFormat:@"☁️ Memos 同步完成：成功 %ld 条，失败 %ld 条。",
            (long)okCount, (long)failCount];
}

@end
