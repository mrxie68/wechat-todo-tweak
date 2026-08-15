#import "AISettings.h"
#import "AIConfig.h"

static NSString * const kAISettingsMemosURLKey = @"WeChatTodoMemosURL";
static NSString * const kAISettingsMemosTokenKey = @"WeChatTodoMemosToken";
static NSString * const kAISettingsMemosVisibilityKey = @"WeChatTodoMemosVisibility";

static NSString *g_currentAccount = nil;

@implementation AISettings

+(void)setCurrentAccount:(NSString *)usrName {
    @synchronized (self) {
        if (usrName.length == 0) return;
        if (![g_currentAccount isEqualToString:usrName]) {
            g_currentAccount = [usrName copy];
        }
    }
}

+(NSString *)currentAccount {
    @synchronized (self) {
        return g_currentAccount;
    }
}

+(NSString *)namespacedKey:(NSString *)base {
    @synchronized (self) {
        if (g_currentAccount.length == 0) return base;
        return [NSString stringWithFormat:@"%@_%@", base, g_currentAccount];
    }
}

+(NSString *)memosURL {
    return [[NSUserDefaults standardUserDefaults]
            stringForKey:[self namespacedKey:kAISettingsMemosURLKey]] ?: @"";
}

+(void)setMemosURL:(NSString *)url {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsMemosURLKey];
    if (url.length > 0) {
        [defaults setObject:url forKey:key];
    } else {
        [defaults removeObjectForKey:key];
    }
    [defaults synchronize];
}

+(NSString *)memosToken {
    return [[NSUserDefaults standardUserDefaults]
            stringForKey:[self namespacedKey:kAISettingsMemosTokenKey]] ?: @"";
}

+(void)setMemosToken:(NSString *)token {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsMemosTokenKey];
    if (token.length > 0) {
        [defaults setObject:token forKey:key];
    } else {
        [defaults removeObjectForKey:key];
    }
    [defaults synchronize];
}

+(NSString *)memosVisibility {
    NSString *stored = [[NSUserDefaults standardUserDefaults]
                        stringForKey:[self namespacedKey:kAISettingsMemosVisibilityKey]];
    if (stored.length > 0) return stored;
    return @"PRIVATE";
}

+(void)setMemosVisibility:(NSString *)visibility {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:visibility.length > 0 ? visibility : @"PRIVATE"
                 forKey:[self namespacedKey:kAISettingsMemosVisibilityKey]];
    [defaults synchronize];
}

@end
