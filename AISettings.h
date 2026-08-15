#import <Foundation/Foundation.h>

// 待办插件设置（按微信账号分目录存储，切号互不串用）
@interface AISettings : NSObject

+(void)setCurrentAccount:(NSString *)usrName;
+(NSString *)currentAccount;

+(NSString *)memosURL;                // Memos 服务器地址（支持 IPv6，如 http://[2001:db8::1]:5230）
+(void)setMemosURL:(NSString *)url;
+(NSString *)memosToken;              // Memos Access Token
+(void)setMemosToken:(NSString *)token;
+(NSString *)memosVisibility;         // PRIVATE / PUBLIC / PROTECTED，默认 PRIVATE
+(void)setMemosVisibility:(NSString *)visibility;

@end
