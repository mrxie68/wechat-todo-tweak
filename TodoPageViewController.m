#import "TodoPageViewController.h"
#import "AITodoManager.h"
#import "AISettings.h"
#import "TodoSettingsViewController.h"
#import "AIConfig.h"

// 时间戳转可读时间
static NSString *todoDateString(double ts) {
    if (ts <= 0) return @"";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm";
    return [fmt stringFromDate:date];
}

@interface TodoPageViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UISegmentedControl *segmentControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *addButton;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIView *statsCard;
@property (nonatomic, strong) UILabel *todoCountLabel;
@property (nonatomic, strong) UILabel *todoTitleLabel;
@property (nonatomic, strong) UILabel *doneCountLabel;
@property (nonatomic, strong) UILabel *doneTitleLabel;
@property (nonatomic, strong) NSMutableArray *filteredTodos;
@property (nonatomic, assign) CGFloat keyboardInset;
@end

@implementation TodoPageViewController

+ (void)presentFrom:(UIViewController *)host {
    if (!host) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (host.presentedViewController) return; // 已有弹层时不重复弹出
        TodoPageViewController *vc = [[TodoPageViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        if (@available(iOS 13.0, *)) {
            // 强制浅色外观：避免微信深色模式下顶部变黑，页面更清爽
            nav.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
            vc.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
            UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
            [appearance configureWithOpaqueBackground];
            appearance.backgroundColor = [UIColor whiteColor];
            appearance.shadowColor = [UIColor clearColor];
            nav.navigationBar.standardAppearance = appearance;
            nav.navigationBar.scrollEdgeAppearance = appearance;
            nav.navigationBar.compactAppearance = appearance;
        }
        [host presentViewController:nav animated:YES completion:nil];
    });
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"待办事项";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    // 内容从导航栏下方开始，避免和标题栏重叠
    self.edgesForExtendedLayout = UIRectEdgeNone;

    // 点击空白处收起键盘
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    tap.delegate = self;
    [self.view addGestureRecognizer:tap];

    // 关闭
    UIImage *down = [UIImage systemImageNamed:@"chevron.down"];
    if (down) {
        self.navigationItem.leftBarButtonItem =
            [[UIBarButtonItem alloc] initWithImage:down
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(closeTapped)];
    } else {
        self.navigationItem.leftBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"关闭"
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(closeTapped)];
    }

    UIBarButtonItem *settingsItem =
        [[UIBarButtonItem alloc] initWithTitle:@"设置"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(settingsTapped)];
    UIBarButtonItem *syncItem =
        [[UIBarButtonItem alloc] initWithTitle:@"同步"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(syncTapped)];
    self.navigationItem.rightBarButtonItems = @[settingsItem, syncItem];

    // 统计卡片：未完成 / 已完成
    self.statsCard = [[UIView alloc] initWithFrame:CGRectZero];
    self.statsCard.backgroundColor = [UIColor whiteColor];
    self.statsCard.layer.cornerRadius = 14;
    self.statsCard.layer.shadowColor = [UIColor blackColor].CGColor;
    self.statsCard.layer.shadowOpacity = 0.05;
    self.statsCard.layer.shadowOffset = CGSizeMake(0, 2);
    self.statsCard.layer.shadowRadius = 6;
    [self.view addSubview:self.statsCard];

    self.todoCountLabel = [self bigNumberLabel];
    self.todoTitleLabel = [self smallCaptionLabel:@"未完成"];
    [self.statsCard addSubview:self.todoCountLabel];
    [self.statsCard addSubview:self.todoTitleLabel];

    self.doneCountLabel = [self bigNumberLabel];
    self.doneTitleLabel = [self smallCaptionLabel:@"已完成"];
    [self.statsCard addSubview:self.doneCountLabel];
    [self.statsCard addSubview:self.doneTitleLabel];

    // 分段：待办 / 已完成 / 全部
    self.segmentControl = [[UISegmentedControl alloc] initWithItems:@[@"待办", @"已完成", @"全部"]];
    self.segmentControl.selectedSegmentIndex = 0;
    [self.segmentControl addTarget:self
                            action:@selector(segmentChanged)
                  forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.segmentControl];

    // 列表（insetGrouped：圆角卡片行，更像原生待办 App）
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.tableView];

    // 空状态
    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];

    // 底部输入栏
    self.inputBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.inputBar.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.inputBar];

    self.inputField = [[UITextField alloc] initWithFrame:CGRectZero];
    self.inputField.placeholder = @"记一条待办…";
    self.inputField.font = [UIFont systemFontOfSize:15];
    self.inputField.backgroundColor = [UIColor systemGray6Color];
    self.inputField.layer.cornerRadius = 18;
    self.inputField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 36)];
    self.inputField.leftViewMode = UITextFieldViewModeAlways;
    self.inputField.returnKeyType = UIReturnKeyDone;
    self.inputField.delegate = self;
    self.inputField.autocorrectionType = UITextAutocorrectionTypeNo;
    [self.inputBar addSubview:self.inputField];

    self.addButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.addButton setTitle:@"添加" forState:UIControlStateNormal];
    [self.addButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.addButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.addButton.backgroundColor = [UIColor systemGreenColor];
    self.addButton.layer.cornerRadius = 18;
    [self.addButton addTarget:self
                       action:@selector(addTapped)
             forControlEvents:UIControlEventTouchUpInside];
    [self.inputBar addSubview:self.addButton];

    // 键盘跟随
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
}

- (UILabel *)bigNumberLabel {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = [UIFont boldSystemFontOfSize:26];
    l.textColor = [UIColor labelColor];
    l.textAlignment = NSTextAlignmentCenter;
    return l;
}

- (UILabel *)smallCaptionLabel:(NSString *)text {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = [UIFont systemFontOfSize:12];
    l.textColor = [UIColor secondaryLabelColor];
    l.textAlignment = NSTextAlignmentCenter;
    return l;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadItems];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    UIEdgeInsets sa = self.view.safeAreaInsets;

    CGFloat cardW = b.size.width - 32;
    CGFloat cardH = 64;
    CGFloat cardTop = sa.top + 12;
    self.statsCard.frame = CGRectMake(16, cardTop, cardW, cardH);
    CGFloat half = cardW / 2.0;
    self.todoCountLabel.frame = CGRectMake(0, 12, half, 30);
    self.todoTitleLabel.frame = CGRectMake(0, 44, half, 16);
    self.doneCountLabel.frame = CGRectMake(half, 12, half, 30);
    self.doneTitleLabel.frame = CGRectMake(half, 44, half, 16);

    CGFloat segTop = cardTop + cardH + 12;
    self.segmentControl.frame = CGRectMake(16, segTop, cardW, 32);

    CGFloat tableTop = segTop + 32 + 12;

    CGFloat barContentH = 54;
    CGFloat barH = barContentH + (self.keyboardInset > 0 ? 0 : sa.bottom);
    CGFloat barBottom = b.size.height - self.keyboardInset;
    self.inputBar.frame = CGRectMake(0, barBottom - barH, b.size.width, barH);

    CGFloat fieldH = 36;
    CGFloat btnW = 64;
    CGFloat fieldY = (barContentH - fieldH) / 2.0;
    self.inputField.frame = CGRectMake(16, fieldY, b.size.width - 32 - btnW - 10, fieldH);
    self.addButton.frame = CGRectMake(b.size.width - 16 - btnW, fieldY, btnW, fieldH);

    self.tableView.frame = CGRectMake(0, tableTop, b.size.width, barBottom - tableTop);
    self.emptyLabel.frame = CGRectMake(32, tableTop + 60, b.size.width - 64, 90);
}

#pragma mark - 数据

- (void)reloadItems {
    NSArray *all = [AITodoManager allTodos];
    NSMutableArray *filtered = [NSMutableArray array];
    NSInteger seg = self.segmentControl.selectedSegmentIndex;
    for (NSDictionary *t in all) {
        BOOL done = [t[@"done"] boolValue];
        if (seg == 0 && done) continue;
        if (seg == 1 && !done) continue;
        [filtered addObject:t];
    }
    // 未完成在前，同状态按编号倒序
    [filtered sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        BOOL da = [a[@"done"] boolValue];
        BOOL db = [b[@"done"] boolValue];
        if (da != db) return da ? NSOrderedDescending : NSOrderedAscending;
        return [b[@"id"] compare:a[@"id"]];
    }];
    self.filteredTodos = filtered;
    [self.tableView reloadData];

    NSUInteger undone = 0, completed = 0;
    for (NSDictionary *t in all) {
        if ([t[@"done"] boolValue]) completed++;
        else undone++;
    }
    self.todoCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)undone];
    self.doneCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)completed];
    self.todoCountLabel.textColor = undone > 0 ? [UIColor systemGreenColor] : [UIColor systemGray3Color];
    self.doneCountLabel.textColor = completed > 0 ? [UIColor secondaryLabelColor] : [UIColor systemGray3Color];

    BOOL empty = (filtered.count == 0);
    self.tableView.hidden = empty;
    self.emptyLabel.hidden = !empty;
    if (seg == 1) {
        self.emptyLabel.text = @"还没有已完成的待办\n完成一条后会自动出现在这里";
    } else {
        self.emptyLabel.text = @"暂无待办 📋\n在下方输入一条吧";
    }

    // 已完成分组底部放“清空已完成”
    if (seg == 1 && filtered.count > 0) {
        UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [clearBtn setTitle:@"清空已完成" forState:UIControlStateNormal];
        [clearBtn setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
        [clearBtn addTarget:self action:@selector(clearDoneTapped) forControlEvents:UIControlEventTouchUpInside];
        clearBtn.frame = CGRectMake(0, 0, 0, 44);
        self.tableView.tableFooterView = clearBtn;
    } else {
        self.tableView.tableFooterView = nil;
    }

    self.title = undone > 0 ? [NSString stringWithFormat:@"待办（%lu）", (unsigned long)undone]
                            : @"待办事项";
}

- (void)segmentChanged {
    [self reloadItems];
}

#pragma mark - 表格

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredTodos.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TodoCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"TodoCell"];
    }
    NSDictionary *t = self.filteredTodos[indexPath.row];
    BOOL done = [t[@"done"] boolValue];
    NSString *content = t[@"content"] ?: @"";

    if (done) {
        cell.textLabel.attributedText =
            [[NSAttributedString alloc] initWithString:content
                                            attributes:@{NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle)}];
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        cell.textLabel.attributedText = nil;
        cell.textLabel.text = content;
        cell.textLabel.textColor = [UIColor labelColor];
    }

    double created = [t[@"created"] doubleValue];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"#%@ · %@",
                                 t[@"id"], todoDateString(created)];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    UIImage *img = [UIImage systemImageNamed:done ? @"checkmark.circle.fill" : @"circle"];
    if (!img) {
        img = [self textImage:done ? @"☑" : @"☐"];
    } else {
        img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    cell.imageView.image = img;
    cell.imageView.tintColor = done ? [UIColor systemGreenColor] : [UIColor systemGray3Color];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *t = self.filteredTodos[indexPath.row];
    [AITodoManager markTodo:[t[@"id"] integerValue] done:![t[@"done"] boolValue]];
    [self reloadItems];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (NSString *)tableView:(UITableView *)tableView
    titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return @"删除";
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    NSDictionary *t = self.filteredTodos[indexPath.row];
    [AITodoManager deleteTodo:[t[@"id"] integerValue]];
    [self reloadItems];
}

#pragma mark - 操作

- (void)addTapped {
    NSString *text = [self.inputField.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) return;
    self.segmentControl.selectedSegmentIndex = 0;
    [AITodoManager addTodo:text];
    self.inputField.text = @"";
    [self reloadItems];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self addTapped];
    return YES;
}

- (void)clearDoneTapped {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"清空已完成"
                                                                     message:@"确定删除所有已完成的待办吗？"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"清空"
                                                style:UIAlertActionStyleDestructive
                                              handler:^(UIAlertAction *action) {
        [AITodoManager clearDone];
        [self reloadItems];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)syncTapped {
    [self.view endEditing:YES];
    UIAlertController *progress =
        [UIAlertController alertControllerWithTitle:@"正在同步"
                                            message:@"正在推送未完成待办到 Memos…\n\n"
                                     preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progress animated:YES completion:nil];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *result = [AITodoManager syncToMemosNow];
        dispatch_async(dispatch_get_main_queue(), ^{
            [progress dismissViewControllerAnimated:NO completion:^{
                UIAlertController *r =
                    [UIAlertController alertControllerWithTitle:@"同步结果"
                                                        message:result
                                                 preferredStyle:UIAlertControllerStyleAlert];
                [r addAction:[UIAlertAction actionWithTitle:@"知道了"
                                                      style:UIAlertActionStyleDefault
                                                    handler:nil]];
                [self presentViewController:r animated:YES completion:nil];
            }];
        });
    });
}

- (void)settingsTapped {
    [self.view endEditing:YES];
    TodoSettingsViewController *vc = [[TodoSettingsViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 键盘

- (void)keyboardWillChange:(NSNotification *)note {
    CGRect kbEnd = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect kbInView = [self.view convertRect:kbEnd fromView:nil];
    CGFloat covered = self.view.bounds.size.height - CGRectGetMinY(kbInView);
    self.keyboardInset = MAX(0, covered);
    [UIView animateWithDuration:0.25 animations:^{
        [self.view layoutIfNeeded];
    }];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    // 输入框/按钮上的点击不拦截，其余空白处点击收起键盘
    if ([touch.view isKindOfClass:[UIControl class]] ||
        [touch.view isKindOfClass:[UITextField class]] ||
        [touch.view isKindOfClass:[UITextView class]]) {
        return NO;
    }
    return YES;
}

#pragma mark - 工具

- (UIImage *)textImage:(NSString *)text {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(24, 24), NO, 0);
    [text drawInRect:CGRectMake(0, 3, 24, 20)
      withAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16]}];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@end
