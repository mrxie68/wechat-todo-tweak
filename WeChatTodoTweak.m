//
//  WeChatTodoTweak.m
//  待办事项插件（微信 + Memos）
//
//  纯 Objective-C 运行时实现，不依赖 CydiaSubstrate / Theos：
//    - TrollStore + TrollFools 直接注入微信
//    - 越狱环境放进 DynamicLibraries 由 MobileSubstrate 加载
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <time.h>
#import <stdlib.h>
#import <string.h>
#import <sqlite3.h>
#import <CommonCrypto/CommonDigest.h>
#import "AIConfig.h"
#import "AISettings.h"
#import "AITodoManager.h"
#import "TodoSettingsViewController.h"

#pragma mark - 微信私有接口声明

@interface CMessageWrap : NSObject
@property (nonatomic, retain) NSString *m_nsContent;
@property (nonatomic, retain) NSString *m_nsFromUsr;
@property (nonatomic, retain) NSString *m_nsToUsr;
@property (nonatomic, assign) long long m_nsMsgSvrID;
@property (nonatomic, assign) unsigned int m_uiMessageType;
@property (nonatomic, assign) unsigned int m_uiCreateTime;
@property (nonatomic, assign) unsigned int m_uiStatus;
- (id)initWithMsgType:(long long)type;
- (id)initWithMsgType:(long long)type nsFromUsr:(NSString *)fromUsr;
@end

@interface CMessageMgr : NSObject
- (void)AsyncOnAddMsg:(id)arg1 MsgWrap:(CMessageWrap *)wrap;
- (void)MainThreadNotifyToExt:(NSDictionary *)ext;
- (void)SendTextMessage:(NSString *)content toUsrName:(NSString *)usrName;
- (void)SendMessage:(id)msgWrap isSendByWeChat:(BOOL)flag;
- (void)AddMsg:(NSString *)chatId MsgWrap:(CMessageWrap *)wrap;
@end

// 微信私有服务/联系人接口声明（与主项目一致，避免编译器找不到 selector）
@interface MMServiceCenter : NSObject
+ (instancetype)defaultCenter;
- (id)getService:(Class)cls;
@end

@interface CContactMgr : NSObject
- (id)getSelfContact;
- (void)addContact:(id)contact;
- (void)addContact:(id)contact importInfo:(id)info;
- (void)saveContact:(id)contact;
- (void)insertContact:(id)contact;
- (id)getContactByName:(NSString *)userName;
@end

@interface CContact : NSObject
@property (nonatomic, retain) NSString *m_nsUsrName;
@property (nonatomic, retain) NSString *m_nsNickName;
@property (nonatomic, retain) NSString *m_nsRemark;
- (id)initWithContactName:(NSString *)userName;
@end

@interface SettingUtil : NSObject
+ (NSString *)getCurUsrName;
@end

@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title
                            version:(NSString *)version
                         controller:(NSString *)controller;
- (void)registerSwitchWithTitle:(NSString *)title key:(NSString *)key;
@end

@interface MMNewSessionMgr : NSObject
- (id)AddOrModifySession:(id)session withNotifyFlag:(BOOL)flag immediateRefresh:(BOOL)refresh;
- (void)DeleteSessionOfUser:(NSString *)userName;
- (id)GetSessionByUserName:(NSString *)userName;
@end

@interface MainSessionMgr : NSObject
- (void)updateMainSessionList;
- (void)rebuildMainSessions;
- (NSArray *)normalSessions;
- (void)setNormalSessions:(NSArray *)sessions;
@end

static NSString *ensureTodoSessionDiagnostic(void); // 前向声明（定义在下方）
static NSString *aiMD5Hex(NSString *input);
static NSArray *aiFindDatabaseFiles(void);
static NSArray *aiSQLiteTableNames(sqlite3 *db);
static NSArray *aiSQLiteColumns(sqlite3 *db, NSString *table);
static UIViewController *tweakTopViewController(void); // 前向声明（定义在下方）

// 从列名列表里按候选名匹配一列（支持多种命名变体）
static NSString *aiPickColumnName(NSArray *cols, NSArray *candidates) {
    for (NSString *c in candidates) {
        for (NSString *col in cols) {
            if ([col isEqualToString:c]) return col;
        }
    }
    return nil;
}

@interface WeChatTodoHandler : NSObject
+ (void)handleIncomingMessage:(CMessageWrap *)wrap;
+ (void)noteReplySent:(NSString *)text chatId:(NSString *)chatId;
+ (BOOL)isRecentReply:(NSString *)text chatId:(NSString *)chatId;
+ (void)sendReply:(NSString *)text chatId:(NSString *)chatId;
+ (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message;
+ (NSString *)todoSessionDiagnostic;
+ (NSString *)createTodoSessionDiagnostic;
+ (NSString *)removeTodoSessionDiagnostic;
+ (NSString *)uiProbeDiagnostic;
@end

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

// 在主线程构造并调用微信原生接口（AddOrModifySession: 是 UI 操作，必须主线程）
static NSString *createTodoSessionOnMain(void) {
    Class mgrCls = NSClassFromString(@"MMNewSessionMgr");
    if (!mgrCls) return @"MMNewSessionMgr 类不存在";
    Class centerCls = NSClassFromString(@"MMServiceCenter");
    id center = centerCls ? [(id)centerCls defaultCenter] : nil;
    if (!center) return @"MMServiceCenter 不可用";
    id mgr = [center getService:mgrCls];
    if (!mgr) return @"拿不到 MMNewSessionMgr 服务";
    if (![mgr respondsToSelector:@selector(AddOrModifySession:withNotifyFlag:immediateRefresh:)]) {
        return @"MMNewSessionMgr 无 AddOrModifySession:withNotifyFlag:immediateRefresh:";
    }
    Class infoCls = NSClassFromString(@"MMSessionInfo");
    if (!infoCls) return @"MMSessionInfo 类不存在";
    id session = [[infoCls alloc] init];
    if (!session) return @"MMSessionInfo 初始化失败";
    id contact = nil; // 联系人对象（可能在下方 if 里创建，外面也要用）
    NSMutableArray *props = [NSMutableArray array];
    unsigned int pc = 0;
    objc_property_t *plist = class_copyPropertyList(infoCls, &pc);
    for (unsigned int i = 0; i < pc; i++) {
        const char *pn = property_getName(plist[i]);
        if (pn) [props addObject:[NSString stringWithUTF8String:pn]];
    }
    free(plist);
    @try {
        BOOL setUser = NO;
        for (NSString *k in @[@"m_nsUserName", @"m_userName", @"userName", @"m_nsUsrName", @"sessionId"]) {
            if ([props containsObject:k]) {
                [session setValue:kAITodoChatId forKey:k];
                setUser = YES;
                break;
            }
        }
        // 昵称在 m_contact（联系人对象）上
        BOOL setContact = NO;
        if ([props containsObject:@"m_contact"]) {
            Class contactCls = NSClassFromString(@"CContact");
            if (contactCls) {
                if ([contactCls instancesRespondToSelector:@selector(initWithContactName:)]) {
                    contact = [(CContact *)[contactCls alloc] initWithContactName:kAITodoChatId];
                } else {
                    contact = [[contactCls alloc] init];
                }
                if (contact) {
                    if ([contact respondsToSelector:@selector(setM_nsUsrName:)]) {
                        [contact setM_nsUsrName:kAITodoChatId];
                    }
                    if ([contact respondsToSelector:@selector(setM_nsNickName:)]) {
                        [contact setM_nsNickName:kAITodoNickName];
                    }
                    if ([contact respondsToSelector:@selector(setM_nsRemark:)]) {
                        [contact setM_nsRemark:kAITodoNickName];
                    }
                    [session setValue:contact forKey:@"m_contact"];
                    setContact = YES;
                }
            }
        }
        if (!setUser) {
            return [NSString stringWithFormat:@"MMSessionInfo 无用户名属性（已有：%@）",
                    [props componentsJoinedByString:@","]];
        }
        // 补排序/时间字段（有的排序依赖 sortTime / m_uLastTime）
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if ([props containsObject:@"sortTime"]) {
            [session setValue:@((long long)now) forKey:@"sortTime"];
        }
        if ([props containsObject:@"m_uLastTime"]) {
            [session setValue:@((unsigned int)now) forKey:@"m_uLastTime"];
        }
        [mgr AddOrModifySession:session withNotifyFlag:YES immediateRefresh:YES];

        // 回读检查：会话是否真的进了内存
        NSString *inMemory = @"会话未入内存";
        if ([mgr respondsToSelector:@selector(GetSessionByUserName:)]) {
            id found = [mgr GetSessionByUserName:kAITodoChatId];
            inMemory = found ? @"会话已入内存" : @"会话未入内存";
        }

        // 注册联系人进 CContactMgr（会话列表可能只显示已知联系人）
        NSString *contactNote = @"联系人未注册";
        if (setContact) {
            id contactMgr = [center getService:NSClassFromString(@"CContactMgr")];
            if ([contactMgr respondsToSelector:@selector(addContact:)]) {
                [contactMgr addContact:contact];
                contactNote = @"已调用 addContact:";
            } else if ([contactMgr respondsToSelector:@selector(insertContact:)]) {
                [contactMgr insertContact:contact];
                contactNote = @"已调用 insertContact:";
            }
            // 回读，仍未注册就换其他方法
            BOOL knownNow = NO;
            if ([contactMgr respondsToSelector:@selector(getContactByName:)]) {
                id known = [contactMgr getContactByName:kAITodoChatId];
                knownNow = known != nil;
            }
            if (!knownNow) {
                if ([contactMgr respondsToSelector:@selector(addContact:importInfo:)]) {
                    [contactMgr addContact:contact importInfo:nil];
                    contactNote = @"已调用 addContact:importInfo:";
                } else if ([contactMgr respondsToSelector:@selector(saveContact:)]) {
                    [contactMgr saveContact:contact];
                    contactNote = @"已调用 saveContact:";
                }
                if ([contactMgr respondsToSelector:@selector(getContactByName:)]) {
                    id known2 = [contactMgr getContactByName:kAITodoChatId];
                    knownNow = known2 != nil;
                }
            }
            contactNote = [contactNote stringByAppendingFormat:@"（回读%@）",
                           knownNow ? @"已知" : @"未知"];
        }
        // 强制刷新会话列表（更新+重建兜底）
        Class mainMgrCls = NSClassFromString(@"MainSessionMgr");
        id mainMgr = mainMgrCls ? [center getService:mainMgrCls] : nil;
        NSMutableArray *diags = [NSMutableArray array];
        [diags addObject:inMemory];
        // AddOrModifySession 未入内存时，直接往 MainSessionMgr.normalSessions 追加（先核对元素类型）
        if ([inMemory hasPrefix:@"会话未入"] && mainMgr &&
            [mainMgr respondsToSelector:@selector(normalSessions)] &&
            [mainMgr respondsToSelector:@selector(setNormalSessions:)]) {
            NSArray *normal = [mainMgr normalSessions];
            [diags addObject:[NSString stringWithFormat:@"normalSessions=%lu", (unsigned long)normal.count]];
            NSString *elemClass = normal.count > 0 ? NSStringFromClass([normal.firstObject class]) : @"空";
            [diags addObject:[NSString stringWithFormat:@"元素类:%@", elemClass]];
            BOOL typeOK = [elemClass isEqualToString:@"MMSessionInfo"] || [elemClass isEqualToString:@"SessionInfo"];
            if (typeOK) {
                BOOL contains = NO;
                for (id s in normal) {
                    NSString *uname = nil;
                    @try {
                        uname = [s valueForKey:@"m_nsUserName"];
                    } @catch (NSException *e) {}
                    if ([uname isEqualToString:kAITodoChatId]) {
                        contains = YES;
                        break;
                    }
                }
                if (!contains) {
                    NSMutableArray *newNormal = [normal mutableCopy];
                    [newNormal addObject:session];
                    [mainMgr setNormalSessions:newNormal];
                    [diags addObject:@"已追加到 normalSessions"];
                } else {
                    [diags addObject:@"已在 normalSessions 中"];
                }
            } else {
                [diags addObject:@"元素类型不匹配，未追加（防崩溃）"];
            }
        }
        if ([mainMgr respondsToSelector:@selector(updateMainSessionList)]) {
            [mainMgr updateMainSessionList];
        }
        BOOL reloaded = reloadMainFrameTable();
        [diags addObject:reloaded ? @"已强制刷新聊天列表" : @"未找到主界面表格"];
        // 用微信原生发送路径触发会话创建：发消息 → 微信自己建会话并刷新列表
        [WeChatTodoHandler sendReply:@"📋 你好，我是待办事项助手。直接发文字就能记录待办，发“帮助”看全部命令。"
                              chatId:kAITodoChatId];
        [diags addObject:@"已发送欢迎消息"];
        if ([mgr respondsToSelector:@selector(GetSessionByUserName:)]) {
            id found2 = [mgr GetSessionByUserName:kAITodoChatId];
            [diags addObject:found2 ? @"发送后会话已入内存" : @"发送后仍未入内存"];
        }
        if ([mainMgr respondsToSelector:@selector(updateMainSessionList)]) {
            [mainMgr updateMainSessionList];
        }
        (void)reloadMainFrameTable();
        [diags addObject:contactNote];
        return [NSString stringWithFormat:@"✅ 已执行\n%@", [diags componentsJoinedByString:@"；"]];
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"⚠️ 创建异常：%@", e];
    }
}

// 确保在主线线程执行
static NSString *createTodoSessionViaManager(void) {
    __block NSString *result = @"";
    if ([NSThread isMainThread]) {
        result = createTodoSessionOnMain();
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = createTodoSessionOnMain();
        });
    }
    return result;
}

#pragma mark - 基础工具

static CMessageMgr *wechatMessageMgr(void) {
    Class centerCls = NSClassFromString(@"MMServiceCenter");
    if (!centerCls) return nil;
    id center = [(id)centerCls defaultCenter];
    if (!center) return nil;
    return [center getService:NSClassFromString(@"CMessageMgr")];
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

#pragma mark - 去重（收消息双 hook + 自己回复回显）

static NSObject *g_dedupLock = nil;
static NSMutableSet *g_seenKeys = nil;
static NSMutableArray *g_seenOrder = nil;
static NSObject *g_replyLock = nil;
static NSMutableSet *g_recentReplies = nil;
static NSMutableArray *g_recentReplyOrder = nil;

static NSString *messageKey(CMessageWrap *wrap) {
    if ([wrap respondsToSelector:@selector(m_nsMsgSvrID)]) {
        @try {
            long long svrId = [wrap m_nsMsgSvrID];
            if (svrId != 0) {
                NSString *from = [wrap m_nsFromUsr] ?: @"";
                return [NSString stringWithFormat:@"%@|%lld", from, svrId];
            }
        } @catch (NSException *e) {}
    }
    NSString *from = [wrap m_nsFromUsr] ?: @"";
    NSString *content = [wrap m_nsContent] ?: @"";
    unsigned int createTime = 0;
    if ([wrap respondsToSelector:@selector(m_uiCreateTime)]) {
        createTime = (unsigned int)[wrap m_uiCreateTime];
    }
    return [NSString stringWithFormat:@"%@|%@|%u", from, content, createTime];
}

static BOOL isDuplicateMessage(CMessageWrap *wrap) {
    NSString *key = messageKey(wrap);
    if (key.length == 0) return NO;
    @synchronized (g_dedupLock) {
        if ([g_seenKeys containsObject:key]) return YES;
        [g_seenKeys addObject:key];
        [g_seenOrder addObject:key];
        if (g_seenOrder.count > 100) {
            NSString *oldest = [g_seenOrder firstObject];
            [g_seenOrder removeObjectAtIndex:0];
            [g_seenKeys removeObject:oldest];
        }
    }
    return NO;
}

@implementation WeChatTodoHandler

+ (void)noteReplySent:(NSString *)text chatId:(NSString *)chatId {
    if (text.length == 0 || chatId.length == 0) return;
    NSString *key = [NSString stringWithFormat:@"%@|%@", chatId, text];
    @synchronized (g_replyLock) {
        if (!g_recentReplies) {
            g_recentReplies = [NSMutableSet set];
            g_recentReplyOrder = [NSMutableArray array];
        }
        [g_recentReplies addObject:key];
        [g_recentReplyOrder addObject:key];
        if (g_recentReplyOrder.count > 40) {
            NSString *oldest = [g_recentReplyOrder firstObject];
            [g_recentReplyOrder removeObjectAtIndex:0];
            [g_recentReplies removeObject:oldest];
        }
    }
}

+ (BOOL)isRecentReply:(NSString *)text chatId:(NSString *)chatId {
    if (text.length == 0 || chatId.length == 0) return NO;
    NSString *key = [NSString stringWithFormat:@"%@|%@", chatId, text];
    @synchronized (g_replyLock) {
        return [g_recentReplies containsObject:key];
    }
}

+ (void)handleIncomingMessage:(CMessageWrap *)wrap {
    @try {
        NSString *selfUsr = wechatSelfUsrName();
        if (selfUsr.length > 0) [AISettings setCurrentAccount:selfUsr];

        if (![wrap isKindOfClass:NSClassFromString(@"CMessageWrap")]) return;
        if ([wrap m_uiMessageType] != 1) return; // 只处理文本
        if (isDuplicateMessage(wrap)) return;

        NSString *content = [wrap m_nsContent];
        NSString *fromUsr = [wrap m_nsFromUsr];
        NSString *toUsr = [wrap m_nsToUsr];
        if (content.length == 0) return;

        BOOL isSelf = (selfUsr.length > 0 && [fromUsr isEqualToString:selfUsr]);
        NSString *chatId = isSelf ? toUsr : fromUsr;
        if (![chatId isEqualToString:kAITodoChatId]) return; // 只处理待办对话

        // 自己刚发出的回复回显：跳过，避免把回复再当命令
        if ([self isRecentReply:content chatId:chatId]) return;

        NSString *reply = [AITodoManager handleCommand:content];
        if (reply.length > 0) {
            [self sendReply:reply chatId:kAITodoChatId];
        }
    } @catch (NSException *e) {
        NSLog(kAITodoLogPrefix "处理消息异常: %@", e);
    }
}

+ (void)sendReply:(NSString *)text chatId:(NSString *)chatId {
    if (text.length == 0 || chatId.length == 0) return;
    void (^send)(void) = ^{
        CMessageMgr *mgr = wechatMessageMgr();
        if (!mgr) {
            NSLog(kAITodoLogPrefix "获取 CMessageMgr 失败");
            return;
        }
        [self noteReplySent:text chatId:chatId];
        BOOL sent = NO;
        if ([mgr respondsToSelector:@selector(SendTextMessage:toUsrName:)]) {
            [mgr SendTextMessage:text toUsrName:chatId];
            sent = YES;
        } else if ([mgr respondsToSelector:@selector(AddMsg:MsgWrap:)]) {
            Class wrapCls = NSClassFromString(@"CMessageWrap");
            if (wrapCls) {
                NSString *selfUsr = wechatSelfUsrName();
                CMessageWrap *wrap = nil;
                if (selfUsr.length > 0) {
                    wrap = [[wrapCls alloc] initWithMsgType:1 nsFromUsr:selfUsr];
                } else {
                    wrap = [[wrapCls alloc] initWithMsgType:1];
                }
                if (wrap) {
                    [wrap setM_nsContent:text];
                    [wrap setM_nsToUsr:chatId];
                    [wrap setM_uiMessageType:1];
                    [wrap setM_uiCreateTime:(unsigned int)time(NULL)];
                    [wrap setM_uiStatus:1];
                    [mgr AddMsg:chatId MsgWrap:wrap];
                    sent = YES;
                }
            }
        } else {
            CMessageWrap *wrap = [[NSClassFromString(@"CMessageWrap") alloc] init];
            if (wrap) {
                [wrap setM_nsContent:text];
                [wrap setM_nsToUsr:chatId];
                [wrap setM_uiMessageType:1];
                id service = mgr;
                Class serviceCls = NSClassFromString(@"WCMessageService");
                Class centerCls = NSClassFromString(@"MMServiceCenter");
                id center = centerCls ? [(id)centerCls defaultCenter] : nil;
                if (serviceCls && center) {
                    id s = [center getService:serviceCls];
                    if (s) service = s;
                }
                if ([service respondsToSelector:@selector(SendMessage:isSendByWeChat:)]) {
                    [service SendMessage:wrap isSendByWeChat:YES];
                    sent = YES;
                }
            }
        }
        NSLog(kAITodoLogPrefix "回复待办 %@：%@", sent ? @"成功" : @"失败", text);
    };
    if ([NSThread isMainThread]) {
        send();
    } else {
        dispatch_async(dispatch_get_main_queue(), send);
    }
}

+ (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = tweakTopViewController();
        if (!top) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}

+ (NSString *)todoSessionDiagnostic {
    return ensureTodoSessionDiagnostic();
}

+ (NSString *)createTodoSessionDiagnostic {
    // 先走微信原生接口（内存创建 + 欢迎消息），结果只作备注，不提前返回
    NSString *managerResult = createTodoSessionViaManager();
    NSMutableArray *notes = [NSMutableArray arrayWithObject:managerResult];

    // 联系人数据库写入（让下次启动时微信能显示中文名）
    NSString *selfUsr = wechatSelfUsrName();
    NSString *md5 = selfUsr.length > 0 ? aiMD5Hex(selfUsr) : @"";

    // 第一步：写联系人（会话要显示名字，必须有联系人记录）
    NSArray *dbs = aiFindDatabaseFiles();
    BOOL contactWritten = NO;
    for (NSDictionary *d in dbs) {
        NSString *path = (NSString *)d[@"path"];
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
            if ([tbl.lowercaseString rangeOfString:@"contact"].location == NSNotFound) continue;
            NSArray *cols = aiSQLiteColumns(db, tbl);
            NSString *userCol = aiPickColumnName(cols, @[@"UserName", @"userName", @"m_nsUserName",
                                                         @"usrName", @"m_nsUsrName", @"ContactName"]);
            NSString *nickCol = aiPickColumnName(cols, @[@"NickName", @"nickName", @"m_nsNickName"]);
            if (!userCol || !nickCol) continue;
            // 已存在？
            sqlite3_stmt *stmt = NULL;
            int count = 0;
            NSString *existsSql = [NSString stringWithFormat:
                                   @"SELECT COUNT(*) FROM \"%@\" WHERE \"%@\" = ?", tbl, userCol];
            if (sqlite3_prepare_v2(db, [existsSql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, [kAITodoChatId UTF8String], -1, SQLITE_TRANSIENT);
                if (sqlite3_step(stmt) == SQLITE_ROW) count = sqlite3_column_int(stmt, 0);
            }
            sqlite3_finalize(stmt);
            if (count > 0) {
                [notes addObject:[NSString stringWithFormat:@"联系人已存在（%@）", tbl]];
                contactWritten = YES;
                sqlite3_close(db);
                break;
            }
            NSString *insertSql = [NSString stringWithFormat:
                                   @"INSERT INTO \"%@\" (\"%@\", \"%@\") VALUES (?, ?)",
                                   tbl, userCol, nickCol];
            sqlite3_stmt *istmt = NULL;
            int rc = sqlite3_prepare_v2(db, [insertSql UTF8String], -1, &istmt, NULL);
            if (rc == SQLITE_OK) {
                sqlite3_bind_text(istmt, 1, [kAITodoChatId UTF8String], -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(istmt, 2, [kAITodoNickName UTF8String], -1, SQLITE_TRANSIENT);
                rc = sqlite3_step(istmt);
            }
            sqlite3_finalize(istmt);
            sqlite3_close(db);
            if (rc == SQLITE_DONE) {
                [notes addObject:[NSString stringWithFormat:@"已写联系人（%@，列 %@/%@）",
                                  tbl, userCol, nickCol]];
                contactWritten = YES;
            } else {
                [notes addObject:[NSString stringWithFormat:@"联系人写入失败（%@ rc=%d）", tbl, rc]];
            }
            break;
        }
        if (contactWritten) break;
    }
    if (!contactWritten) {
        [notes addObject:@"未找到可写的联系人表（需 UserName+NickName 列）"];
    }
    [notes insertObject:@"——— 接口路径 ———" atIndex:0];
    [notes insertObject:@"——— 联系人路径 ———" atIndex:notes.count];

    // 第二步：写会话行
    for (NSDictionary *d in dbs) {
        NSString *path = (NSString *)d[@"path"];
        if ([path.lowercaseString rangeOfString:@"session"].location == NSNotFound) continue;
        // 只写当前账号的 session.db（账号目录下的优先）
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
            if (![tbl isEqualToString:@"SessionTable"]) continue;
            NSArray *cols = aiSQLiteColumns(db, tbl);
            if (![cols containsObject:@"sessionId"]) continue;
            // 已存在？
            sqlite3_stmt *stmt = NULL;
            int count = 0;
            NSString *existsSql = @"SELECT COUNT(*) FROM \"SessionTable\" WHERE \"sessionId\" = ?";
            if (sqlite3_prepare_v2(db, [existsSql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, [kAITodoChatId UTF8String], -1, SQLITE_TRANSIENT);
                if (sqlite3_step(stmt) == SQLITE_ROW) {
                    count = sqlite3_column_int(stmt, 0);
                }
            }
            sqlite3_finalize(stmt);
            if (count > 0) {
                sqlite3_close(db);
                [notes addObject:@"会话行已存在"];
                return [NSString stringWithFormat:@"✅ 创建完成\n%@\n若列表没出现，重启微信再看；异常可用“移除待办联系人”清理。",
                        [notes componentsJoinedByString:@"\n"]];
            }
            // 只填 sessionId，其余列交给默认值
            sqlite3_stmt *istmt = NULL;
            int rc = sqlite3_prepare_v2(db,
                                        "INSERT INTO \"SessionTable\" (\"sessionId\") VALUES (?)",
                                        -1, &istmt, NULL);
            if (rc == SQLITE_OK) {
                sqlite3_bind_text(istmt, 1, [kAITodoChatId UTF8String], -1, SQLITE_TRANSIENT);
                rc = sqlite3_step(istmt);
            }
            sqlite3_finalize(istmt);
            sqlite3_close(db);
            if (rc == SQLITE_DONE) {
                return [NSString stringWithFormat:
                        @"✅ 已写入待办联系人\n%@\n若列表没出现，重启微信再看；异常可用“移除待办联系人”清理。",
                        [notes componentsJoinedByString:@"\n"]];
            }
            return [NSString stringWithFormat:@"⚠️ 插入失败（rc=%d），可能需要更多必填列，见日志", rc];
        }
        sqlite3_close(db);
    }
    return [NSString stringWithFormat:@"未找到当前账号的 SessionTable（session.db）\n%@",
            [notes componentsJoinedByString:@"\n"]];
}

+ (NSString *)removeTodoSessionDiagnostic {
    NSString *selfUsr = wechatSelfUsrName();
    NSString *md5 = selfUsr.length > 0 ? aiMD5Hex(selfUsr) : @"";
    NSMutableArray *notes = [NSMutableArray array];
    // 先用微信接口删除内存会话
    Class mgrCls = NSClassFromString(@"MMNewSessionMgr");
    Class centerCls = NSClassFromString(@"MMServiceCenter");
    id center = centerCls ? [(id)centerCls defaultCenter] : nil;
    id mgr = center ? [center getService:mgrCls] : nil;
    if (mgr && [mgr respondsToSelector:@selector(DeleteSessionOfUser:)]) {
        @try {
            [mgr DeleteSessionOfUser:kAITodoChatId];
            [notes addObject:@"已通过微信接口删除内存会话"];
        } @catch (NSException *e) {
            [notes addObject:[NSString stringWithFormat:@"接口删除异常：%@", e]];
        }
    } else {
        [notes addObject:@"MMNewSessionMgr 无 DeleteSessionOfUser:"];
    }
    NSArray *dbs = aiFindDatabaseFiles();
    // 清理联系人
    for (NSDictionary *d in dbs) {
        NSString *path = (NSString *)d[@"path"];
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
            if ([tbl.lowercaseString rangeOfString:@"contact"].location == NSNotFound) continue;
            NSArray *cols = aiSQLiteColumns(db, tbl);
            if (![cols containsObject:@"UserName"]) continue;
            sqlite3_stmt *stmt = NULL;
            NSString *delSql = [NSString stringWithFormat:
                                @"DELETE FROM \"%@\" WHERE \"UserName\" = ?", tbl];
            int rc = sqlite3_prepare_v2(db, delSql.UTF8String, -1, &stmt, NULL);
            if (rc == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, [kAITodoChatId UTF8String], -1, SQLITE_TRANSIENT);
                rc = sqlite3_step(stmt);
            }
            sqlite3_finalize(stmt);
            if (rc == SQLITE_DONE) {
                [notes addObject:[NSString stringWithFormat:@"已清联系人（%@）", tbl]];
            }
        }
        sqlite3_close(db);
    }
    // 清理会话行
    for (NSDictionary *d in dbs) {
        NSString *path = (NSString *)d[@"path"];
        if ([path.lowercaseString rangeOfString:@"session"].location == NSNotFound) continue;
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
            if (![tbl isEqualToString:@"SessionTable"]) continue;
            sqlite3_stmt *stmt = NULL;
            int rc = sqlite3_prepare_v2(db,
                                        "DELETE FROM \"SessionTable\" WHERE \"sessionId\" = ?",
                                        -1, &stmt, NULL);
            if (rc == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, [kAITodoChatId UTF8String], -1, SQLITE_TRANSIENT);
                rc = sqlite3_step(stmt);
            }
            sqlite3_finalize(stmt);
            sqlite3_close(db);
            return rc == SQLITE_DONE
                ? [NSString stringWithFormat:@"🗑 已移除待办联系人\n%@", [notes componentsJoinedByString:@"\n"]]
                : [NSString stringWithFormat:@"⚠️ 移除失败（rc=%d）", rc];
        }
        sqlite3_close(db);
    }
    return [NSString stringWithFormat:@"未找到当前账号的 SessionTable（session.db）\n%@",
            [notes componentsJoinedByString:@"\n"]];
}

+ (NSString *)uiProbeDiagnostic {
    NSMutableArray *lines = [NSMutableArray array];

    // 1. ChatViewController 是否存在 + 常见初始化 selector（最优先）
    Class chatCls = NSClassFromString(@"ChatViewController");
    if (chatCls) {
        [lines addObject:@"== ChatViewController =="];
        NSArray *sels = @[@"initWithContactName:", @"setContactName:", @"setUserName:",
                          @"initWithUserName:", @"initWithChatRoomName:", @"initWithChatName:",
                          @"initWithContact:", @"setContact:"];
        for (NSString *s in sels) {
            if ([chatCls instancesRespondToSelector:NSSelectorFromString(s)]) {
                [lines addObject:[@"  ✔ " stringByAppendingString:s]];
            }
        }
    } else {
        [lines addObject:@"== ChatViewController 未加载（先打开任意聊天再探测）=="];
    }

    // 2. 会话管理类的方法（含 session/add/create/insert）
    for (NSString *cn in @[@"MainSessionMgr", @"MMNewSessionMgr"]) {
        Class cls = NSClassFromString(cn);
        if (!cls) continue;
        [lines addObject:[NSString stringWithFormat:@"== %@ ==", cn]];
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        int shown = 0;
        for (unsigned int i = 0; i < count && shown < 30; i++) {
            NSString *sel = NSStringFromSelector(method_getName(methods[i]));
            BOOL hit = [sel rangeOfString:@"session" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                       [sel hasPrefix:@"add"] || [sel hasPrefix:@"create"] || [sel hasPrefix:@"insert"];
            if (hit) {
                [lines addObject:[@"  " stringByAppendingString:sel]];
                shown++;
            }
        }
        free(methods);
    }

    // 2.5 会话对象类探测（构造 AddOrModifySession 需要）
    for (NSString *cn in @[@"WCContactSession", @"MMSession", @"WCSession", @"MMNewSession"]) {
        Class cls = NSClassFromString(cn);
        if (!cls) continue;
        [lines addObject:[NSString stringWithFormat:@"== %@ ==", cn]];
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        int shown = 0;
        for (unsigned int i = 0; i < count && shown < 20; i++) {
            NSString *sel = NSStringFromSelector(method_getName(methods[i]));
            if ([sel rangeOfString:@"userName" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [sel rangeOfString:@"nick" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [sel hasPrefix:@"set"] || [sel hasPrefix:@"init"]) {
                [lines addObject:[@"  " stringByAppendingString:sel]];
                shown++;
            }
        }
        free(methods);
        unsigned int pcount = 0;
        objc_property_t *props = class_copyPropertyList(cls, &pcount);
        for (unsigned int i = 0; i < pcount && i < 20; i++) {
            const char *pname = property_getName(props[i]);
            if (pname) [lines addObject:[NSString stringWithFormat:@"  prop: %s", pname]];
        }
        free(props);
    }

    // 3. 主界面类（只报关键候选）
    int classCount = objc_getClassList(NULL, 0);
    Class *classes = NULL;
    if (classCount > 0) {
        classes = (Class *)malloc(sizeof(Class) * (unsigned long)classCount);
        objc_getClassList(classes, classCount);
    }
    NSMutableArray *frames = [NSMutableArray array];
    for (int i = 0; i < classCount; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if ([name isEqualToString:@"NewMainFrameViewController"]) {
            [frames addObject:name];
        }
    }
    free(classes);
    if (frames.count > 0) {
        [lines addObject:@"== 主界面候选 =="];
        [lines addObject:[frames componentsJoinedByString:@"、"]];
    }

    // 4. 聊天界面类（名字含 Chat + ViewController，打开过聊天后应该已加载）
    NSMutableArray *chatVCs = [NSMutableArray array];
    classCount = objc_getClassList(NULL, 0);
    if (classCount > 0) {
        classes = (Class *)malloc(sizeof(Class) * (unsigned long)classCount);
        objc_getClassList(classes, classCount);
    }
    for (int i = 0; i < classCount; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if ([name rangeOfString:@"Chat"].location != NSNotFound &&
            [name rangeOfString:@"ViewController"].location != NSNotFound &&
            [name rangeOfString:@"NSKVONotifying"].location == NSNotFound) {
            [chatVCs addObject:name];
        }
    }
    free(classes);
    if (chatVCs.count > 0) {
        [lines addObject:@"== 聊天界面类 =="];
        [lines addObject:[chatVCs componentsJoinedByString:@"、"]];
    } else {
        [lines addObject:@"== 聊天界面类：未找到（打开聊天后再探测）=="];
    }

    // 5. 会话对象类（名字含 Session、非 Mgr，且带 userName/nick 属性或方法）
    NSMutableArray *sessionClasses = [NSMutableArray array];
    classCount = objc_getClassList(NULL, 0);
    if (classCount > 0) {
        classes = (Class *)malloc(sizeof(Class) * (unsigned long)classCount);
        objc_getClassList(classes, classCount);
    }
    for (int i = 0; i < classCount; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if ([name rangeOfString:@"Session"].location == NSNotFound) continue;
        if ([name rangeOfString:@"Mgr"].location != NSNotFound) continue;
        if ([name hasPrefix:@"NSKVONotifying"] || [name hasPrefix:@"WK"] || [name hasPrefix:@"WCSession"]) continue;
        Class c = classes[i];
        BOOL useful = NO;
        unsigned int pcount = 0;
        objc_property_t *props = class_copyPropertyList(c, &pcount);
        for (unsigned int j = 0; j < pcount; j++) {
            const char *pn = property_getName(props[j]);
            if (!pn) continue;
            NSString *ps = [NSString stringWithUTF8String:pn];
            if ([ps rangeOfString:@"userName" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [ps rangeOfString:@"nick" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                useful = YES;
                break;
            }
        }
        free(props);
        if (!useful) {
            unsigned int mcount = 0;
            Method *methods = class_copyMethodList(c, &mcount);
            for (unsigned int j = 0; j < mcount; j++) {
                NSString *sel = NSStringFromSelector(method_getName(methods[j]));
                if ([sel rangeOfString:@"userName" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                    [sel rangeOfString:@"setNick" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    useful = YES;
                    break;
                }
            }
            free(methods);
        }
        if (useful) [sessionClasses addObject:name];
    }
    free(classes);
    if (sessionClasses.count > 0) {
        [lines addObject:@"== 会话对象候选 =="];
        [lines addObject:[sessionClasses componentsJoinedByString:@"、"]];
    } else {
        [lines addObject:@"== 会话对象候选：未找到带 userName 的类 =="];
    }

    NSString *full = [lines componentsJoinedByString:@"\n"];
    return full.length ? full : @"无结果";
}

@end

#pragma mark - 消息 hook

static void (*orig_AsyncOnAddMsg)(id, SEL, id, CMessageWrap *);
static void (*orig_MainThreadNotifyToExt)(id, SEL, NSDictionary *);

static void swz_AsyncOnAddMsg(id self, SEL _cmd, id arg1, CMessageWrap *wrap) {
    if (orig_AsyncOnAddMsg) orig_AsyncOnAddMsg(self, _cmd, arg1, wrap);
    [WeChatTodoHandler handleIncomingMessage:wrap];
}

static void swz_MainThreadNotifyToExt(id self, SEL _cmd, NSDictionary *ext) {
    if (orig_MainThreadNotifyToExt) orig_MainThreadNotifyToExt(self, _cmd, ext);
    @try {
        if (![ext isKindOfClass:[NSDictionary class]]) return;
        CMessageWrap *wrap = ext[@"3"];
        if ([wrap isKindOfClass:NSClassFromString(@"CMessageWrap")]) {
            [WeChatTodoHandler handleIncomingMessage:wrap];
        }
    } @catch (NSException *e) {
        NSLog(kAITodoLogPrefix "MainThreadNotifyToExt 异常: %@", e);
    }
}

#pragma mark - 待办联系人（本机会话）

// —— 数据库工具（只读/只插入待办会话，不修改微信任何其他数据）——

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

// 返回表字段结构（带必填标记），如：UserName(必填), NickName, OrderFlag(必填)
static NSString *aiSQLiteColumnInfo(sqlite3 *db, NSString *table) {
    NSMutableArray *parts = [NSMutableArray array];
    NSString *safe = [table stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
    NSString *sql = [NSString stringWithFormat:@"PRAGMA table_info(\"%@\")", safe];
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const unsigned char *name = sqlite3_column_text(stmt, 1);
            int notnull = sqlite3_column_int(stmt, 3);
            if (!name) continue;
            NSString *n = [NSString stringWithUTF8String:(const char *)name];
            [parts addObject:notnull ? [n stringByAppendingString:@"(必填)"] : n];
        }
    }
    sqlite3_finalize(stmt);
    return [parts componentsJoinedByString:@", "];
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

// 只读探测会话库结构（绝不写微信数据库，避免闪退/损坏）。
// 待办联系人的展示后续改用 UI 插行方案，不走数据库写入。
static NSString *ensureTodoSessionDiagnostic(void) {
    NSMutableArray *candidateTables = [NSMutableArray array];
    NSMutableArray *contactTables = [NSMutableArray array];
    NSString *sessionTableColumns = @"";
    NSInteger sessionCount = 0, chatCount = 0;
    NSArray *dbs = aiFindDatabaseFiles();
    for (NSDictionary *d in dbs) {
        sqlite3 *db = NULL;
        if (sqlite3_open_v2([d[@"path"] UTF8String], &db,
                            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
            if (db) sqlite3_close(db);
            continue;
        }
        sqlite3_busy_timeout(db, 3000);
        NSArray *tables = aiSQLiteTableNames(db);
        for (NSString *tbl in tables) {
            NSString *lower = tbl.lowercaseString;
            BOOL isSessionLike = [lower rangeOfString:@"session"].location != NSNotFound;
            BOOL isChatLike = [lower rangeOfString:@"chat"].location != NSNotFound;
            if (isSessionLike || isChatLike) {
                if (isSessionLike) sessionCount++; else chatCount++;
                // 记录第一张会话表（SessionTable/session.db）的字段结构
                NSString *dbPath = (NSString *)d[@"path"];
                if (isSessionLike && sessionTableColumns.length == 0 &&
                    [dbPath.lowercaseString containsString:@"session"]) {
                    sessionTableColumns = [NSString stringWithFormat:
                                           @"\n%@ 列：%@", tbl, aiSQLiteColumnInfo(db, tbl)];
                }
                if (candidateTables.count < 15) {
                    [candidateTables addObject:[NSString stringWithFormat:@"%@(%@)", tbl,
                                                [d[@"path"] lastPathComponent]]];
                }
                continue;
            }
            if ([lower rangeOfString:@"contact"].location != NSNotFound ||
                [lower rangeOfString:@"friend"].location != NSNotFound) {
                if (contactTables.count < 4) {
                    NSArray *cols = aiSQLiteColumns(db, tbl);
                    [contactTables addObject:[NSString stringWithFormat:@"%@[%@]",
                                              tbl, [cols componentsJoinedByString:@","]]];
                }
            }
        }
        sqlite3_close(db);
    }
    NSString *contactLine = @"";
    if (contactTables.count > 0) {
        contactLine = [NSString stringWithFormat:@"\n联系人表：%@",
                       [contactTables componentsJoinedByString:@" | "]];
    }
    if (candidateTables.count > 0) {
        NSInteger total = sessionCount + chatCount;
        NSString *list = [candidateTables componentsJoinedByString:@"、"];
        if (total > 15) {
            list = [list stringByAppendingFormat:@"…等共 %ld 张", (long)total];
        }
        return [NSString stringWithFormat:
                @"只读探测完成：会话类表 %ld 张 / 聊天类表 %ld 张\n示例：%@%@\n待办联系人方案评估中（只读，未做任何写入）。",
                (long)sessionCount, (long)chatCount, list,
                [sessionTableColumns stringByAppendingString:contactLine]];
    }
    return @"只读探测：未找到 session/chat 相关表；写入已禁用（防闪退）。";
}

#pragma mark - hook 安装 / wcplugins 注册

static BOOL g_hooksInstalled = NO;

static int installHooks(void) {
    if (g_hooksInstalled) return 1; // 幂等：防止重复 swizzle 导致递归闪退
    Class cls = NSClassFromString(@"CMessageMgr");
    if (!cls) return 0;
    g_hooksInstalled = YES;
    Method recvMethod = class_getInstanceMethod(cls, @selector(AsyncOnAddMsg:MsgWrap:));
    if (recvMethod) {
        orig_AsyncOnAddMsg = (void *)method_getImplementation(recvMethod);
        method_setImplementation(recvMethod, (IMP)swz_AsyncOnAddMsg);
    }
    Method extMethod = class_getInstanceMethod(cls, @selector(MainThreadNotifyToExt:));
    if (extMethod) {
        orig_MainThreadNotifyToExt = (void *)method_getImplementation(extMethod);
        method_setImplementation(extMethod, (IMP)swz_MainThreadNotifyToExt);
    }
    return 1;
}

static void retryInstall(int remaining) {
    if (installHooks()) return;
    if (remaining <= 0) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        retryInstall(remaining - 1);
    });
}

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

__attribute__((constructor))
static void WeChatTodoInit(void) {
    NSLog(kAITodoLogPrefix "待办事项插件已加载…");
    g_dedupLock = [[NSObject alloc] init];
    g_seenKeys = [NSMutableSet set];
    g_seenOrder = [NSMutableArray array];
    g_replyLock = [[NSObject alloc] init];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidFinishLaunchingNotification"
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *note) {
        retryInstall(10);
        registerWithWCPlugins(10);
    }];

    retryInstall(10);
    registerWithWCPlugins(10);
}
