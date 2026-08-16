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
#import "CustomCalendarTodoViewController.h"

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

// 供待办页调用：进入页面时立即刷新当前账号（不等消息 hook / 定时器）
void todoEnsureAccount(void) {
    @try {
        NSString *usr = wechatSelfUsrName();
        if (usr.length > 0) [AISettings setCurrentAccount:usr];
    } @catch (NSException *e) {}
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

#pragma mark - 底部菜单加“待办”tab

static void diagLog(NSString *fmt, ...); // 前向声明（定义在下方）

static BOOL g_todoSkipInjection = NO; // 本次启动是否跳过 tab 注入（构造时决定）

// 崩溃自恢复：只在“上一次同版本疑似崩溃”时跳过，新版本/正常启动不拦
static BOOL todoTabCrashGuard(void) {
    if (g_todoSkipInjection) {
        diagLog(@"上次同版本疑似崩溃，本次跳过 tab 注入");
        return NO;
    }
    return YES;
}

static UIWindow *g_todoWindow = nil;
static UIView *g_todoTabContainer = nil;
static UIView *g_todoTabItemView = nil;
static UIViewController *g_todoOverlayVC = nil;
static UIImageView *g_todoTabIcon = nil;
static UILabel *g_todoTabLabel = nil;
static BOOL g_tabSwizzled = NO;
static BOOL g_inTabRelayout = NO;
static void (*orig_tabLayoutSubviews)(id, SEL);

static NSObject *g_diagLock = nil;
static NSMutableArray *g_diagEvents = nil;
static BOOL g_todoSettingHooked = NO;        // 设置页原生入口是否已装上（诊断用）
static BOOL g_todoSettingsFallbackUsed = NO; // 是否已退回 wcplugins 兜底

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

// 找到底部 tab 栏容器（微信是 MMTabBar，类名含 TabBar 且贴近窗口底部）
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

// 按类名收集 tab 栏子视图（按 x 排序）
static NSArray *viewsWithName(UIView *container, NSString *keyword) {
    NSMutableArray *arr = [NSMutableArray array];
    for (UIView *s in container.subviews) {
        NSString *cls = NSStringFromClass([s class]);
        if ([cls rangeOfString:keyword].location != NSNotFound) {
            [arr addObject:s];
        }
    }
    [arr sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        if (a.frame.origin.x < b.frame.origin.x) return NSOrderedAscending;
        if (a.frame.origin.x > b.frame.origin.x) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return arr;
}

// 识别 tab 数量：优先按钮数（UITabBarButton），其次内容视图（MMTabBarItemView），最后按帧宽等分推算
static NSUInteger detectTabCount(UIView *container) {
    if (!container) return 0;
    NSArray *buttons = viewsWithName(container, @"TabBarButton");
    if (buttons.count >= 3 && buttons.count <= 5) return buttons.count;
    NSArray *items = viewsWithName(container, @"TabBarItem");
    if (items.count >= 3 && items.count <= 5) return items.count;
    CGFloat cw = container.bounds.size.width;
    if (cw <= 0) return 0;
    for (UIView *s in container.subviews) {
        CGRect f = s.frame;
        if (f.size.width > cw / 8.0 && f.size.width < cw / 2.5 &&
            f.size.height >= 30 && f.origin.y >= 0) {
            NSUInteger n = (NSUInteger)(cw / f.size.width + 0.5);
            if (n >= 3 && n <= 5) return n;
        }
    }
    return 0;
}

// 重排：现有 tab 项按 N+1 等分缩窄，待办 tab 占最后一位；微信每次布局后会自动恢复
static void relayoutTodoTabItems(void) {
    UIView *container = g_todoTabContainer;
    if (!container) return;
    CGFloat cw = container.bounds.size.width;
    if (cw <= 0) return;

    NSArray *buttons = viewsWithName(container, @"TabBarButton");
    NSArray *items = viewsWithName(container, @"TabBarItem");
    NSUInteger N = detectTabCount(container);
    if (N < 3) return;
    CGFloat slotW = cw / (N + 1.0);

    if (buttons.count == N) {
        for (NSUInteger i = 0; i < N; i++) {
            UIView *b = buttons[i];
            CGRect f = b.frame;
            f.origin.x = i * slotW;
            f.size.width = slotW;
            b.frame = f;
        }
    }
    if (items.count >= N) {
        // 内容视图按 x 排序后依次分配到槽位 0..N-1，避免就近匹配把两个挤到同一槽
        NSArray *sorted = [items sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            if (a.frame.origin.x < b.frame.origin.x) return NSOrderedAscending;
            if (a.frame.origin.x > b.frame.origin.x) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        for (NSUInteger i = 0; i < N && i < sorted.count; i++) {
            UIView *it = sorted[i];
            CGRect f = it.frame;
            f.origin.x = i * slotW;
            f.size.width = slotW;
            it.frame = f;
        }
    }
    if (g_todoTabItemView) {
        if (g_todoTabItemView.superview != container) {
            [container addSubview:g_todoTabItemView]; // 微信重建子视图后补回来
        }
        CGRect f = g_todoTabItemView.frame;
        f.origin.x = N * slotW;
        f.size.width = slotW;
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

// 前向声明（定义在下方）
static void openTodoOverlay(void);
static void closeTodoOverlay(void);

@interface TodoTabTarget : NSObject
@end

static TodoTabTarget *g_todoTabTarget = nil;

@implementation TodoTabTarget

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pageAppeared)
                                                     name:kWeChatTodoPageAppearNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pageDisappeared)
                                                     name:kWeChatTodoPageDisappearNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setSelected:(BOOL)selected {
    UIColor *c = selected ? [UIColor systemGreenColor] : [UIColor labelColor];
    if (g_todoTabIcon) g_todoTabIcon.tintColor = c;
    if (g_todoTabLabel) g_todoTabLabel.textColor = c;
}

- (void)pageAppeared {
    [self setSelected:YES];
}

- (void)pageDisappeared {
    [self setSelected:NO];
}

- (void)todoTabTapped {
    diagLog(@"底部菜单「待办」tab 点击");
    if (g_todoOverlayVC) {
        [self setSelected:NO];
        closeTodoOverlay();
        return;
    }
    [self setSelected:YES];
    openTodoOverlay();
}

- (void)otherTabTapped {
    diagLog(@"其它 tab 点击，关闭待办页");
    closeTodoOverlay();
}

@end

// 内嵌打开待办页：只占底部菜单上方的内容区，底部菜单保持可见
static void openTodoOverlay(void) {
    if (g_todoOverlayVC) return;
    UIWindow *window = g_todoWindow ?: [UIApplication sharedApplication].keyWindow;
    if (!window) return;
    UIViewController *root = window.rootViewController;
    if (!root) return;
    UIView *tabBar = g_todoTabContainer;
    if (!tabBar) return;
    CGRect tb = [tabBar convertRect:tabBar.bounds toView:window];
    if (CGRectIsEmpty(tb) || CGRectGetMinY(tb) <= 0) return;

    CustomCalendarTodoViewController *vc = [[CustomCalendarTodoViewController alloc] init];
    [root addChildViewController:vc];
    vc.view.frame = CGRectMake(0, 0, window.bounds.size.width, CGRectGetMinY(tb));
    vc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [root.view addSubview:vc.view];
    [vc didMoveToParentViewController:root];
    g_todoOverlayVC = vc;
    diagLog(@"待办页以内嵌方式打开（底部菜单可见）");
}

static void closeTodoOverlay(void) {
    UIViewController *vc = g_todoOverlayVC;
    if (!vc) return;
    [vc.view removeFromSuperview];
    [vc removeFromParentViewController];
    g_todoOverlayVC = nil;
    diagLog(@"待办页已关闭");
}

// 供待办页关闭按钮调用（内嵌模式没有导航栈可退）
void todoCloseOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        closeTodoOverlay();
    });
}

// 供待办页使用微信页面背景，让页面和微信融为一体
UIColor *todoWeChatBackgroundColor(void) {
    UIViewController *mf = findNewMainFrameVC();
    UIColor *c = nil;
    UIWindow *window = g_todoWindow ?: [UIApplication sharedApplication].keyWindow;
    // 1. 窗口背景（ThemeBox 通常把主题色设在这）
    if (window && window.backgroundColor &&
        CGColorGetAlpha(window.backgroundColor.CGColor) > 0.01) {
        c = window.backgroundColor;
    }
    // 2. 根视图背景
    if (!c && window.rootViewController.view.backgroundColor &&
        CGColorGetAlpha(window.rootViewController.view.backgroundColor.CGColor) > 0.01) {
        c = window.rootViewController.view.backgroundColor;
    }
    // 优先取主界面表格背景（微信页面通常用它做底色）
    if (!c && mf.view) {
        NSMutableArray *queue = [NSMutableArray arrayWithObject:mf.view];
        int scanned = 0;
        while (queue.count > 0 && scanned < 5000) {
            UIView *v = queue.firstObject;
            [queue removeObjectAtIndex:0];
            scanned++;
            if ([v isKindOfClass:[UITableView class]]) {
                UIColor *tc = v.backgroundColor;
                if (tc && CGColorGetAlpha(tc.CGColor) > 0.01) {
                    c = tc;
                    break;
                }
            }
            [queue addObjectsFromArray:v.subviews];
        }
    }
    if (!c) c = mf.view.backgroundColor;
    if (!c || CGColorGetAlpha(c.CGColor) < 0.01) {
        return [UIColor systemGroupedBackgroundColor];
    }
    return c;
}

// 保险：微信切换 tab 时也关闭待办页（覆盖手势没接住的情况）
static void (*orig_setSelectedIndex)(id, SEL, NSInteger);
static void swz_setSelectedIndex(id self, SEL _cmd, NSInteger index) {
    if (orig_setSelectedIndex) orig_setSelectedIndex(self, _cmd, index);
    closeTodoOverlay();
}
static void (*orig_setSelectedViewController)(id, SEL, id);
static void swz_setSelectedViewController(id self, SEL _cmd, id vc) {
    if (orig_setSelectedViewController) orig_setSelectedViewController(self, _cmd, vc);
    closeTodoOverlay();
}
static void (*orig_tabBarDidSelect)(id, SEL, id, id);
static void swz_tabBarDidSelect(id self, SEL _cmd, id tb, id item) {
    if (orig_tabBarDidSelect) orig_tabBarDidSelect(self, _cmd, tb, item);
    closeTodoOverlay();
}

static void installTabSwitchHook(void) {
    Class cls = NSClassFromString(@"MainTabBarViewController");
    if (!cls) return;
    static BOOL hooked = NO;
    if (hooked) return;
    @try {
        Method m1 = class_getInstanceMethod(cls, @selector(setSelectedIndex:));
        if (m1) {
            orig_setSelectedIndex = (void *)method_getImplementation(m1);
            method_setImplementation(m1, (IMP)swz_setSelectedIndex);
        }
        Method m2 = class_getInstanceMethod(cls, @selector(setSelectedViewController:));
        if (m2) {
            orig_setSelectedViewController = (void *)method_getImplementation(m2);
            method_setImplementation(m2, (IMP)swz_setSelectedViewController);
        }
        Method m3 = class_getInstanceMethod(cls, @selector(tabBar:didSelectItem:));
        if (m3) {
            orig_tabBarDidSelect = (void *)method_getImplementation(m3);
            method_setImplementation(m3, (IMP)swz_tabBarDidSelect);
        }
    } @catch (NSException *e) {
        NSLog(kAITodoLogPrefix "tab 切换 hook 安装异常: %@", e);
    }
    hooked = YES;
    NSLog(kAITodoLogPrefix "tab 切换 hook 已安装");
}

// 生成“待办”tab 项视图（图标 + 文字）
static UIView *makeTodoTabItemView(CGFloat width, CGFloat height) {
    UIView *item = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    item.userInteractionEnabled = YES;

    // 对齐微信原生 MMTabBarItemView：图标 28x28 在顶部，文字 12pt 在下方
    CGFloat iconSize = 28.0;
    CGFloat iconY = height >= 80 ? 8.0 : 6.0;
    UIImageView *iv = [[UIImageView alloc]
                       initWithFrame:CGRectMake((width - iconSize) / 2.0, iconY, iconSize, iconSize)];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    UIImage *icon = [UIImage systemImageNamed:@"checklist"];
    if (icon) {
        iv.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    } else {
        iv.image = [UIImage systemImageNamed:@"square.and.pencil"];
    }
    iv.tintColor = [UIColor labelColor]; // 未选中：黑线（深色模式自动变白），和微信一致
    [item addSubview:iv];
    g_todoTabIcon = iv;

    CGFloat labelY = height >= 80 ? height - 52.0 : height - 17.0; // 90→38, 55→38
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, labelY, width, 12)];
    label.text = @"待办";
    label.font = [UIFont systemFontOfSize:10];
    label.textColor = [UIColor labelColor];
    label.textAlignment = NSTextAlignmentCenter;
    [item addSubview:label];
    g_todoTabLabel = label;

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:g_todoTabTarget
                                                action:@selector(todoTabTapped)];
    [item addGestureRecognizer:tap];
    return item;
}

// 结构匹配才加：容器 + tab 项存在，否则静默跳过（诊断里能看到原因）
static void installTodoTabItem(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!todoTabCrashGuard()) return;
        @try {
            if (g_todoTabItemView) return;
            UIWindow *window = g_todoWindow ?: [UIApplication sharedApplication].keyWindow;
            if (!window) return;
            UIView *container = findBottomTabContainer(window);
            if (!container) return;
            g_todoWindow = window;

            // 先确认 tab 数量（3 或 4 个，防止误判其它视图）
            NSUInteger tabCount = detectTabCount(container);
            if (tabCount < 3) return;

            if (!g_todoTabTarget) {
                g_todoTabTarget = [[TodoTabTarget alloc] init];
            }

            CGFloat newW = container.bounds.size.width / (tabCount + 1.0);
            CGFloat itemY = 0, itemH = 55.0;
            for (UIView *s in container.subviews) {
                NSString *cls = NSStringFromClass([s class]);
                if ([cls rangeOfString:@"TabBarItem"].location != NSNotFound ||
                    [cls rangeOfString:@"TabBarButton"].location != NSNotFound) {
                    itemY = s.frame.origin.y;
                    itemH = s.frame.size.height;
                    break;
                }
            }
            g_todoTabItemView = makeTodoTabItemView(newW, itemH);
            g_todoTabItemView.frame = CGRectMake(tabCount * newW, itemY, newW, itemH);
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
            // 其它 4 个 tab 点击时关闭待办页（按钮和 item 都挂，确保生效）
            NSArray *otherButtons = viewsWithName(container, @"TabBarButton");
            for (UIView *iv in otherButtons) {
                UITapGestureRecognizer *t =
                    [[UITapGestureRecognizer alloc] initWithTarget:g_todoTabTarget
                                                            action:@selector(otherTabTapped)];
                t.cancelsTouchesInView = NO;
                [iv addGestureRecognizer:t];
            }
            NSArray *otherItems = viewsWithName(container, @"TabBarItem");
            for (UIView *iv in otherItems) {
                UITapGestureRecognizer *t =
                    [[UITapGestureRecognizer alloc] initWithTarget:g_todoTabTarget
                                                            action:@selector(otherTabTapped)];
                t.cancelsTouchesInView = NO;
                [iv addGestureRecognizer:t];
            }
            diagLog(@"底部菜单已加待办tab（容器=%@ 原tab=%lu）",
                    NSStringFromClass(cls), (unsigned long)tabCount);
            installTabSwitchHook();
        } @catch (NSException *e) {
            NSLog(kAITodoLogPrefix "tab 注入异常（已跳过）: %@", e);
        }
    });
}

// 诊断（设置页按钮调用，结果复制到剪贴板）
static NSString *todoTabBarProbe(void); // 前向声明（定义在下方）

NSString *todoTabDiagnostic(void) {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"待办插件 v%@ 诊断\n", kAITodoVersion];
    UIWindow *key = [UIApplication sharedApplication].keyWindow;
    [s appendFormat:@"keyWindow: %@\n", key ? NSStringFromClass([key class]) : @"无"];
    UIViewController *root = key ? key.rootViewController : nil;
    [s appendFormat:@"rootVC: %@\n", root ? NSStringFromClass([root class]) : @"无"];
    UIWindow *win = g_todoWindow ?: key;
    [s appendFormat:@"主窗口: %@\n", win ? NSStringFromClass([win class]) : @"无"];
    UIView *container = findBottomTabContainer(win);
    [s appendFormat:@"tab 容器: %@\n", container ? NSStringFromClass([container class]) : @"未找到"];
    [s appendFormat:@"待办tab已加: %@\n", g_todoTabItemView ? @"是" : @"否"];
    [s appendFormat:@"设置页入口: %@\n",
     g_todoSettingHooked ? @"微信原生设置页" : (g_todoSettingsFallbackUsed ? @"wcplugins 兜底" : @"安装中…")];
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
        NSArray *buttons = viewsWithName(container, @"TabBarButton");
        NSArray *items = viewsWithName(container, @"TabBarItem");
        [s appendFormat:@"tab 数量: %lu（按钮%lu / 内容视图%lu）\n",
         (unsigned long)detectTabCount(container),
         (unsigned long)buttons.count, (unsigned long)items.count];
        for (UIView *it in buttons) {
            [s appendFormat:@"  [按钮] %@ frame=(%.0f,%.0f,%.0f,%.0f)\n",
             NSStringFromClass([it class]), it.frame.origin.x, it.frame.origin.y,
             it.frame.size.width, it.frame.size.height];
        }
        for (UIView *it in items) {
            [s appendFormat:@"  [内容] %@ frame=(%.0f,%.0f,%.0f,%.0f)\n",
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

#pragma mark - 设置页入口：优先挂入微信原生设置页（参考 itenfay/WeChat_tweak）

static void *kTodoSettingTableKey = &kTodoSettingTableKey;          // 标记微信设置页表格
static void *kTodoDSHookedKey = &kTodoDSHookedKey;                  // 某 dataSource 类已挂钩
static void *kTodoOrigNumberRowsKey = &kTodoOrigNumberRowsKey;      // 每类原实现（沿继承链取）
static void *kTodoOrigCellKey = &kTodoOrigCellKey;
static void *kTodoOrigDidSelectKey = &kTodoOrigDidSelectKey;
static void *kTodoOrigHeightKey = &kTodoOrigHeightKey;

static void (*orig_reloadTableData_setting)(id, SEL);
static void (*orig_viewDidAppear_setting)(id, SEL, BOOL);

static NSInteger swz_todo_numberOfRows(id, SEL, UITableView *, NSInteger);        // 前向声明
static UITableViewCell *swz_todo_cellForRow(id, SEL, UITableView *, NSIndexPath *);
static void swz_todo_didSelect(id, SEL, UITableView *, NSIndexPath *);
static CGFloat swz_todo_heightForRow(id, SEL, UITableView *, NSIndexPath *);
static BOOL todoEnsureDataSourceHooked(UITableView *);                           // 前向声明
static void registerWithWCPlugins(int remaining);                                // 前向声明（兜底）

static BOOL todoTableIsSettingTable(UITableView *tableView) {
    return [objc_getAssociatedObject(tableView, &kTodoSettingTableKey) boolValue];
}

// 沿类继承链查找该类的“挂钩前原实现”（子类实例也能取到父类记录的原实现）
static IMP todoOrigImpForClass(Class cls, void *key) {
    for (Class c = cls; c; c = class_getSuperclass(c)) {
        NSValue *v = objc_getAssociatedObject(c, key);
        if (v) return (IMP)[v pointerValue];
    }
    return NULL;
}

static void todoSetOrigImpForClass(Class cls, void *key, IMP imp) {
    objc_setAssociatedObject(cls, key,
                             [NSValue valueWithPointer:(const void *)imp],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 找到指定视图内的第一个 UITableView
static UITableView *todoFindTableViewInView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UITableView class]]) return (UITableView *)view;
    for (UIView *sub in view.subviews) {
        UITableView *found = todoFindTableViewInView(sub);
        if (found) return found;
    }
    return nil;
}

static UITableViewCell *todoMakeSettingEntryCell(void) {
    UITableViewCell *cell = nil;
    @try {
        Class cellClass = NSClassFromString(@"MMTableViewCell");
        if (cellClass) {
            cell = [[cellClass alloc] initWithStyle:UITableViewCellStyleDefault
                                    reuseIdentifier:@"WeChatTodoSettingEntry"];
        }
    } @catch (NSException *e) {
        cell = nil;
    }
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"WeChatTodoSettingEntry"];
    }
    cell.textLabel.text = @"待办事项";
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    // 背景不写死，交给 MMTableViewCell / 微信主题接管，ThemeBox 也能正常染色
    return cell;
}

// 打开设置页：优先 push 进微信导航栈（原生转场，无黑背景）
static void todoPushSettingsPage(UITableView *tableView) {
    @try {
        Class vcCls = NSClassFromString(@"TodoSettingsViewController");
        if (!vcCls) return;
        UIViewController *vc = [[vcCls alloc] init];
        UIViewController *host = nil;
        UIResponder *r = tableView;
        while ((r = [r nextResponder])) {
            if ([r isKindOfClass:[UIViewController class]]) {
                host = (UIViewController *)r;
                break;
            }
        }
        UINavigationController *nav = host.navigationController;
        if (nav) {
            [nav pushViewController:vc animated:YES];
            return;
        }
        UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        UINavigationController *wrap = [[UINavigationController alloc] initWithRootViewController:vc];
        wrap.modalPresentationStyle = UIModalPresentationFullScreen;
        [top presentViewController:wrap animated:YES completion:nil];
    } @catch (NSException *e) {
        NSLog(kAITodoLogPrefix "打开待办设置页异常: %@", e);
    }
}

static NSInteger swz_todo_numberOfRows(id self, SEL _cmd, UITableView *tableView, NSInteger section) {
    NSInteger (*origFn)(id, SEL, UITableView *, NSInteger) =
        (NSInteger (*)(id, SEL, UITableView *, NSInteger))
        todoOrigImpForClass(object_getClass(self), &kTodoOrigNumberRowsKey);
    NSInteger orig = origFn ? origFn(self, _cmd, tableView, section) : 0;
    if (todoTableIsSettingTable(tableView) && section == 0) {
        return orig + 1; // 第一组顶部加一行“待办事项”
    }
    return orig;
}

// 把设置页表格 dataSource 的类挂上我们的扩展。
// 动态发现：不预设 MMTableViewInfo / WCTableViewManager，实际是谁就 hook 谁。
// 原实现沿继承链存放，子类实例也能取到。返回 YES 表示“刚刚补挂”，需要刷一次表格。
static BOOL todoEnsureDataSourceHooked(UITableView *tableView) {
    if (!tableView.dataSource) return NO;
    Class ds = object_getClass(tableView.dataSource);
    if (!ds) return NO;
    if (objc_getAssociatedObject(ds, &kTodoDSHookedKey)) return NO;

    SEL sels[4] = {
        @selector(tableView:numberOfRowsInSection:),
        @selector(tableView:cellForRowAtIndexPath:),
        @selector(tableView:didSelectRowAtIndexPath:),
        @selector(tableView:heightForRowAtIndexPath:)
    };
    void *keys[4] = {
        &kTodoOrigNumberRowsKey, &kTodoOrigCellKey,
        &kTodoOrigDidSelectKey, &kTodoOrigHeightKey
    };
    IMP imps[4] = {
        (IMP)swz_todo_numberOfRows, (IMP)swz_todo_cellForRow,
        (IMP)swz_todo_didSelect, (IMP)swz_todo_heightForRow
    };

    BOOL installed = NO;
    for (int i = 0; i < 4; i++) {
        Method m = class_getInstanceMethod(ds, sels[i]);
        if (!m) continue;
        IMP imp = method_getImplementation(m);
        if (imp == imps[i]) continue; // 已是我们（含继承），无需重复挂钩
        // 找方法实际定义在继承链的哪个类上，原实现记在那个类，整条链都能取到
        Class owner = ds;
        for (Class c = ds; c; c = class_getSuperclass(c)) {
            unsigned int count = 0;
            Method *ms = class_copyMethodList(c, &count);
            BOOL defines = NO;
            for (unsigned int j = 0; j < count; j++) {
                if (method_getName(ms[j]) == sels[i]) { defines = YES; break; }
            }
            free(ms);
            if (defines) { owner = c; break; }
        }
        if (!todoOrigImpForClass(owner, keys[i])) {
            todoSetOrigImpForClass(owner, keys[i], imp);
        }
        method_setImplementation(m, imps[i]);
        installed = YES;
    }
    objc_setAssociatedObject(ds, &kTodoDSHookedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return installed;
}

static UITableViewCell *swz_todo_cellForRow(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    if (todoEnsureDataSourceHooked(tableView)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [tableView reloadData];
        });
    }
    if (todoTableIsSettingTable(tableView) && indexPath.section == 0) {
        if (indexPath.row == 0) return todoMakeSettingEntryCell();
        NSIndexPath *shifted = [NSIndexPath indexPathForRow:indexPath.row - 1 inSection:indexPath.section];
        UITableViewCell *(*origFn)(id, SEL, UITableView *, NSIndexPath *) =
            (UITableViewCell *(*)(id, SEL, UITableView *, NSIndexPath *))
            todoOrigImpForClass(object_getClass(self), &kTodoOrigCellKey);
        return origFn ? origFn(self, _cmd, tableView, shifted) : nil;
    }
    UITableViewCell *(*origFn)(id, SEL, UITableView *, NSIndexPath *) =
        (UITableViewCell *(*)(id, SEL, UITableView *, NSIndexPath *))
        todoOrigImpForClass(object_getClass(self), &kTodoOrigCellKey);
    return origFn ? origFn(self, _cmd, tableView, indexPath) : nil;
}

static void swz_todo_didSelect(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    todoEnsureDataSourceHooked(tableView);
    if (todoTableIsSettingTable(tableView) && indexPath.section == 0) {
        if (indexPath.row == 0) {
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            todoPushSettingsPage(tableView);
            return;
        }
        NSIndexPath *shifted = [NSIndexPath indexPathForRow:indexPath.row - 1 inSection:indexPath.section];
        void (*origFn)(id, SEL, UITableView *, NSIndexPath *) =
            (void (*)(id, SEL, UITableView *, NSIndexPath *))
            todoOrigImpForClass(object_getClass(self), &kTodoOrigDidSelectKey);
        if (origFn) origFn(self, _cmd, tableView, shifted);
        return;
    }
    void (*origFn)(id, SEL, UITableView *, NSIndexPath *) =
        (void (*)(id, SEL, UITableView *, NSIndexPath *))
        todoOrigImpForClass(object_getClass(self), &kTodoOrigDidSelectKey);
    if (origFn) origFn(self, _cmd, tableView, indexPath);
}

static CGFloat swz_todo_heightForRow(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    todoEnsureDataSourceHooked(tableView);
    if (todoTableIsSettingTable(tableView) && indexPath.section == 0) {
        if (indexPath.row == 0) return 44;
        NSIndexPath *shifted = [NSIndexPath indexPathForRow:indexPath.row - 1 inSection:indexPath.section];
        CGFloat (*origFn)(id, SEL, UITableView *, NSIndexPath *) =
            (CGFloat (*)(id, SEL, UITableView *, NSIndexPath *))
            todoOrigImpForClass(object_getClass(self), &kTodoOrigHeightKey);
        return origFn ? origFn(self, _cmd, tableView, shifted) : 44;
    }
    CGFloat (*origFn)(id, SEL, UITableView *, NSIndexPath *) =
        (CGFloat (*)(id, SEL, UITableView *, NSIndexPath *))
        todoOrigImpForClass(object_getClass(self), &kTodoOrigHeightKey);
    return origFn ? origFn(self, _cmd, tableView, indexPath) : 44;
}

// 设置页 reloadTableData / viewDidAppear 时给表格打标记，并动态挂钩它的 dataSource
static void todoMarkSettingTable(UIViewController *vc) {
    @try {
        UITableView *tableView = nil;
        Ivar tableIvar = class_getInstanceVariable([vc class], "m_tableView");
        if (tableIvar) tableView = object_getIvar(vc, tableIvar);
        if (!tableView) tableView = todoFindTableViewInView(vc.view);
        if (tableView) {
            objc_setAssociatedObject(tableView, &kTodoSettingTableKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (todoEnsureDataSourceHooked(tableView)) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [tableView reloadData];
                });
            }
        }
    } @catch (NSException *e) {
        NSLog(kAITodoLogPrefix "标记设置页表格异常: %@", e);
    }
}

static void swz_reloadTableData_setting(id self, SEL _cmd) {
    if (orig_reloadTableData_setting) orig_reloadTableData_setting(self, _cmd);
    if ([self isKindOfClass:[UIViewController class]]) {
        todoMarkSettingTable((UIViewController *)self);
    }
}

static void swz_viewDidAppear_setting(id self, SEL _cmd, BOOL animated) {
    if (orig_viewDidAppear_setting) orig_viewDidAppear_setting(self, _cmd, animated);
    if ([self isKindOfClass:[UIViewController class]]) {
        todoMarkSettingTable((UIViewController *)self);
    }
}

// 只 hook“类自己实现”的方法，避免误改父类实现影响微信其他页面
static BOOL todoClassDefines(Class cls, SEL sel) {
    if (!cls || !sel) return NO;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == sel) {
            found = YES;
            break;
        }
    }
    free(methods);
    return found;
}

static void installTodoSettingHooks(void) {
    if (g_todoSettingHooked) return;
    Class settingCls = NSClassFromString(@"NewSettingViewController");
    if (!settingCls) return;

    Method method;
    BOOL markingInstalled = NO;
    if (todoClassDefines(settingCls, @selector(reloadTableData))) {
        method = class_getInstanceMethod(settingCls, @selector(reloadTableData));
        orig_reloadTableData_setting = (void *)method_getImplementation(method);
        method_setImplementation(method, (IMP)swz_reloadTableData_setting);
        markingInstalled = YES;
    }
    if (todoClassDefines(settingCls, @selector(viewDidAppear:))) {
        method = class_getInstanceMethod(settingCls, @selector(viewDidAppear:));
        orig_viewDidAppear_setting = (void *)method_getImplementation(method);
        method_setImplementation(method, (IMP)swz_viewDidAppear_setting);
        markingInstalled = YES;
    }
    // 只有装上了“能标记设置页表格”的钩子才算成功；否则继续重试，最终退回 wcplugins
    g_todoSettingHooked = markingInstalled;
    if (g_todoSettingHooked) {
        NSLog(kAITodoLogPrefix "已挂入微信原生设置页入口（NewSettingViewController）");
    } else {
        NSLog(kAITodoLogPrefix "设置页标记钩子未装上（NewSettingViewController 无 reloadTableData/viewDidAppear），等待兜底");
    }
}

// 优先原生设置页入口；长时间拿不到再退回 wcplugins（避免重复条目，二选一）
static void setupTodoSettingsEntry(int remaining) {
    if (g_todoSettingsFallbackUsed) return;
    installTodoSettingHooks();
    if (g_todoSettingHooked) return;
    if (remaining <= 0) {
        g_todoSettingsFallbackUsed = YES;
        registerWithWCPlugins(0);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        setupTodoSettingsEntry(remaining - 1);
    });
}

// wcplugins 兜底：原生设置页入口不可用时的备用注册
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
            NSLog(kAITodoLogPrefix "已注册到 wcplugins（设置页条目，兜底）");
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

    // 崩溃自恢复：先判断“上一次同版本是否疑似崩溃”，再武装本次标记
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *crashVer = [defaults stringForKey:@"WeChatTodoTabCrashVersion"];
    BOOL crashedLast = [defaults boolForKey:@"WeChatTodoTabSuspectedCrash"] &&
                       [crashVer isEqualToString:kAITodoVersion];
    if (crashedLast) {
        g_todoSkipInjection = YES; // 上次同版本崩了，本次跳过注入，先保证微信能开
    }
    [defaults setBool:YES forKey:@"WeChatTodoTabSuspectedCrash"];
    [defaults setObject:kAITodoVersion forKey:@"WeChatTodoTabCrashVersion"];
    [defaults synchronize];
    // 正常跑到 45 秒则清除标记（说明没崩）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(45.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [defaults setBool:NO forKey:@"WeChatTodoTabSuspectedCrash"];
        [defaults synchronize];
    });

    [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidFinishLaunchingNotification"
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *note) {
        setupTodoSettingsEntry(15);
        installHooks();
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
        setupTodoSettingsEntry(15);
        installHooks();
        installTodoTabItem();
    });
}
