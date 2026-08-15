#import "TodoPageViewController.h"
#import "AITodoManager.h"
#import "AISettings.h"
#import "TodoSettingsViewController.h"
#import "TodoDetailViewController.h"
#import "TodoTableViewCell.h"
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
@property (nonatomic, strong) UIView *segmentBar;
@property (nonatomic, strong) NSArray *segmentButtons;
@property (nonatomic, assign) NSInteger segmentIndex;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *addButton;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIView *statsCard;
@property (nonatomic, strong) CAGradientLayer *heroGradient;
@property (nonatomic, strong) UILabel *heroDateLabel;
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
        // 兜底白底：即使微信/其它插件把导航栏弄透明，露出来的也是白色而不是黑色
        nav.view.backgroundColor = [UIColor whiteColor];
        nav.navigationBar.translucent = NO;
        nav.navigationBar.barTintColor = [UIColor whiteColor];
        nav.navigationBar.prefersLargeTitles = YES; // 大标题，更像原生 App
        if (@available(iOS 13.0, *)) {
            // 强制浅色外观：避免微信深色模式下顶部变黑，页面更清爽
            nav.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
            vc.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
            UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
            [appearance configureWithOpaqueBackground];
            appearance.backgroundColor = [UIColor whiteColor];
            appearance.shadowColor = [UIColor clearColor];
            appearance.largeTitleTextAttributes = @{
                NSFontAttributeName: [UIFont boldSystemFontOfSize:30],
                NSForegroundColorAttributeName: [UIColor blackColor],
            };
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
    // 显式浅灰背景，不随深色模式变黑（参考 ThemeBox 的兜底背景思路）
    self.view.backgroundColor = [UIColor colorWithRed:0.945 green:0.945 blue:0.957 alpha:1.0];
    // 内容从导航栏下方开始，避免和标题栏重叠
    self.edgesForExtendedLayout = UIRectEdgeNone;

    // 点击空白处收起键盘
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    tap.delegate = self;
    [self.view addGestureRecognizer:tap];

    // 左右滑动切换分段：待办 / 已完成 / 全部
    UISwipeGestureRecognizer *swipeLeft =
        [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft)];
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    swipeLeft.delegate = self;
    [self.view addGestureRecognizer:swipeLeft];
    UISwipeGestureRecognizer *swipeRight =
        [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    swipeRight.delegate = self;
    [self.view addGestureRecognizer:swipeRight];

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

    // 绿色渐变头部卡片：日期 + 未完成/已完成
    self.statsCard = [[UIView alloc] initWithFrame:CGRectZero];
    self.statsCard.backgroundColor = [UIColor clearColor];
    self.statsCard.layer.cornerRadius = 16;
    self.statsCard.clipsToBounds = YES;
    [self.view addSubview:self.statsCard];

    self.heroGradient = [CAGradientLayer layer];
    self.heroGradient.colors = @[
        (id)[UIColor colorWithRed:0.23 green:0.78 blue:0.47 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.03 green:0.70 blue:0.38 alpha:1.0].CGColor,
    ];
    self.heroGradient.startPoint = CGPointMake(0, 0.5);
    self.heroGradient.endPoint = CGPointMake(1, 0.5);
    [self.statsCard.layer addSublayer:self.heroGradient];

    self.heroDateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    NSDateFormatter *dateFmt = [[NSDateFormatter alloc] init];
    dateFmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    dateFmt.dateFormat = @"M月d日 EEEE";
    self.heroDateLabel.text = [dateFmt stringFromDate:[NSDate date]];
    self.heroDateLabel.font = [UIFont systemFontOfSize:12];
    self.heroDateLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    [self.statsCard addSubview:self.heroDateLabel];

    self.todoCountLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.todoCountLabel.font = [UIFont boldSystemFontOfSize:34];
    self.todoCountLabel.textColor = [UIColor whiteColor];
    self.todoTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.todoTitleLabel.text = @"项未完成";
    self.todoTitleLabel.font = [UIFont systemFontOfSize:15];
    self.todoTitleLabel.textColor = [UIColor whiteColor];
    [self.statsCard addSubview:self.todoCountLabel];
    [self.statsCard addSubview:self.todoTitleLabel];

    self.doneCountLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.doneCountLabel.font = [UIFont systemFontOfSize:14];
    self.doneCountLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    self.doneCountLabel.textAlignment = NSTextAlignmentRight;
    self.doneTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    [self.statsCard addSubview:self.doneCountLabel];
    [self.statsCard addSubview:self.doneTitleLabel];

    // 胶囊式分段：待办 / 已完成 / 全部
    self.segmentBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.segmentBar.backgroundColor = [UIColor whiteColor];
    self.segmentBar.layer.cornerRadius = 18;
    self.segmentBar.layer.shadowColor = [UIColor blackColor].CGColor;
    self.segmentBar.layer.shadowOpacity = 0.04;
    self.segmentBar.layer.shadowOffset = CGSizeMake(0, 2);
    self.segmentBar.layer.shadowRadius = 6;
    [self.view addSubview:self.segmentBar];

    NSMutableArray *btns = [NSMutableArray array];
    NSArray *titles = @[@"待办", @"已完成", @"全部"];
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.tag = i;
        [b setTitle:titles[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [b addTarget:self action:@selector(segmentTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.segmentBar addSubview:b];
        [btns addObject:b];
    }
    self.segmentButtons = btns;
    self.segmentIndex = 0;
    [self updateSegmentStyles];

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

    // 底部浮动输入栏
    self.inputBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.inputBar.backgroundColor = [UIColor whiteColor];
    self.inputBar.layer.cornerRadius = 18;
    self.inputBar.layer.shadowColor = [UIColor blackColor].CGColor;
    self.inputBar.layer.shadowOpacity = 0.08;
    self.inputBar.layer.shadowOffset = CGSizeMake(0, 2);
    self.inputBar.layer.shadowRadius = 8;
    [self.view addSubview:self.inputBar];

    self.inputField = [[UITextField alloc] initWithFrame:CGRectZero];
    self.inputField.placeholder = @"记一条待办…";
    self.inputField.font = [UIFont systemFontOfSize:15];
    self.inputField.backgroundColor = [UIColor colorWithRed:0.910 green:0.910 blue:0.925 alpha:1.0];
    self.inputField.layer.cornerRadius = 18;
    self.inputField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 36)];
    self.inputField.leftViewMode = UITextFieldViewModeAlways;
    self.inputField.returnKeyType = UIReturnKeyDone;
    self.inputField.delegate = self;
    self.inputField.autocorrectionType = UITextAutocorrectionTypeNo;
    [self.inputBar addSubview:self.inputField];

    self.addButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *plus = [UIImage systemImageNamed:@"plus"];
    [self.addButton setImage:plus forState:UIControlStateNormal];
    self.addButton.tintColor = [UIColor whiteColor];
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
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] postNotificationName:kWeChatTodoPageAppearNotification object:nil];
    [self reloadItems];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] postNotificationName:kWeChatTodoPageDisappearNotification object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    UIEdgeInsets sa = self.view.safeAreaInsets;

    CGFloat cardW = b.size.width - 32;
    CGFloat cardH = 96;
    CGFloat cardTop = sa.top + 12;
    self.statsCard.frame = CGRectMake(16, cardTop, cardW, cardH);
    self.heroGradient.frame = self.statsCard.bounds;
    self.heroDateLabel.frame = CGRectMake(18, 12, cardW - 36, 18);
    self.todoCountLabel.frame = CGRectMake(18, 38, 76, 44);
    self.todoTitleLabel.frame = CGRectMake(96, 52, 90, 24);
    self.doneCountLabel.frame = CGRectMake(cardW - 150, 60, 132, 20);
    self.doneTitleLabel.frame = CGRectZero;

    CGFloat segTop = cardTop + cardH + 12;
    self.segmentBar.frame = CGRectMake(16, segTop, cardW, 36);
    [self updateSegmentStyles];

    CGFloat tableTop = segTop + 36 + 12;

    CGFloat barContentH = 54;
    CGFloat barBottom = b.size.height - self.keyboardInset - (self.keyboardInset > 0 ? 10 : sa.bottom + 8);
    self.inputBar.frame = CGRectMake(16, barBottom - barContentH, b.size.width - 32, barContentH);

    CGFloat fieldH = 36;
    CGFloat fieldY = (barContentH - fieldH) / 2.0;
    self.inputField.frame = CGRectMake(10, fieldY, self.inputBar.bounds.size.width - 20 - 44 - 8, fieldH);
    self.addButton.frame = CGRectMake(self.inputBar.bounds.size.width - 10 - 36, fieldY, 36, 36);
    self.addButton.layer.cornerRadius = 18;

    self.tableView.frame = CGRectMake(0, tableTop, b.size.width, barBottom - tableTop);
    self.emptyLabel.frame = CGRectMake(32, tableTop + 60, b.size.width - 64, 90);
}

#pragma mark - 数据

- (void)reloadItems {
    NSArray *all = [AITodoManager allTodos];
    NSMutableArray *filtered = [NSMutableArray array];
    NSInteger seg = self.segmentIndex;
    for (NSDictionary *t in all) {
        BOOL done = [t[@"done"] boolValue];
        if (seg == 0 && done) continue;
        if (seg == 1 && !done) continue;
        [filtered addObject:t];
    }
    // 未完成在前；未完成里：重要优先 → 截止近的在前（无截止最后）→ 编号倒序；已完成按完成时间倒序
    [filtered sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        BOOL da = [a[@"done"] boolValue];
        BOOL db = [b[@"done"] boolValue];
        if (da != db) return da ? NSOrderedDescending : NSOrderedAscending;
        if (!da) {
            BOOL ia = [a[@"important"] boolValue];
            BOOL ib = [b[@"important"] boolValue];
            if (ia != ib) return ia ? NSOrderedAscending : NSOrderedDescending;
            double dueA = [a[@"due"] doubleValue];
            double dueB = [b[@"due"] doubleValue];
            if (dueA > 0 && dueB > 0) {
                if (dueA != dueB) return dueA < dueB ? NSOrderedAscending : NSOrderedDescending;
            } else if (dueA > 0) {
                return NSOrderedAscending;
            } else if (dueB > 0) {
                return NSOrderedDescending;
            }
            return [b[@"id"] compare:a[@"id"]];
        }
        double daA = [a[@"doneAt"] doubleValue];
        double daB = [b[@"doneAt"] doubleValue];
        if (daA != daB) return daA > daB ? NSOrderedAscending : NSOrderedDescending;
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
    self.doneCountLabel.text = [NSString stringWithFormat:@"已完成 %lu 项", (unsigned long)completed];
    // 渐变头部卡里统一白色
    self.todoCountLabel.textColor = [UIColor whiteColor];
    self.doneCountLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.9];

    BOOL empty = (filtered.count == 0);
    self.tableView.hidden = empty;
    self.emptyLabel.hidden = !empty;
    if (seg == 1) {
        [self setEmptyMessage:@"还没有已完成的待办\n完成一条后会自动出现在这里" icon:@"🎉"];
    } else if (seg == 2) {
        [self setEmptyMessage:@"还没有任何待办\n在下方输入第一条吧" icon:@"📋"];
    } else {
        [self setEmptyMessage:@"太棒了，全部完成！\n在下方输入新的待办吧" icon:@"✅"];
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

- (void)setEmptyMessage:(NSString *)message icon:(NSString *)icon {
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] init];
    if (icon.length > 0) {
        [as appendAttributedString:
            [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", icon]
                                            attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:44]}]];
    }
    [as appendAttributedString:
        [[NSAttributedString alloc] initWithString:message
                                        attributes:@{
                                            NSFontAttributeName: [UIFont systemFontOfSize:14],
                                            NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
                                        }]];
    self.emptyLabel.attributedText = as;
}

- (void)segmentTapped:(UIButton *)sender {
    self.segmentIndex = sender.tag;
    [self updateSegmentStyles];
    [self reloadItems];
}

- (void)updateSegmentStyles {
    CGFloat w = self.segmentBar.bounds.size.width;
    CGFloat h = self.segmentBar.bounds.size.height;
    if (w <= 0 || h <= 0) return;
    for (UIButton *b in self.segmentButtons) {
        CGFloat x = b.tag * (w / 3.0);
        b.frame = CGRectMake(x + 3, 3, w / 3.0 - 6, h - 6);
        BOOL sel = (b.tag == self.segmentIndex);
        b.backgroundColor = sel ? [UIColor systemGreenColor] : [UIColor clearColor];
        [b setTitleColor:sel ? [UIColor whiteColor]
                            : [UIColor colorWithRed:0.35 green:0.35 blue:0.38 alpha:1.0]
                forState:UIControlStateNormal];
        b.layer.cornerRadius = (h - 6) / 2.0;
        b.clipsToBounds = YES;
    }
}

- (void)swipeLeft {
    if (self.segmentIndex < 2) {
        self.segmentIndex++;
        [self updateSegmentStyles];
        [self reloadItems];
    }
}

- (void)swipeRight {
    if (self.segmentIndex > 0) {
        self.segmentIndex--;
        [self updateSegmentStyles];
        [self reloadItems];
    }
}

#pragma mark - 表格

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredTodos.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TodoTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TodoCell"];
    if (!cell) {
        cell = [[TodoTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                        reuseIdentifier:@"TodoCell"];
    }
    NSDictionary *t = self.filteredTodos[indexPath.row];
    BOOL done = [t[@"done"] boolValue];
    NSString *content = t[@"content"] ?: @"";

    NSMutableString *meta = [NSMutableString string];
    if ([t[@"important"] boolValue]) [meta appendString:@"⭐ "];
    double due = [t[@"due"] doubleValue];
    BOOL overdue = NO;
    if (due > 0) {
        overdue = !done && due < [[NSDate date] timeIntervalSince1970];
        [meta appendFormat:@"⏰ %@", todoDateString(due)];
        if (overdue) [meta appendString:@"（已逾期）"];
    } else if (done) {
        double doneAt = [t[@"doneAt"] doubleValue];
        if (doneAt > 0) [meta appendFormat:@"✅ 完成于 %@", todoDateString(doneAt)];
    } else {
        [meta appendFormat:@"创建于 %@", todoDateString([t[@"created"] doubleValue])];
    }
    [cell setDone:done important:[t[@"important"] boolValue] overdue:overdue
           content:content meta:meta];
    NSInteger todoId = [t[@"id"] integerValue];
    cell.onToggle = ^{
        [AITodoManager markTodo:todoId done:!done];
        [self reloadItems];
    };
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *t = self.filteredTodos[indexPath.row];
    NSString *content = t[@"content"] ?: @"";
    CGFloat cw = tableView.bounds.size.width - 56 - 14;
    NSInteger lines = MAX(1, (NSInteger)ceil(content.length / (cw / 17.0)));
    if (lines > 2) lines = 2;
    return MAX(64, 18 + lines * 22 + 24);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *t = self.filteredTodos[indexPath.row];
    TodoDetailViewController *vc = [[TodoDetailViewController alloc] initWithTodo:t];
    [self.navigationController pushViewController:vc animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *t = self.filteredTodos[indexPath.row];
    NSInteger todoId = [t[@"id"] integerValue];
    BOOL done = [t[@"done"] boolValue];

    UIContextualAction *toggleAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:done ? @"取消完成" : @"完成"
                          handler:^(UIContextualAction *action, UIView *sourceView, void (^completion)(BOOL)) {
        [AITodoManager markTodo:todoId done:!done];
        [self reloadItems];
        completion(YES);
    }];
    toggleAction.backgroundColor = [UIColor systemGreenColor];

    UIContextualAction *deleteAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:@"删除"
                          handler:^(UIContextualAction *action, UIView *sourceView, void (^completion)(BOOL)) {
        [AITodoManager deleteTodo:todoId];
        [self reloadItems];
        completion(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, toggleAction]];
}

#pragma mark - 操作

- (void)addTapped {
    NSString *text = [self.inputField.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) return;
    self.segmentIndex = 0;
    [self updateSegmentStyles];
    [AITodoManager addTodo:text];
    self.inputField.text = @"";
    [self reloadItems];
    if (self.filteredTodos.count > 0) {
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]
                              atScrollPosition:UITableViewScrollPositionTop animated:YES];
    }
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

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDarkContent; // 白底上用深色状态栏文字
}

#pragma mark - 键盘

- (void)keyboardWillChange:(NSNotification *)note {
    CGRect kbEnd = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat inset = 0;
    if (!CGRectIsNull(kbEnd)) {
        CGRect kbInView = [self.view convertRect:kbEnd fromView:nil];
        CGRect inter = CGRectIntersection(self.view.bounds, kbInView);
        inset = MAX(0, inter.size.height);
        // 保险：合法键盘不会盖住屏幕 75% 以上，异常全屏 frame 直接忽略，防止输入栏飞顶
        if (inset > self.view.bounds.size.height * 0.75) inset = 0;
    }
    self.keyboardInset = inset;
    // 必须先 setNeedsLayout 再 layoutIfNeeded，否则布局不会重跑，输入栏会被键盘挡住
    [self.view setNeedsLayout];
    [UIView animateWithDuration:0.25 animations:^{
        [self.view layoutIfNeeded];
    }];
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    // 兜底：通知已经算好高度的话，确保布局刷新（不扫窗口，键盘窗口 frame 是整个屏幕，扫了会算错）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.keyboardInset > 0) {
            [self.view setNeedsLayout];
            [UIView animateWithDuration:0.2 animations:^{
                [self.view layoutIfNeeded];
            }];
        }
    });
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    if ([gestureRecognizer isKindOfClass:[UISwipeGestureRecognizer class]]) {
        // 左右滑切换分段：不在列表行上触发，避免和“左滑删除”冲突
        if ([touch.view isDescendantOfView:self.tableView]) return NO;
        return YES;
    }
    // 输入框/按钮上的点击不拦截，其余空白处点击收起键盘
    if ([touch.view isKindOfClass:[UIControl class]] ||
        [touch.view isKindOfClass:[UITextField class]] ||
        [touch.view isKindOfClass:[UITextView class]]) {
        return NO;
    }
    return YES;
}

@end
