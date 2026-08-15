#import "TodoSettingsViewController.h"
#import "AISettings.h"
#import "AITodoManager.h"
#import "TodoPageViewController.h"
#import "AIConfig.h"

extern NSString *todoTabDiagnostic(void); // 由 WeChatTodoTweak.m 提供

@interface TodoSettingsViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UITextField *tokenField;
@property (nonatomic, strong) UISegmentedControl *visibilityControl;
@end

static void todoAlert(NSString *msg); // 前向声明

@implementation TodoSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"待办事项设置";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    // 内容从导航栏下方开始，避免和标题栏重叠
    self.edgesForExtendedLayout = UIRectEdgeNone;

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
    intro.text = @"微信底部菜单新增「待办」tab，点它直接进待办页。\n像普通待办 App 一样：添加、勾选、删除、同步。";
    intro.numberOfLines = 0;
    intro.font = [UIFont systemFontOfSize:13];
    intro.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:intro];
    y += 60 + 12;

    // 打开待办页
    UIButton *openBtn = [self makeButton:@"📋 打开待办页"];
    openBtn.frame = CGRectMake(x, y, cardW, 44);
    [openBtn addTarget:self action:@selector(openTodoTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:openBtn];
    y += 44 + 12;

    // 手势诊断
    UIButton *diagBtn = [self makeButton:@"🔍 诊断（底部菜单，复制到剪贴板）"];
    diagBtn.frame = CGRectMake(x, y, cardW, 44);
    [diagBtn addTarget:self action:@selector(diagTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:diagBtn];
    y += 44 + 12;

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
    self.urlField.delegate = self;
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

    UIButton *webBtn = [self makeButton:@"🌐 打开 Memos 网页"];
    webBtn.frame = CGRectMake(x, y, cardW, 44);
    [webBtn addTarget:self action:@selector(openTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:webBtn];
    y += 44 + 12;

    UILabel *versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, y, w, 24)];
    versionLabel.text = [NSString stringWithFormat:@"待办插件 v%@", kAITodoVersion];
    versionLabel.textAlignment = NSTextAlignmentCenter;
    versionLabel.font = [UIFont systemFontOfSize:12];
    versionLabel.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:versionLabel];
    y += 24 + 12;

    self.contentView.frame = CGRectMake(0, 0, w, y);
    self.scrollView.contentSize = CGSizeMake(w, y);
}

- (UIButton *)makeButton:(NSString *)title {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    btn.layer.cornerRadius = 12;
    return btn;
}

- (void)openTodoTapped {
    [self.view endEditing:YES];
    [TodoPageViewController presentFrom:self];
}

// 诊断结果：完整内容复制剪贴板，弹窗只显示摘要；2 分钟后自动清空剪贴板（用完即销毁）
- (NSString *)consumeDiagnostic:(NSString *)full {
    [[UIPasteboard generalPasteboard] setString:full];
    NSString *copied = [full copy];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(120 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if ([[[UIPasteboard generalPasteboard] string] isEqualToString:copied]) {
            [[UIPasteboard generalPasteboard] setString:@""];
        }
    });
    if (full.length > 180) {
        return [[full substringToIndex:180] stringByAppendingString:
                @"\n…（完整已复制到剪贴板，2 分钟后自动清除）"];
    }
    return full;
}

- (void)diagTapped {
    [self.view endEditing:YES];
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"正在诊断"
                                                                     message:@"正在读取底部菜单结构…\n\n"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progress animated:YES completion:nil];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block NSString *diag = nil;
        // 诊断会读 UI 层级，必须在主线程执行
        dispatch_sync(dispatch_get_main_queue(), ^{
            diag = todoTabDiagnostic();
        });
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *shortText = [self consumeDiagnostic:diag];
            [progress dismissViewControllerAnimated:NO completion:^{
                UIAlertController *r = [UIAlertController alertControllerWithTitle:@"诊断结果"
                                                                           message:shortText
                                                                    preferredStyle:UIAlertControllerStyleAlert];
                [r addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:r animated:YES completion:nil];
            }];
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
        todoAlert(@"还没配置 Memos 地址");
        return;
    }
    NSURL *u = [NSURL URLWithString:url];
    if (!u) {
        todoAlert(@"Memos 地址格式不对");
        return;
    }
    if (@available(iOS 10.0, *)) {
        [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil];
    } else {
        [[UIApplication sharedApplication] openURL:u];
    }
}

static void todoAlert(NSString *msg) {
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
