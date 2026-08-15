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

@interface TodoPageViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UISegmentedControl *segmentControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *addButton;
@property (nonatomic, strong) UILabel *emptyLabel;
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

    // 分段：待办 / 已完成 / 全部
    self.segmentControl = [[UISegmentedControl alloc] initWithItems:@[@"待办", @"已完成", @"全部"]];
    self.segmentControl.selectedSegmentIndex = 0;
    [self.segmentControl addTarget:self
                            action:@selector(segmentChanged)
                  forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.segmentControl];

    // 列表
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
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
    self.inputBar.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    [self.view addSubview:self.inputBar];

    self.inputField = [[UITextField alloc] initWithFrame:CGRectZero];
    self.inputField.placeholder = @"记一条待办…";
    self.inputField.borderStyle = UITextBorderStyleRoundedRect;
    self.inputField.returnKeyType = UIReturnKeyDone;
    self.inputField.delegate = self;
    self.inputField.autocorrectionType = UITextAutocorrectionTypeNo;
    [self.inputBar addSubview:self.inputField];

    self.addButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.addButton setTitle:@"添加" forState:UIControlStateNormal];
    self.addButton.backgroundColor = [UIColor systemGray5Color];
    self.addButton.layer.cornerRadius = 8;
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

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadItems];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGRect b = self.view.bounds;
    UIEdgeInsets sa = self.view.safeAreaInsets;

    CGFloat segY = 10.0;
    CGFloat segH = 32.0;
    self.segmentControl.frame = CGRectMake(16, segY, b.size.width - 32, segH);

    CGFloat barH = 50.0 + (self.keyboardInset > 0 ? 0 : sa.bottom);
    CGFloat barBottom = b.size.height - self.keyboardInset;
    self.inputBar.frame = CGRectMake(0, barBottom - barH, b.size.width, barH);

    CGFloat fieldH = 34.0;
    CGFloat btnW = 60.0;
    CGFloat btnGap = 8.0;
    self.inputField.frame = CGRectMake(16, (barH - fieldH) / 2.0,
                                       b.size.width - 32 - btnW - btnGap, fieldH);
    self.addButton.frame = CGRectMake(b.size.width - 16 - btnW, (barH - fieldH) / 2.0,
                                      btnW, fieldH);

    CGFloat tableTop = segY + segH + 8;
    self.tableView.frame = CGRectMake(0, tableTop, b.size.width, barBottom - tableTop);
    self.emptyLabel.frame = CGRectMake(16, tableTop + 48, b.size.width - 32, 80);
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

    BOOL empty = (filtered.count == 0);
    self.tableView.hidden = empty;
    self.emptyLabel.hidden = !empty;
    if (seg == 1) {
        self.emptyLabel.text = @"还没有已完成的待办";
    } else {
        self.emptyLabel.text = @"暂无待办 📋\n在下方输入一条吧";
    }

    NSUInteger undone = [AITodoManager unfinishedCount];
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
    cell.detailTextLabel.text = [NSString stringWithFormat:@"#%@  %@",
                                 t[@"id"], todoDateString(created)];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    UIImage *img = [UIImage systemImageNamed:done ? @"checkmark.circle.fill" : @"circle"];
    if (!img) {
        img = [self textImage:done ? @"☑" : @"☐"];
    } else {
        img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    cell.imageView.image = img;
    cell.imageView.tintColor = done ? [UIColor systemGreenColor] : [UIColor systemGrayColor];
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
