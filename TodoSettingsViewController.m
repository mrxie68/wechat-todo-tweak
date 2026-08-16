#import "TodoSettingsViewController.h"
#import "AISettings.h"
#import "AITodoManager.h"
#import "CustomCalendarTodoViewController.h"
#import "AIConfig.h"

extern NSString *todoTabDiagnostic(void); // 由 WeChatTodoTweak.m 提供

@interface TodoSettingsViewController () <UITextFieldDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

@property (nonatomic, strong) UIView *introCard;
@property (nonatomic, strong) UILabel *introLabel;
@property (nonatomic, strong) UIView *actionCard;
@property (nonatomic, strong) UIButton *openButton;
@property (nonatomic, strong) UIButton *diagButton;
@property (nonatomic, strong) UIView *memosCard;
@property (nonatomic, strong) UILabel *urlLabel;
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UILabel *tokenLabel;
@property (nonatomic, strong) UITextField *tokenField;
@property (nonatomic, strong) UILabel *visLabel;
@property (nonatomic, strong) UISegmentedControl *visibilityControl;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIView *opCard;
@property (nonatomic, strong) UIButton *syncButton;
@property (nonatomic, strong) UIButton *webButton;
@property (nonatomic, strong) UIView *versionCard;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UILabel *versionValueLabel;
@end

static void todoAlert(NSString *msg);

@implementation TodoSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"待办事项";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    // 点击空白处收起键盘（点在输入框/按钮/控件上不触发）
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    tap.delegate = self;
    [self.view addGestureRecognizer:tap];

    self.contentView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.scrollView addSubview:self.contentView];

    // 被 wcplugins 兜底弹出时才显示“关闭”；挂进微信设置页时用微信原生返回
    if (self.navigationController.presentingViewController) {
        self.navigationItem.leftBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"关闭"
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(closeTapped)];
    }

    [self buildUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 不做任何导航栏样式篡改：被微信 push 时保持微信原生外观，避免转场闪黑/主题被破坏
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ([touch.view isKindOfClass:[UITextField class]] ||
        [touch.view isKindOfClass:[UIButton class]] ||
        [touch.view isKindOfClass:[UISegmentedControl class]]) {
        return NO;
    }
    return YES;
}

#pragma mark - UI 构建

- (void)buildUI {
    self.introCard = [self makeCard];
    self.introLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.introLabel.text = @"微信设置页新增「待办事项」入口：\n记录待办、勾选完成、收藏书签，可与 Memos 同步。";
    self.introLabel.numberOfLines = 0;
    self.introLabel.font = [UIFont systemFontOfSize:13];
    self.introLabel.textColor = [UIColor secondaryLabelColor];
    [self.introCard addSubview:self.introLabel];
    [self.contentView addSubview:self.introCard];

    self.actionCard = [self makeCard];
    self.openButton = [self makeRowButton:@"📋 打开待办页"];
    [self.openButton addTarget:self action:@selector(openTodoTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.actionCard addSubview:self.openButton];
    self.diagButton = [self makeRowButton:@"🔍 诊断（底部菜单，复制到剪贴板）"];
    [self.diagButton addTarget:self action:@selector(diagTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.actionCard addSubview:self.diagButton];
    [self.contentView addSubview:self.actionCard];

    self.memosCard = [self makeCard];
    self.urlLabel = [self makeRowLabel:@"Memos 地址"];
    [self.memosCard addSubview:self.urlLabel];
    self.urlField = [self makeRowField:@"http://[IPv6地址]:5230"];
    self.urlField.text = [AISettings memosURL];
    [self.memosCard addSubview:self.urlField];
    self.tokenLabel = [self makeRowLabel:@"Token"];
    [self.memosCard addSubview:self.tokenLabel];
    self.tokenField = [self makeRowField:@"Access Token"];
    self.tokenField.text = [AISettings memosToken];
    self.tokenField.secureTextEntry = YES;
    [self.memosCard addSubview:self.tokenField];
    self.visLabel = [self makeRowLabel:@"可见性"];
    [self.memosCard addSubview:self.visLabel];
    self.visibilityControl = [[UISegmentedControl alloc] initWithItems:@[@"PRIVATE", @"PUBLIC", @"PROTECTED"]];
    NSString *vis = [AISettings memosVisibility];
    self.visibilityControl.selectedSegmentIndex =
        [vis isEqualToString:@"PUBLIC"] ? 1 : ([vis isEqualToString:@"PROTECTED"] ? 2 : 0);
    [self.memosCard addSubview:self.visibilityControl];
    self.saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.saveButton setTitle:@"保存配置" forState:UIControlStateNormal];
    self.saveButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [self.saveButton addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.memosCard addSubview:self.saveButton];
    [self.contentView addSubview:self.memosCard];

    self.opCard = [self makeCard];
    self.syncButton = [self makeRowButton:@"☁️ 同步未完成待办到 Memos"];
    [self.syncButton addTarget:self action:@selector(syncTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.opCard addSubview:self.syncButton];
    self.webButton = [self makeRowButton:@"🌐 打开 Memos 网页"];
    [self.webButton addTarget:self action:@selector(openTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.opCard addSubview:self.webButton];
    [self.contentView addSubview:self.opCard];

    self.versionCard = [self makeCard];
    self.versionLabel = [self makeRowLabel:@"插件版本"];
    [self.versionCard addSubview:self.versionLabel];
    self.versionValueLabel = [self makeRowLabel:kAITodoVersion];
    self.versionValueLabel.textColor = [UIColor secondaryLabelColor];
    self.versionValueLabel.textAlignment = NSTextAlignmentRight;
    [self.versionCard addSubview:self.versionValueLabel];
    [self.contentView addSubview:self.versionCard];

    [self layoutCards];
}

- (UIView *)makeCard {
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 12;
    card.layer.masksToBounds = YES;
    return card;
}

- (UILabel *)makeRowLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.font = [UIFont systemFontOfSize:16];
    label.textColor = [UIColor labelColor];
    return label;
}

- (UITextField *)makeRowField:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
    field.placeholder = placeholder;
    field.borderStyle = UITextBorderStyleNone;
    field.font = [UIFont systemFontOfSize:15];
    field.textAlignment = NSTextAlignmentRight;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.delegate = self;
    return field;
}

- (UIButton *)makeRowButton:(NSString *)title {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:16];
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    btn.titleEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 0);
    return btn;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.scrollView.frame = self.view.bounds;
    [self layoutCards];
}

- (void)layoutCards {
    CGFloat width = self.view.bounds.size.width;
    CGFloat x = 16;
    CGFloat cardW = width - 32;
    CGFloat y = 12;

    self.introCard.frame = CGRectMake(x, y, cardW, 64);
    self.introLabel.frame = CGRectMake(16, 10, cardW - 32, 44);
    y += 64 + 12;

    self.actionCard.frame = CGRectMake(x, y, cardW, 96);
    self.openButton.frame = CGRectMake(0, 0, cardW, 48);
    self.diagButton.frame = CGRectMake(0, 48, cardW, 48);
    y += 96 + 12;

    self.memosCard.frame = CGRectMake(x, y, cardW, 192);
    self.urlLabel.frame = CGRectMake(16, 0, 110, 48);
    self.urlField.frame = CGRectMake(130, 0, cardW - 146, 48);
    self.tokenLabel.frame = CGRectMake(16, 48, 110, 48);
    self.tokenField.frame = CGRectMake(130, 48, cardW - 146, 48);
    self.visLabel.frame = CGRectMake(16, 96, 110, 48);
    self.visibilityControl.frame = CGRectMake(130, 104, cardW - 146, 32);
    self.saveButton.frame = CGRectMake(16, 140, cardW - 32, 44);
    y += 192 + 12;

    self.opCard.frame = CGRectMake(x, y, cardW, 96);
    self.syncButton.frame = CGRectMake(0, 0, cardW, 48);
    self.webButton.frame = CGRectMake(0, 48, cardW, 48);
    y += 96 + 12;

    self.versionCard.frame = CGRectMake(x, y, cardW, 48);
    self.versionLabel.frame = CGRectMake(16, 0, cardW - 160, 48);
    self.versionValueLabel.frame = CGRectMake(cardW - 140, 0, 124, 48);
    y += 48 + 20;

    self.contentView.frame = CGRectMake(0, 0, width, y);
    self.scrollView.contentSize = CGSizeMake(width, y);
}

#pragma mark - 操作

- (void)openTodoTapped {
    [self.view endEditing:YES];
    [CustomCalendarTodoViewController presentFrom:self];
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

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end

static void todoAlert(NSString *msg) {
    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"提示"
                                                               message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [top presentViewController:a animated:YES completion:nil];
}
