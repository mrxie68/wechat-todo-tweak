#import "TodoSettingsViewController.h"
#import "AISettings.h"
#import "AITodoManager.h"
#import "AIConfig.h"

// 由 WeChatTodoTweak 提供（同一个 dylib 内）
@interface WeChatTodoHandler : NSObject
+ (NSString *)todoSessionDiagnostic;
@end

@interface TodoSettingsViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UITextField *tokenField;
@property (nonatomic, strong) UISegmentedControl *visibilityControl;
@property (nonatomic, strong) UILabel *sessionStatusLabel;
@end

@implementation TodoSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"待办事项设置";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];
    self.contentView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.scrollView addSubview:self.contentView];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(closeTapped)];

    CGFloat w = self.view.bounds.size.width;
    CGFloat x = 16;
    CGFloat cardW = w - 32;
    CGFloat y = 12;

    // 使用说明
    UILabel *intro = [[UILabel alloc] initWithFrame:CGRectMake(x, y, cardW, 60)];
    intro.text = @"在微信聊天列表的“待办事项”对话里发消息即可记录。\n命令：待办 / 完成 1 / 取消 1 / 删除 1 / 历史 / 同步 / 帮助";
    intro.numberOfLines = 0;
    intro.font = [UIFont systemFontOfSize:13];
    intro.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:intro];
    y += 60 + 12;

    // Memos 配置
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(x, y, cardW, 170)];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 12;
    [self.contentView addSubview:card];

    UILabel *urlLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, 90, 30)];
    urlLabel.text = @"Memos 地址";
    urlLabel.font = [UIFont systemFontOfSize:15];
    [card addSubview:urlLabel];
    self.urlField = [[UITextField alloc] initWithFrame:CGRectMake(110, 12, cardW - 130, 30)];
    self.urlField.placeholder = @"http://[IPv6地址]:5230";
    self.urlField.font = [UIFont systemFontOfSize:14];
    self.urlField.borderStyle = UITextBorderStyleRoundedRect;
    self.urlField.text = [AISettings memosURL];
    self.urlField.autocorrectionType = UITextAutocorrectionTypeNo;
    [card addSubview:self.urlField];

    UILabel *tokenLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 52, 90, 30)];
    tokenLabel.text = @"Token";
    tokenLabel.font = [UIFont systemFontOfSize:15];
    [card addSubview:tokenLabel];
    self.tokenField = [[UITextField alloc] initWithFrame:CGRectMake(110, 52, cardW - 130, 30)];
    self.tokenField.placeholder = @"Access Token";
    self.tokenField.font = [UIFont systemFontOfSize:14];
    self.tokenField.borderStyle = UITextBorderStyleRoundedRect;
    self.tokenField.text = [AISettings memosToken];
    self.tokenField.secureTextEntry = YES;
    self.tokenField.autocorrectionType = UITextAutocorrectionTypeNo;
    [card addSubview:self.tokenField];

    UILabel *visLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 92, 90, 30)];
    visLabel.text = @"可见性";
    visLabel.font = [UIFont systemFontOfSize:15];
    [card addSubview:visLabel];
    self.visibilityControl = [[UISegmentedControl alloc] initWithItems:@[@"PRIVATE", @"PUBLIC", @"PROTECTED"]];
    self.visibilityControl.frame = CGRectMake(110, 92, cardW - 130, 30);
    NSString *vis = [AISettings memosVisibility];
    self.visibilityControl.selectedSegmentIndex =
        [vis isEqualToString:@"PUBLIC"] ? 1 : ([vis isEqualToString:@"PROTECTED"] ? 2 : 0);
    [card addSubview:self.visibilityControl];

    UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
    save.frame = CGRectMake(16, 130, cardW - 32, 32);
    [save setTitle:@"保存配置" forState:UIControlStateNormal];
    [save addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:save];
    y += 170 + 12;

    // 操作按钮
    UIButton *syncBtn = [self makeButton:@"☁️ 同步未完成待办到 Memos"];
    syncBtn.frame = CGRectMake(x, y, cardW, 44);
    [syncBtn addTarget:self action:@selector(syncTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:syncBtn];
    y += 44 + 8;

    UIButton *openBtn = [self makeButton:@"🌐 打开 Memos 网页"];
    openBtn.frame = CGRectMake(x, y, cardW, 44);
    [openBtn addTarget:self action:@selector(openTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:openBtn];
    y += 44 + 12;

    // 待办联系人
    UIView *sessionCard = [[UIView alloc] initWithFrame:CGRectMake(x, y, cardW, 110)];
    sessionCard.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    sessionCard.layer.cornerRadius = 12;
    [self.contentView addSubview:sessionCard];
    UILabel *sessLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, cardW - 32, 20)];
    sessLabel.text = @"待办联系人";
    sessLabel.font = [UIFont systemFontOfSize:15];
    [sessionCard addSubview:sessLabel];
    self.sessionStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 38, cardW - 32, 40)];
    self.sessionStatusLabel.text = @"未检查";
    self.sessionStatusLabel.numberOfLines = 2;
    self.sessionStatusLabel.font = [UIFont systemFontOfSize:12];
    self.sessionStatusLabel.textColor = [UIColor secondaryLabelColor];
    [sessionCard addSubview:self.sessionStatusLabel];
    UIButton *createBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    createBtn.frame = CGRectMake(16, 76, cardW - 32, 28);
    [createBtn setTitle:@"检查待办联系人（只读探测）" forState:UIControlStateNormal];
    [createBtn addTarget:self action:@selector(checkSessionTapped) forControlEvents:UIControlEventTouchUpInside];
    [sessionCard addSubview:createBtn];
    y += 110 + 12;

    self.contentView.frame = CGRectMake(0, 0, w, y);
    self.scrollView.contentSize = CGSizeMake(w, y);

    [self refreshSessionStatus];
}

- (UIButton *)makeButton:(NSString *)title {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    btn.layer.cornerRadius = 12;
    return btn;
}

- (void)refreshSessionStatus {
    self.sessionStatusLabel.text = @"正在探测…";
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *diag = [WeChatTodoHandler todoSessionDiagnostic];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.sessionStatusLabel.text = diag;
        });
    });
}

- (void)saveTapped {
    NSString *url = [self.urlField.text stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [AISettings setMemosURL:url];
    [AISettings setMemosToken:[self.tokenField.text stringByTrimmingCharactersInSet:
                               [NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    NSArray *vs = @[@"PRIVATE", @"PUBLIC", @"PROTECTED"];
    [AISettings setMemosVisibility:vs[self.visibilityControl.selectedSegmentIndex]];
    UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"已保存"
                                                                message:@"Memos 配置已保存。"
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ok addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ok animated:YES completion:nil];
}

- (void)syncTapped {
    [self.view endEditing:YES];
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"正在同步"
                                                                     message:@"正在推送未完成待办到 Memos…\n\n"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progress animated:YES completion:nil];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *result = [AITodoManager syncToMemosNow];
        dispatch_async(dispatch_get_main_queue(), ^{
            [progress dismissViewControllerAnimated:NO completion:^{
                UIAlertController *r = [UIAlertController alertControllerWithTitle:@"同步结果"
                                                                           message:result
                                                                    preferredStyle:UIAlertControllerStyleAlert];
                [r addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:r animated:YES completion:nil];
            }];
        });
    });
}

- (void)openTapped {
    NSString *url = [AISettings memosURL];
    if (url.length == 0) {
        WeChatTodoHandler_todoAlert(@"还没配置 Memos 地址");
        return;
    }
    NSURL *u = [NSURL URLWithString:url];
    if (!u) {
        WeChatTodoHandler_todoAlert(@"Memos 地址格式不对");
        return;
    }
    if (@available(iOS 10.0, *)) {
        [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil];
    } else {
        [[UIApplication sharedApplication] openURL:u];
    }
}

- (void)checkSessionTapped {
    [self.view endEditing:YES];
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"正在探测"
                                                                     message:@"正在只读扫描会话库…\n\n"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progress animated:YES completion:nil];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *diag = [WeChatTodoHandler todoSessionDiagnostic];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.sessionStatusLabel.text = diag;
            [progress dismissViewControllerAnimated:NO completion:^{
                UIAlertController *r = [UIAlertController alertControllerWithTitle:@"待办联系人"
                                                                           message:diag
                                                                    preferredStyle:UIAlertControllerStyleAlert];
                [r addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:r animated:YES completion:nil];
            }];
        });
    });
}

static void WeChatTodoHandler_todoAlert(NSString *msg) {
    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"提示"
                                                               message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [top presentViewController:a animated:YES completion:nil];
}

- (void)closeTapped {
    if (self.navigationController.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    } else if (self.navigationController) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

@end
