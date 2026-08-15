//
//  WeChatTodoTweak.m
//  待办事项插件（微信 + Memos）
//
//  纯 Objective-C 运行时实现，不依赖 CydiaSubstrate / Theos：
//    - TrollStore + TrollFools 直接注入微信
//    - 越狱环境放进 DynamicLibraries 由 MobileSubstrate 加载
//
//  v0.2.0：改为「主界面底部上滑 → 全屏待办页」，
//          移除 todo@local 假联系人方案，启动时一次性清理旧假联系人残留。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdarg.h>
#import <string.h>
#import <sqlite3.h>
#import <CommonCrypto/CommonDigest.h>
#import "AIConfig.h"
#import "AISettings.h"
#import "AITodoManager.h"
#import "TodoPageViewController.h"

#pragma mark - 微信私有接口声明

@interface MMServiceCenter : NSObject
+ (instancetype)defaultCenter;
- (id)getService:(Class)cls;
@end

@interface CContactMgr : NSObject
- (id)getSelfContact;
@end

// 声明属性是为了让编译器认识 m_nsUsrName selector（ARC 下 id 收件人必须能推断返回类型）
@interface CContact : NSObject
@property (nonatomic, retain) NSString *m_nsUsrName;
@end

@interface SettingUtil : NSObject
+ (NSString *)getCurUsrName;
@end

@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title
                            version:(NSString *)version
                         controller:(NSString *)controller;
@end

@interface MMNewSessionMgr : NSObject
- (void)DeleteSessionOfUser:(NSString *)userName;
@end

@interface MainSessionMgr : NSObject
- (void)updateMainSessionList;
- (NSArray *)normalSessions;
- (void)setNormalSessions:(NSArray *)sessions;
@end

#pragma mark - 基础工具

static NSString *aiMD5Hex(NSString *input) {
    const char *cStr = [input UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), digest);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

static BOOL aiIsSQLiteFile(NSString *path) {
    FILE *f = fopen([path UTF8String], "rb");
    if (!f) return NO;
    char buf[16];
    size_t n = fread(buf, 1, 16, f);
    fclose(f);
    return n == 16 && memcmp(buf, "SQLite format 3", 16) == 0;
}

static NSArray *aiSQLiteTableNames(sqlite3 *db) {
    NSMutableArray *tables = [NSMutableArray array];
    sqlite3_stmt *stmt = NULL;
    const char *sql = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name";
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const unsigned char *t = sqlite3_column_text(stmt, 0);
            if (t) [tables addObject:[NSString stringWithUTF8String:(const char *)t]];
        }
    }
    sqlite3_finalize(stmt);
    return tables;
}

static NSArray *aiSQLiteColumns(sqlite3 *db, NSString *table) {
    NSMutableArray *cols = [NSMutableArray array];
    NSString *safe = [table stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
    NSString *sql = [NSString stringWithFormat:@"PRAGMA table_info(\"%@\")", safe];
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const unsigned char *c = sqlite3_column_text(stmt, 1);
            if (c) [cols addObject:[NSString stringWithUTF8String:(const char *)c]];
        }
    }
    sqlite3_finalize(stmt);
    return cols;
}

// 从列名列表里按候选名匹配一列（支持多种命名变体）
static NSString *aiPickColumnName(NSArray *cols, NSArray *candidates) {
    for (NSString *c in candidates) {
        for (NSString *col in cols) {
            if ([col isEqualToString:c]) return col;
        }
    }
    return nil;
}

static NSString *wechatSelfUsrName(void) {
    Class centerCls = NSClassFromString(@"MMServiceCenter");
    if (!centerCls) return nil;
    id center = [(id)centerCls defaultCenter];
    if (!center) return nil;
    id contactMgr = [center getService:NSClassFromString(@"CContactMgr")];
    NSString *usrName = nil;
    if ([contactMgr respondsToSelector:@selector(getSelfContact)]) {
        id selfContact = [contactMgr getSelfContact];
        if ([selfContact respondsToSelector:@selector(m_nsUsrName)]) {
            usrName = [selfContact m_nsUsrName];
        }
    }
    if (usrName.length == 0) {
        Class settingUtil = NSClassFromString(@"SettingUtil");
        if (settingUtil && [settingUtil respondsToSelector:@selector(getCurUsrName)]) {
            usrName = [(id)settingUtil getCurUsrName];
        }
    }
    return usrName;
}

static NSArray *aiFindDatabaseFiles(void) {
    NSMutableArray *files = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *home = NSHomeDirectory();
    NSMutableArray *roots = [NSMutableArray array];
    NSString *selfUsr = wechatSelfUsrName();
    NSString *documents = [home stringByAppendingPathComponent:@"Documents"];
    if (selfUsr.length > 0) {
        NSString *accountDir = [documents stringByAppendingPathComponent:aiMD5Hex(selfUsr)];
        if ([fm fileExistsAtPath:accountDir]) [roots addObject:accountDir];
    }
    if (roots.count == 0) [roots addObject:documents];
    [roots addObject:[home stringByAppendingPathComponent:@"Library/Application Support"]];
    for (NSString *root in roots) {
        if (![fm fileExistsAtPath:root]) continue;
        NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
        int scanned = 0;
        for (NSString *rel in en) {
            if (++scanned > 30000) break;
            NSString *ext = rel.pathExtension.lowercaseString;
            if (!([ext isEqualToString:@"sqlite"] || [ext isEqualToString:@"sqlite3"] ||
                  [ext isEqualToString:@"db"])) continue;
            NSString *full = [root stringByAppendingPathComponent:rel];
            if (!aiIsSQLiteFile(full)) continue;
            NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
            [files addObject:@{@"path": full, @"size": attrs[NSFileSize] ?: @0}];
            if (files.count >= 100) break;
        }
    }
    [files sortUsingComparator:^NSComparisonResult(id a, id b) {
        NSString *ar = a[@"path"], *br = b[@"path"];
        BOOL aSession = [ar.lowercaseString rangeOfString:@"session"].location != NSNotFound;
        BOOL bSession = [br.lowercaseString rangeOfString:@"session"].location != NSNotFound;
        if (aSession != bSession) return aSession ? NSOrderedAscending : NSOrderedDescending;
        return [b[@"size"] compare:a[@"size"]];
    }];
    if (files.count > 100) {
        files = [[files subarrayWithRange:NSMakeRange(0, 100)] mutableCopy];
    }
    return files;
}

static UIViewController *tweakTopViewController(void) {
    UIWindow *window = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { window = w; break; }
    }
    if (!window) window = [UIApplication sharedApplication].windows.firstObject;
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

// 找到聊天列表主界面 VC（NewMainFrameViewController，BFS 全窗口层级）
static UIViewController *findNewMainFrameVC(void) {
    NSMutableArray *queue = [NSMutableArray array];
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.rootViewController) [queue addObject:w.rootViewController];
    }
    NSMutableSet *visited = [NSMutableSet set];
    while (queue.count > 0) {
        UIViewController *vc = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (!vc) continue;
        NSNumber *mark = @((uintptr_t)vc);
        if ([visited containsObject:mark]) continue;
        [visited addObject:mark];
        if ([NSStringFromClass([vc class]) rangeOfString:@"NewMainFrame"].location != NSNotFound) {
            return vc;
        }
        [queue addObjectsFromArray:vc.childViewControllers];
        if (vc.presentedViewController) [queue addObject:vc.presentedViewController];
    }
    return nil;
}

// 强制刷新聊天列表表格（找到 UITableView 后 reloadData）
static BOOL reloadMainFrameTable(void) {
    UIViewController *mvc = findNewMainFrameVC();
    if (!mvc) return NO;
    NSMutableArray *queue = [NSMutableArray arrayWithObject:mvc.view];
    while (queue.count > 0) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:[UITableView class]]) {
            [(UITableView *)v reloadData];
            return YES;
        }
        [queue addObjectsFromArray:v.subviews];
    }
    return NO;
}

#pragma mark - 旧 todo@local 假联系人清理（一次性，只删本机假联系人，不碰其他数据）

// 数据库层：删联系人表 + SessionTable 里 todo@local 的行
static void cleanupTodoContactInDB(NSString *selfUsr) {
    if (selfUsr.length == 0) return;
    NSString *md5 = aiMD5Hex(selfUsr);
    NSArray *dbs = aiFindDatabaseFiles();
    for (NSDictionary *d in dbs) {
        NSString *path = d[@"path"];
        if (md5.length > 0 && [path rangeOfString:md5].location == NSNotFound) continue;
        sqlite3 *db = NULL;
        if (sqlite3_open_v2([path UTF8String], &db,
                            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
            if (db) sqlite3_close(db);
            continue;
        }
        sqlite3_busy_timeout(db, 3000);
        NSArray *tables = aiSQLiteTableNames(db);
        for (NSString *tbl in tables) {
            NSString *lower = tbl.lowercaseString;
            BOOL isContact = [lower rangeOfString:@"contact"].location != NSNotFound;
            BOOL isSession = [tbl isEqualToString:@"SessionTable"];
            if (!isContact && !isSession) continue;
            NSArray *cols = aiSQLiteColumns(db, tbl);
            NSString *keyCol = nil;
            if (isSession) {
                if ([cols containsObject:@"sessionId"]) keyCol = @"sessionId";
            } else {
                keyCol = aiPickColumnName(cols, @[@"UserName", @"userName", @"username",
                                                  @"m_nsUserName", @"usrName", @"m_nsUsrName"]);
            }
            if (!keyCol) continue;
            NSString *sql = [NSString stringWithFormat:
                             @"DELETE FROM \"%@\" WHERE \"%@\" = ?", tbl, keyCol];
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, [kAITodoChatId UTF8String], -1, SQLITE_TRANSIENT);
                sqlite3_step(stmt);
            }
            sqlite3_finalize(stmt);
        }
        sqlite3_close(db);
    }
}

// 内存层：删会话 + 从主界面会话数组移除 + 刷新列表（必须在主线程）
static void cleanupTodoContactInMemory(void) {
    Class centerCls = NSClassFromString(@"MMServiceCenter");
    if (!centerCls) return;
    id center = [(id)centerCls defaultCenter];
    if (!center) return;

    id newMgr = [center getService:NSClassFromString(@"MMNewSessionMgr")];
    if ([newMgr respondsToSelector:@selector(DeleteSessionOfUser:)]) {
        @try { [newMgr DeleteSessionOfUser:kAITodoChatId]; } @catch (NSException *e) {}
    }

    Class mainCls = NSClassFromString(@"MainSessionMgr");
    id mainMgr = mainCls ? [center getService:mainCls] : nil;
    if ([mainMgr respondsToSelector:@selector(normalSessions)] &&
        [mainMgr respondsToSelector:@selector(setNormalSessions:)]) {
        NSArray *normal = [mainMgr normalSessions];
        NSMutableArray *kept = [NSMutableArray array];
        for (id s in normal) {
            NSString *uname = nil;
            @try { uname = [s valueForKey:@"m_nsUserName"]; } @catch (NSException *e) {}
            if ([uname isEqualToString:kAITodoChatId]) continue;
            [kept addObject:s];
        }
        if (kept.count != normal.count) {
            @try { [mainMgr setNormalSessions:kept]; } @catch (NSException *e) {}
        }
    }
    if ([mainMgr respondsToSelector:@selector(updateMainSessionList)]) {
        @try { [mainMgr updateMainSessionList]; } @catch (NSException *e) {}
    }
    (void)reloadMainFrameTable();
}

// 每个账号只清理一次，清理成功后再也不扫库
static void runTodoContactCleanupOnce(void) {
    NSString *selfUsr = wechatSelfUsrName();
    if (selfUsr.length == 0) return;
    NSString *flagKey = [@"WeChatTodoCleanupV2_" stringByAppendingString:selfUsr];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:flagKey]) return;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        @try {
            cleanupTodoContactInDB(selfUsr);
        } @catch (NSException *e) {
            NSLog(kAITodoLogPrefix "清理假联系人数据库异常: %@", e);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                cleanupTodoContactInMemory();
            } @catch (NSException *e) {
                NSLog(kAITodoLogPrefix "清理假联系人内存异常: %@", e);
            }
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:flagKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
        });
    });
}

#pragma mark - 主界面判断 + 底部上滑呼出待办页

static UIWindow *g_todoWindow = nil;
static UIButton *g_todoHint = nil;
static BOOL g_todoPanTriggered = NO;
static BOOL g_gestureInstalled = NO;

static NSObject *g_diagLock = nil;
static NSMutableArray *g_diagEvents = nil;

static void diagLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    @synchronized (g_diagLock) {
        if (!g_diagEvents) g_diagEvents = [NSMutableArray array];
        [g_diagEvents addObject:msg];
        while (g_diagEvents.count > 40) {
            [g_diagEvents removeObjectAtIndex:0];
        }
    }
    NSLog(kAITodoLogPrefix "%@", msg);
}

// 找到底部 tab 栏容器（类名含 TaskBar/TabBar 且贴近窗口底部）
static UIView *findBottomTabContainer(UIWindow *window) {
    if (!window) return nil;
    NSMutableArray *queue = [NSMutableArray arrayWithObject:window];
    int scanned = 0;
    while (queue.count > 0) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (++scanned > 30000) break;
        NSString *cls = NSStringFromClass([v class]);
        if ([cls rangeOfString:@"TaskBar"].location != NSNotFound ||
            [cls rangeOfString:@"TabBar"].location != NSNotFound) {
            CGRect f = [v convertRect:v.bounds toView:window];
            if (f.size.height >= 40 && f.size.height <= 110 && f.size.width > 100 &&
                f.origin.y + f.size.height >= window.bounds.size.height - 20) {
                return v;
            }
        }
        [queue addObjectsFromArray:v.subviews];
    }
    return nil;
}

// 从容器里找“一排等宽的 tab 项”（微信是 4 个，横向铺满容器）
static UIView *g_todoTabItemView = nil; // 我们自己加的“待办”tab（探测时跳过它）

static NSArray *findTabItemRow(UIView *container) {
    if (!container) return nil;
    CGFloat cw = container.bounds.size.width;
    if (cw <= 0) return nil;
    NSMutableArray *candidates = [NSMutableArray arrayWithObject:container];
    [candidates addObjectsFromArray:container.subviews];
    for (UIView *cand in candidates) {
        NSArray *subs = cand.subviews;
        if (subs.count < 4 || subs.count > 8) continue;
        NSMutableArray *items = [NSMutableArray array];
        for (UIView *s in subs) {
            if (s == g_todoTabItemView) continue; // 跳过我们自己加的 tab
            CGRect f = s.frame;
            if (f.size.width > cw / 8.0 && f.size.width < cw / 2.5 &&
                f.size.height >= 30 && f.origin.y >= -5 && f.origin.y < cand.bounds.size.height) {
                [items addObject:s];
            }
        }
        if (items.count != 4) continue;
        [items sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            if (a.frame.origin.x < b.frame.origin.x) return NSOrderedAscending;
            if (a.frame.origin.x > b.frame.origin.x) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        UIView *first = items[0];
        UIView *last = items[3];
        CGFloat expectW = cw / 4.0;
        BOOL ok = fabs(first.frame.origin.x - 0) <= cw * 0.05 &&
                  fabs(last.frame.origin.x + last.frame.size.width - cw) <= cw * 0.08 &&
                  fabs(first.frame.size.width - expectW) <= cw * 0.12;
        if (ok) return items;
    }
    return nil;
}

// 窗口视图层级里是否存在微信主界面的底部 tab 栏
static BOOL windowHasBottomBar(UIWindow *window) {
    return findBottomTabContainer(window) != nil;
}

static BOOL g_cachedMainVisible = NO;
static NSTimeInterval g_cachedMainTime = 0;

// 当前真正显示在最上层的控制器（走完 presented + 导航栈）
static UIViewController *visibleViewController(void) {
    UIViewController *vc = tweakTopViewController();
    while (vc) {
        if ([vc isKindOfClass:[UINavigationController class]]) {
            UIViewController *t = ((UINavigationController *)vc).topViewController;
            if (t && t != vc) {
                vc = t;
                continue;
            }
        }
        break;
    }
    return vc;
}

// 主界面是否可见：只有最上层就是主界面、且底部 tab 栏还在层级里才算。
// 自己的待办页/设置页、微信弹层、聊天页（tab 栏会被移除）都会自动排除，避免误触。
static BOOL isMainFrameVisible(void) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - g_cachedMainTime < 0.3) return g_cachedMainVisible;

    BOOL visible = NO;
    UIViewController *top = visibleViewController();
    if (top) {
        NSString *topCls = NSStringFromClass([top class]);
        if ([topCls rangeOfString:@"NewMainFrame"].location != NSNotFound ||
            [topCls rangeOfString:@"MainFrame"].location != NSNotFound) {
            UIWindow *window = g_todoWindow ?: [UIApplication sharedApplication].keyWindow;
            visible = windowHasBottomBar(window);
        }
    }
    g_cachedMainTime = now;
    g_cachedMainVisible = visible;
    return visible;
}

@interface TodoGestureTarget : NSObject <UIGestureRecognizerDelegate>
@end

static TodoGestureTarget *g_todoGestureTarget = nil;

@implementation TodoGestureTarget

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    // 只在主界面且触摸点在底部区域时参与识别
    BOOL mainVisible = isMainFrameVisible();
    CGPoint p = [touch locationInView:gestureRecognizer.view];
    CGRect b = gestureRecognizer.view.bounds;
    BOOL inZone = p.y >= b.size.height - 88.0;
    if (inZone) {
        diagLog(@"底部触摸 y=%.0f main=%d → %@", p.y, mainVisible,
                mainVisible ? @"参与识别" : @"跳过");
    }
    return mainVisible && inZone;
}

- (void)todoPan:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [pan translationInView:pan.view];
        // 上滑超过 50pt 且纵向为主，才算有效手势
        if (t.y < -50 && fabs(t.y) > fabs(t.x)) {
            g_todoPanTriggered = YES;
        }
    } else if (pan.state == UIGestureRecognizerStateEnded) {
        CGPoint t = [pan translationInView:pan.view];
        diagLog(@"pan 结束 t=(%.0f,%.0f) trigger=%d", t.x, t.y, g_todoPanTriggered);
        if (g_todoPanTriggered && t.y < -40) {
            [TodoPageViewController presentFrom:tweakTopViewController()];
        }
        g_todoPanTriggered = NO;
    } else if (pan.state != UIGestureRecognizerStatePossible) {
        g_todoPanTriggered = NO;
    }
    if (g_todoHint) {
        g_todoHint.hidden = !isMainFrameVisible();
    }
}

- (void)todoHintTapped {
    diagLog(@"提示条点击，打开待办页");
    [TodoPageViewController presentFrom:tweakTopViewController()];
}

- (void)todoTabTapped {
    diagLog(@"底部菜单「待办」tab 点击");
    [TodoPageViewController presentFrom:tweakTopViewController()];
}

@end

static void installTodoGestureAndHint(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_gestureInstalled) return;
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window) window = [UIApplication sharedApplication].windows.firstObject;
        if (!window) return;
        // 多窗口时优先选包含底部 tab 栏的主窗口
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (windowHasBottomBar(w)) { window = w; break; }
        }
        g_todoWindow = window;

        if (!g_todoGestureTarget) {
            g_todoGestureTarget = [[TodoGestureTarget alloc] init];
        }
        UIPanGestureRecognizer *pan =
            [[UIPanGestureRecognizer alloc] initWithTarget:g_todoGestureTarget
                                                    action:@selector(todoPan:)];
        pan.delegate = g_todoGestureTarget;
        [window addGestureRecognizer:pan];

        // 底部小按钮：点击也能打开待办页，同时作为上滑入口提示（不遮挡 tab 按钮）
        g_todoHint = [UIButton buttonWithType:UIButtonTypeSystem];
        [g_todoHint setTitle:@"⬆ 待办" forState:UIControlStateNormal];
        g_todoHint.titleLabel.font = [UIFont systemFontOfSize:11];
        g_todoHint.tintColor = [UIColor systemGrayColor];
        g_todoHint.backgroundColor = [UIColor systemGray6Color];
        g_todoHint.layer.cornerRadius = 11;
        g_todoHint.layer.borderColor = [UIColor systemGray4Color].CGColor;
        g_todoHint.layer.borderWidth = 0.5;
        [g_todoHint addTarget:g_todoGestureTarget
                       action:@selector(todoHintTapped)
             forControlEvents:UIControlEventTouchUpInside];
        [window addSubview:g_todoHint];
        [window bringSubviewToFront:g_todoHint];

        CGRect b = window.bounds;
        CGFloat bottomInset = 0;
        if (@available(iOS 11.0, *)) bottomInset = window.safeAreaInsets.bottom;
        CGFloat hintW = 66, hintH = 26;
        g_todoHint.frame = CGRectMake((b.size.width - hintW) / 2.0,
                                      b.size.height - bottomInset - 49.0 - hintH - 12.0,
                                      hintW, hintH);
        g_todoHint.autoresizingMask =
            UIViewAutoresizingFlexibleLeftMargin |
            UIViewAutoresizingFlexibleRightMargin |
            UIViewAutoresizingFlexibleTopMargin;
        g_todoHint.hidden = !isMainFrameVisible();
        g_gestureInstalled = YES;

        // 每秒刷新提示可见性（主界面显示时出现，进聊天/设置后隐藏）
        NSTimer *hintTimer = [NSTimer timerWithTimeInterval:1.0
                                                     repeats:YES
                                                       block:^(NSTimer *timer) {
            if (g_todoHint) g_todoHint.hidden = !isMainFrameVisible();
        }];
        [[NSRunLoop mainRunLoop] addTimer:hintTimer forMode:NSRunLoopCommonModes];

        diagLog(@"手势+提示条已安装 window=%@", NSStringFromClass([window class]));
    });
}

// 手势诊断（设置页按钮调用，结果复制到剪贴板）
static NSString *todoTabBarProbe(void); // 前向声明（定义在下方）

NSString *todoGestureDiagnostic(void) {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"待办插件 v%@ 手势诊断\n", kAITodoVersion];
    UIWindow *key = [UIApplication sharedApplication].keyWindow;
    [s appendFormat:@"keyWindow: %@\n", key ? NSStringFromClass([key class]) : @"无"];
    UIViewController *root = key ? key.rootViewController : nil;
    [s appendFormat:@"rootVC: %@\n", root ? NSStringFromClass([root class]) : @"无"];
    UIViewController *top = tweakTopViewController();
    [s appendFormat:@"topVC: %@\n", top ? NSStringFromClass([top class]) : @"无"];
    UIWindow *win = g_todoWindow ?: key;
    [s appendFormat:@"手势窗口: %@\n", win ? NSStringFromClass([win class]) : @"无"];
    [s appendFormat:@"底部栏可见: %@\n", windowHasBottomBar(win) ? @"是" : @"否"];
    [s appendFormat:@"主界面判定: %@\n", isMainFrameVisible() ? @"是" : @"否"];
    [s appendFormat:@"手势已安装: %@\n", g_gestureInstalled ? @"是" : @"否"];
    if (win) {
        NSMutableArray *queue = [NSMutableArray arrayWithObject:win];
        BOOL found = NO;
        while (queue.count > 0 && !found) {
            UIView *v = queue.firstObject;
            [queue removeObjectAtIndex:0];
            NSString *cls = NSStringFromClass([v class]);
            if ([cls rangeOfString:@"TaskBar"].location != NSNotFound ||
                [cls rangeOfString:@"TabBar"].location != NSNotFound) {
                [s appendFormat:@"底部栏类: %@\n", cls];
                found = YES;
                break;
            }
            [queue addObjectsFromArray:v.subviews];
        }
        if (!found) [s appendString:@"底部栏类: 未找到\n"];
    }
    @synchronized (g_diagLock) {
        [s appendString:@"\n事件日志（最近40条）:\n"];
        for (NSString *e in g_diagEvents) {
            [s appendFormat:@"%@\n", e];
        }
    }
    [s appendString:@"\n== 底部菜单探测 ==\n"];
    [s appendString:todoTabBarProbe()];
    return s.length ? s : @"无数据";
}

#pragma mark - 底部菜单加“待办”tab（第 5 个）

static UIView *g_todoTabContainer = nil;
static NSArray *g_todoTabItems = nil; // 安装时记住的 4 个原 tab 项
static BOOL g_tabSwizzled = NO;
static BOOL g_inTabRelayout = NO;
static void (*orig_tabLayoutSubviews)(id, SEL);

// 重排：4 个原 tab 各占 1/5，我们的待办 tab 占第 5 个 1/5
static void relayoutTodoTabItems(void) {
    UIView *container = g_todoTabContainer;
    if (!container) return;
    NSArray *items = g_todoTabItems;
    if (items.count != 4) return;
    // 校验引用还在容器上；微信重建子视图时重新探测一次
    BOOL valid = YES;
    for (UIView *it in items) {
        if (it.superview != container) { valid = NO; break; }
    }
    if (!valid) {
        items = findTabItemRow(container);
        if (items.count != 4) return;
        g_todoTabItems = items;
    }
    CGFloat cw = container.bounds.size.width;
    if (cw <= 0) return;
    CGFloat newW = cw / 5.0;
    for (NSUInteger i = 0; i < items.count; i++) {
        UIView *it = items[i];
        CGRect f = it.frame;
        f.origin.x = i * newW;
        f.size.width = newW;
        it.frame = f;
    }
    if (g_todoTabItemView) {
        if (g_todoTabItemView.superview != container) {
            [container addSubview:g_todoTabItemView]; // 微信重建子视图后补回来
        }
        CGRect f = g_todoTabItemView.frame;
        f.origin.x = 4 * newW;
        f.size.width = newW;
        g_todoTabItemView.frame = f;
        [container bringSubviewToFront:g_todoTabItemView];
    }
}

static void swz_tabLayoutSubviews(id self, SEL _cmd) {
    if (orig_tabLayoutSubviews) orig_tabLayoutSubviews(self, _cmd);
    if (self == g_todoTabContainer && !g_inTabRelayout) {
        g_inTabRelayout = YES;
        @try {
            relayoutTodoTabItems();
        } @catch (NSException *e) {}
        g_inTabRelayout = NO;
    }
}

// 生成“待办”tab 项视图（图标 + 文字，点击打开待办页）
static UIView *makeTodoTabItemView(CGFloat width, CGFloat height) {
    UIView *item = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    item.userInteractionEnabled = YES;

    CGFloat iconSize = 40.0;
    CGFloat iconY = 6.0;
    if (height < 55) iconY = 2.0;
    UIImageView *iv = [[UIImageView alloc]
                       initWithFrame:CGRectMake((width - iconSize) / 2.0, iconY, iconSize, iconSize)];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    UIImage *icon = [UIImage systemImageNamed:@"checklist"];
    if (icon) {
        iv.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    } else {
        iv.image = [UIImage systemImageNamed:@"square.and.pencil"];
    }
    iv.tintColor = [UIColor systemGrayColor];
    [item addSubview:iv];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, height - 20, width, 14)];
    label.text = @"待办";
    label.font = [UIFont systemFontOfSize:10];
    label.textColor = [UIColor systemGrayColor];
    label.textAlignment = NSTextAlignmentCenter;
    [item addSubview:label];

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:g_todoGestureTarget
                                                action:@selector(todoTabTapped)];
    [item addGestureRecognizer:tap];
    return item;
}

// 结构匹配才加：容器 + 恰好 4 个等宽 tab 项，否则静默跳过（诊断里能看到原因）
static void installTodoTabItem(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_todoTabItemView) return;
        UIWindow *window = g_todoWindow ?: [UIApplication sharedApplication].keyWindow;
        if (!window) return;
        UIView *container = findBottomTabContainer(window);
        if (!container) return;
        NSArray *items = findTabItemRow(container);
        if (items.count != 4) return;

        if (!g_todoGestureTarget) {
            g_todoGestureTarget = [[TodoGestureTarget alloc] init];
        }
        UIView *first = items[0];
        CGFloat newW = container.bounds.size.width / 5.0;
        g_todoTabItems = items;
        g_todoTabItemView = makeTodoTabItemView(newW, first.frame.size.height);
        g_todoTabItemView.frame = CGRectMake(4 * newW, first.frame.origin.y, newW, first.frame.size.height);
        [container addSubview:g_todoTabItemView];
        g_todoTabContainer = container;
        relayoutTodoTabItems();

        // 微信自己重排后自动恢复我们的布局（只 swizzle 一次）
        Class cls = [container class];
        if (!g_tabSwizzled) {
            Method m = class_getInstanceMethod(cls, @selector(layoutSubviews));
            if (m) {
                orig_tabLayoutSubviews = (void *)method_getImplementation(m);
                method_setImplementation(m, (IMP)swz_tabLayoutSubviews);
                g_tabSwizzled = YES;
            }
        }
        diagLog(@"底部菜单已加第5个tab（容器=%@ 原项=%lu）",
                NSStringFromClass(cls), (unsigned long)items.count);
    });
}

// 底部菜单结构探测（诊断用，结果进剪贴板）
static NSString *todoTabBarProbe(void) {
    NSMutableString *s = [NSMutableString string];
    UIWindow *win = g_todoWindow ?: [UIApplication sharedApplication].keyWindow;
    [s appendFormat:@"窗口: %@\n", win ? NSStringFromClass([win class]) : @"无"];
    if (!win) return s;

    NSMutableArray *queue = [NSMutableArray arrayWithObject:win];
    int scanned = 0;
    int shown = 0;
    while (queue.count > 0 && shown < 20) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (++scanned > 30000) break;
        NSString *cls = NSStringFromClass([v class]);
        if ([cls rangeOfString:@"TaskBar"].location != NSNotFound ||
            [cls rangeOfString:@"TabBar"].location != NSNotFound ||
            [cls rangeOfString:@"MainFrameItem"].location != NSNotFound ||
            [cls rangeOfString:@"CustomBar"].location != NSNotFound) {
            CGRect f = [v convertRect:v.bounds toView:win];
            [s appendFormat:@"%@ frame=(%.0f,%.0f,%.0f,%.0f) 子视图=%lu\n",
             cls, f.origin.x, f.origin.y, f.size.width, f.size.height,
             (unsigned long)v.subviews.count];
            shown++;
            for (UIView *sv in v.subviews) {
                CGRect sf = [sv convertRect:sv.bounds toView:win];
                [s appendFormat:@"  ├ %@ frame=(%.0f,%.0f,%.0f,%.0f) 子=%lu\n",
                 NSStringFromClass([sv class]), sf.origin.x, sf.origin.y,
                 sf.size.width, sf.size.height, (unsigned long)sv.subviews.count];
            }
        }
        [queue addObjectsFromArray:v.subviews];
    }

    UIView *container = findBottomTabContainer(win);
    [s appendFormat:@"tab 容器: %@\n", container ? NSStringFromClass([container class]) : @"未找到"];
    if (container) {
        NSArray *items = findTabItemRow(container);
        [s appendFormat:@"等宽 tab 项: %lu 个\n", (unsigned long)items.count];
        for (UIView *it in items) {
            [s appendFormat:@"  %@ frame=(%.0f,%.0f,%.0f,%.0f)\n",
             NSStringFromClass([it class]), it.frame.origin.x, it.frame.origin.y,
             it.frame.size.width, it.frame.size.height];
        }
    }
    // 兜底：不依赖类名，按位置找底部条（防止 tab 栏类名和猜测不一致）
    [s appendString:@"\n按位置找底部条（高40-120、贴底，最多8个）:\n"];
    NSMutableArray *queue2 = [NSMutableArray arrayWithObject:win];
    int scanned2 = 0;
    int shown2 = 0;
    while (queue2.count > 0 && shown2 < 8) {
        UIView *v = queue2.firstObject;
        [queue2 removeObjectAtIndex:0];
        if (++scanned2 > 30000) break;
        CGRect f = [v convertRect:v.bounds toView:win];
        if (f.size.height >= 40 && f.size.height <= 120 && f.size.width > 150 &&
            f.origin.y + f.size.height >= win.bounds.size.height - 12) {
            [s appendFormat:@"  %@ frame=(%.0f,%.0f,%.0f,%.0f) 子=%lu\n",
             NSStringFromClass([v class]), f.origin.x, f.origin.y,
             f.size.width, f.size.height, (unsigned long)v.subviews.count];
            shown2++;
        }
        [queue2 addObjectsFromArray:v.subviews];
    }
    return s;
}

// 定时刷新当前账号（多账号隔离），同时兜底触发旧联系人清理
static void startAccountRefreshTimer(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTimer *timer = [NSTimer timerWithTimeInterval:30.0
                                                repeats:YES
                                                  block:^(NSTimer *timer) {
            NSString *usr = wechatSelfUsrName();
            if (usr.length > 0) [AISettings setCurrentAccount:usr];
            runTodoContactCleanupOnce();
        }];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    });
}

#pragma mark - 消息 hook（仅用于刷新当前账号，不做任何消息处理，无副作用）

static void (*orig_AsyncOnAddMsg)(id, SEL, id, id);

static void swz_AsyncOnAddMsg(id self, SEL _cmd, id arg1, id wrap) {
    if (orig_AsyncOnAddMsg) orig_AsyncOnAddMsg(self, _cmd, arg1, wrap);
    @try {
        NSString *usr = wechatSelfUsrName();
        if (usr.length > 0) [AISettings setCurrentAccount:usr];
    } @catch (NSException *e) {}
}

static BOOL g_hooksInstalled = NO;

static void installHooks(void) {
    if (g_hooksInstalled) return;
    Class cls = NSClassFromString(@"CMessageMgr");
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, @selector(AsyncOnAddMsg:MsgWrap:));
    if (!m) return;
    g_hooksInstalled = YES;
    orig_AsyncOnAddMsg = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)swz_AsyncOnAddMsg);
    NSLog(kAITodoLogPrefix "消息 hook 已安装（仅账号刷新）");
}

#pragma mark - wcplugins 注册

static void registerWithWCPlugins(int remaining) {
    static BOOL g_wcpluginsRegistered = NO;
    if (g_wcpluginsRegistered) return; // 幂等：只注册一次
    Class mgrClass = NSClassFromString(@"WCPluginsMgr");
    if (mgrClass && [mgrClass respondsToSelector:@selector(sharedInstance)]) {
        id mgr = [mgrClass sharedInstance];
        if (mgr && [mgr respondsToSelector:@selector(registerControllerWithTitle:version:controller:)]) {
            [mgr registerControllerWithTitle:@"待办事项"
                                     version:kAITodoVersion
                                  controller:@"TodoSettingsViewController"];
            g_wcpluginsRegistered = YES;
            NSLog(kAITodoLogPrefix "已注册到 wcplugins（设置页条目）");
            return;
        }
    }
    if (remaining <= 0) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        registerWithWCPlugins(remaining - 1);
    });
}

#pragma mark - 初始化

__attribute__((constructor))
static void WeChatTodoInit(void) {
    NSLog(kAITodoLogPrefix "待办事项插件已加载（v%@）…", kAITodoVersion);
    g_diagLock = [[NSObject alloc] init];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidFinishLaunchingNotification"
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *note) {
        registerWithWCPlugins(10);
        installHooks();
        installTodoGestureAndHint();
        // 底部菜单加“待办”tab：微信结构加载较慢，分几次尝试
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ installTodoTabItem(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ installTodoTabItem(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ installTodoTabItem(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(24.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ installTodoTabItem(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            NSString *usr = wechatSelfUsrName();
            if (usr.length > 0) [AISettings setCurrentAccount:usr];
            runTodoContactCleanupOnce();
            startAccountRefreshTimer();
        });
    }];

    // 兜底：通知没等到也安装
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        registerWithWCPlugins(10);
        installHooks();
        installTodoGestureAndHint();
        installTodoTabItem();
    });
}
