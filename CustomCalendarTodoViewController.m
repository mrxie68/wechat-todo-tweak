#import "CustomCalendarTodoViewController.h"
#import "CustomTodoTableViewCell.h"
#import "AITodoManager.h"
#import "AISettings.h"
#import "TodoEditorViewController.h"
#import "TodoListViewController.h"
#import "TodoStatsViewController.h"
#import "AIConfig.h"

extern void todoEnsureAccount(void); // 由 WeChatTodoTweak.m 提供
extern void todoCloseOverlay(void);  // 由 WeChatTodoTweak.m 提供
extern UIColor *todoWeChatBackgroundColor(void); // 微信页面背景

#pragma mark - 日历日期 Cell

@interface CalendarDayCell : UICollectionViewCell
@property (nonatomic, strong) UILabel *weekLabel;
@property (nonatomic, strong) UILabel *dayLabel;
@property (nonatomic, strong) UIView *dotView;
- (void)setDay:(NSDate *)day selected:(BOOL)selected isToday:(BOOL)isToday hasTodos:(BOOL)hasTodos;
@end

@implementation CalendarDayCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.cornerRadius = 14;
        self.clipsToBounds = YES;
        self.layer.borderWidth = 1.0; // 1px 边框
        _weekLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _weekLabel.font = [UIFont systemFontOfSize:11];
        _weekLabel.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_weekLabel];
        _dayLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _dayLabel.font = [UIFont boldSystemFontOfSize:17];
        _dayLabel.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_dayLabel];
        _dotView = [[UIView alloc] initWithFrame:CGRectZero];
        _dotView.layer.cornerRadius = 2;
        [self.contentView addSubview:_dotView];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    _weekLabel.frame = CGRectMake(0, 12, w, 14);
    _dayLabel.frame = CGRectMake(0, 32, w, 24);
    _dotView.frame = CGRectMake((w - 4) / 2.0, 60, 4, 4);
}

- (void)setDay:(NSDate *)day selected:(BOOL)selected isToday:(BOOL)isToday hasTodos:(BOOL)hasTodos {
    NSDateFormatter *wf = [[NSDateFormatter alloc] init];
    wf.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    wf.dateFormat = @"EEE";
    _weekLabel.text = [wf stringFromDate:day];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"d";
    _dayLabel.text = [df stringFromDate:day];
    if (selected) {
        self.backgroundColor = kAITodoAccentColor;
        self.layer.borderColor = kAITodoAccentDark.CGColor;
        _weekLabel.textColor = [UIColor systemBackgroundColor];
        _dayLabel.textColor = [UIColor systemBackgroundColor];
        _dotView.hidden = YES; // 选中日不显示圆点，避免出现小白圈
    } else {
        self.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        self.layer.borderColor = [UIColor separatorColor].CGColor;
        _weekLabel.textColor = [UIColor secondaryLabelColor];
        _dayLabel.textColor = isToday ? kAITodoAccentColor : [UIColor labelColor];
        if (isToday) {
            _dotView.backgroundColor = kAITodoAccentColor;
            _dotView.hidden = NO;
        } else if (hasTodos) {
            _dotView.backgroundColor = [UIColor colorWithRed:0.45 green:0.82 blue:0.55 alpha:1.0];
            _dotView.hidden = NO;
        } else {
            _dotView.hidden = YES;
        }
    }
}

@end

#pragma mark - 主页

@interface CustomCalendarTodoViewController () <UICollectionViewDataSource, UICollectionViewDelegate,
                                                UICollectionViewDelegateFlowLayout,
                                                UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSDate *selectedDay;
@property (nonatomic, strong) NSDate *currentMonth;
@property (nonatomic, strong) NSMutableArray<NSDate *> *days;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *prevMonthButton;
@property (nonatomic, strong) UIButton *nextMonthButton;
@property (nonatomic, strong) UILabel *monthLabel;
@property (nonatomic, strong) UIView *calendarCard;
@property (nonatomic, strong) UICollectionView *calendarView;
@property (nonatomic, strong) UIView *filterCard;
@property (nonatomic, strong) UIButton *allTodosRow;
@property (nonatomic, strong) UIButton *bookmarkRow;
@property (nonatomic, strong) UIButton *statsRow;
@property (nonatomic, strong) NSArray *filterDividers;
@property (nonatomic, strong) UILabel *allTodosValueLabel;
@property (nonatomic, strong) UILabel *bookmarkValueLabel;
@property (nonatomic, strong) UILabel *statsValueLabel;
@property (nonatomic, strong) UILabel *listHeaderLabel;
@property (nonatomic, strong) UIButton *todayButton;
@property (nonatomic, strong) UIButton *addFooterButton;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UILabel *emptyIconLabel;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIButton *emptyButton;
@property (nonatomic, strong) NSArray<MainTodoItem *> *listTodos;
@property (nonatomic, assign) BOOL didInitialScroll;
@property (nonatomic, strong) NSSet *daysWithTodos;
@property (nonatomic, strong) NSMutableSet *expandedIds; // 展开状态只存内存，互不影响
@end

@implementation CustomCalendarTodoViewController

+ (void)presentFrom:(UIViewController *)host {
    if (!host) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (host.presentedViewController) return;
        CustomCalendarTodoViewController *vc = [[CustomCalendarTodoViewController alloc] init];
        vc.modalPresentationStyle = UIModalPresentationFullScreen;
        [host presentViewController:vc animated:YES completion:nil];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // 用微信页面背景，和微信融为一体
    self.view.backgroundColor = todoWeChatBackgroundColor();
    todoEnsureAccount(); // 重进微信后立即拿到当前账号，保证待办目录正确
    // 每次进入都停留在当天
    self.selectedDay = [NSDate date];
    self.currentMonth = self.selectedDay;
    self.expandedIds = [NSMutableSet set];

    [self buildTopBar];
    [self buildCalendarCard];
    [self buildList];
    [self rebuildDays];
    [self refreshDaysWithTodos];
    [self reloadList];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] postNotificationName:kWeChatTodoPageAppearNotification object:nil];
    [self reloadList];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] postNotificationName:kWeChatTodoPageDisappearNotification object:nil];
}

#pragma mark - 顶部导航栏

- (void)buildTopBar {
    self.topBar = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.topBar];

    // 内嵌打开（底部菜单 tab）时顶部不显示关闭/添加按钮：
    // 再点一次待办 tab 或切走即关闭；添加走列表底部“再添加一条待办”。
    // 从设置页整页弹出时保留关闭按钮，避免没有返回路径。
    if (self.presentingViewController) {
        self.closeButton = [self topBarButton:@"xmark"];
        [self.closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.topBar addSubview:self.closeButton];
    }

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"待办";
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textAlignment = NSTextAlignmentCenter;
    title.tag = 101;
    [self.topBar addSubview:title];
}

- (UIButton *)topBarButton:(NSString *)symbol {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *img = [UIImage systemImageNamed:symbol];
    [b setImage:img forState:UIControlStateNormal];
    b.tintColor = [UIColor labelColor];
    return b;
}

#pragma mark - 日历卡片（月份切换 + 日期条 + 书签/统计，一个白色容器）

- (void)buildCalendarCard {
    self.calendarCard = [[UIView alloc] initWithFrame:CGRectZero];
    self.calendarCard.backgroundColor = [UIColor systemBackgroundColor]; // 白色卡片
    self.calendarCard.layer.cornerRadius = 16;
    self.calendarCard.layer.shadowColor = [UIColor blackColor].CGColor;
    self.calendarCard.layer.shadowOpacity = 0.05;
    self.calendarCard.layer.shadowOffset = CGSizeMake(0, 2);
    self.calendarCard.layer.shadowRadius = 8;
    [self.view addSubview:self.calendarCard];

    self.prevMonthButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.prevMonthButton setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    [self.prevMonthButton addTarget:self action:@selector(prevMonth) forControlEvents:UIControlEventTouchUpInside];
    [self.calendarCard addSubview:self.prevMonthButton];

    self.monthLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.monthLabel.font = [UIFont boldSystemFontOfSize:16];
    self.monthLabel.textAlignment = NSTextAlignmentCenter;
    [self.calendarCard addSubview:self.monthLabel];

    self.nextMonthButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.nextMonthButton setImage:[UIImage systemImageNamed:@"chevron.right"] forState:UIControlStateNormal];
    [self.nextMonthButton addTarget:self action:@selector(nextMonth) forControlEvents:UIControlEventTouchUpInside];
    [self.calendarCard addSubview:self.nextMonthButton];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.itemSize = CGSizeMake(52, 78);
    layout.minimumLineSpacing = 10;
    layout.minimumInteritemSpacing = 10;
    layout.sectionInset = UIEdgeInsetsMake(0, 16, 0, 16);
    self.calendarView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.calendarView.backgroundColor = [UIColor clearColor];
    self.calendarView.showsHorizontalScrollIndicator = NO;
    self.calendarView.dataSource = self;
    self.calendarView.delegate = self;
    [self.calendarView registerClass:[CalendarDayCell class] forCellWithReuseIdentifier:@"DayCell"];
    [self.calendarCard addSubview:self.calendarView];

    // 全部待办 / 全部书签 / 今日统计：日历卡片下方，设置条目样式
    [self buildFilterCard];
}

// 三个筛选入口：一行三块（全部待办 / 全部书签 / 今日统计）
- (void)buildFilterCard {
    self.filterCard = [[UIView alloc] initWithFrame:CGRectZero];
    self.filterCard.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.filterCard.layer.cornerRadius = 12;
    self.filterCard.layer.masksToBounds = YES;
    [self.view addSubview:self.filterCard];

    self.allTodosRow = [self makeFilterBlock:@"全部" action:@selector(openAllTodos)];
    self.bookmarkRow = [self makeFilterBlock:@"书签" action:@selector(openBookmarks)];
    self.statsRow = [self makeFilterBlock:@"统计" action:@selector(openStats)];

    self.allTodosValueLabel = [self makeFilterBlockValueFor:self.allTodosRow];
    self.bookmarkValueLabel = [self makeFilterBlockValueFor:self.bookmarkRow];
    self.statsValueLabel = [self makeFilterBlockValueFor:self.statsRow];

    // 块与块之间的细分隔线
    UIView *d1 = [[UIView alloc] initWithFrame:CGRectZero];
    d1.backgroundColor = [UIColor separatorColor];
    UIView *d2 = [[UIView alloc] initWithFrame:CGRectZero];
    d2.backgroundColor = [UIColor separatorColor];
    [self.filterCard addSubview:d1];
    [self.filterCard addSubview:d2];
    self.filterDividers = @[d1, d2];
}

- (UIButton *)makeFilterBlock:(NSString *)title action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    btn.backgroundColor = [UIColor clearColor];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.tag = 1;
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:13];
    titleLabel.textColor = [UIColor secondaryLabelColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [btn addSubview:titleLabel];

    [self.filterCard addSubview:btn];
    return btn;
}

- (UILabel *)makeFilterBlockValueFor:(UIButton *)block {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.tag = 2;
    label.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    label.textColor = [UIColor labelColor];
    label.textAlignment = NSTextAlignmentCenter;
    [block addSubview:label];
    return label;
}

- (void)rebuildDays {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *first = [self firstDayOfMonth:self.currentMonth];
    NSDate *start = [cal dateByAddingUnit:NSCalendarUnitDay value:-14 toDate:first options:0];
    NSInteger count = [self daysInMonth:self.currentMonth] + 28;
    NSMutableArray *arr = [NSMutableArray array];
    for (NSInteger i = 0; i < count; i++) {
        [arr addObject:[cal dateByAddingUnit:NSCalendarUnitDay value:i toDate:start options:0]];
    }
    self.days = arr;
    [self.calendarView reloadData];
    [self scrollToSelectedDayAnimated:NO];
    [self updateMonthLabel];
}

- (NSDate *)firstDayOfMonth:(NSDate *)date {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:date];
    c.day = 1;
    return [cal dateFromComponents:c];
}

- (NSInteger)daysInMonth:(NSDate *)date {
    NSRange r = [[NSCalendar currentCalendar]
                 rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:date];
    return r.length;
}

- (void)updateMonthLabel {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    fmt.dateFormat = @"M月/yyyy年";
    self.monthLabel.text = [fmt stringFromDate:self.currentMonth];
}

- (void)prevMonth {
    self.currentMonth = [[NSCalendar currentCalendar]
                         dateByAddingUnit:NSCalendarUnitMonth value:-1
                         toDate:self.currentMonth options:0];
    [self clampSelectedDayToMonth];
    [self rebuildDays];
    [self reloadList];
}

- (void)nextMonth {
    self.currentMonth = [[NSCalendar currentCalendar]
                         dateByAddingUnit:NSCalendarUnitMonth value:1
                         toDate:self.currentMonth options:0];
    [self clampSelectedDayToMonth];
    [self rebuildDays];
    [self reloadList];
}

- (void)clampSelectedDayToMonth {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSInteger dayNum = [cal component:NSCalendarUnitDay fromDate:self.selectedDay];
    dayNum = MIN(dayNum, [self daysInMonth:self.currentMonth]);
    NSDateComponents *c = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:self.currentMonth];
    c.day = dayNum;
    self.selectedDay = [cal dateFromComponents:c];
}

- (void)scrollToSelectedDayAnimated:(BOOL)animated {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *sel = [cal startOfDayForDate:self.selectedDay];
    for (NSUInteger i = 0; i < self.days.count; i++) {
        if ([[cal startOfDayForDate:self.days[i]] isEqualToDate:sel]) {
            [self.calendarView scrollToItemAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]
                                      atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                              animated:animated];
            return;
        }
    }
}

#pragma mark - 列表

- (void)buildList {
    self.listHeaderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.listHeaderLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.listHeaderLabel.textColor = [UIColor labelColor];
    [self.view addSubview:self.listHeaderLabel];

    self.todayButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.todayButton setTitle:@"回到今天" forState:UIControlStateNormal];
    self.todayButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.todayButton.tintColor = [UIColor colorWithRed:0.35 green:0.58 blue:0.95 alpha:1.0];
    [self.todayButton addTarget:self action:@selector(goToToday) forControlEvents:UIControlEventTouchUpInside];
    self.todayButton.hidden = YES;
    [self.view addSubview:self.todayButton];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    self.emptyView = [[UIView alloc] initWithFrame:CGRectZero];
    self.emptyView.hidden = YES;
    [self.view addSubview:self.emptyView];

    self.emptyIconLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyIconLabel.font = [UIFont systemFontOfSize:40];
    self.emptyIconLabel.textAlignment = NSTextAlignmentCenter;
    [self.emptyView addSubview:self.emptyIconLabel];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyLabel.font = [UIFont systemFontOfSize:14];
    [self.emptyView addSubview:self.emptyLabel];

    self.emptyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.emptyButton setTitle:@"添加第一条" forState:UIControlStateNormal];
    self.emptyButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [self.emptyButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.emptyButton.backgroundColor = kAITodoAccentColor;
    self.emptyButton.layer.cornerRadius = 20;
    [self.emptyButton addTarget:self action:@selector(addTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.emptyView addSubview:self.emptyButton];

    // 列表底部“再添加一条待办”
    self.addFooterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.addFooterButton setTitle:@"＋ 再添加一条待办" forState:UIControlStateNormal];
    [self.addFooterButton setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    self.addFooterButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [self.addFooterButton addTarget:self action:@selector(addTapped) forControlEvents:UIControlEventTouchUpInside];
    self.addFooterButton.frame = CGRectMake(0, 0, self.view.bounds.size.width, 56);
    self.addFooterButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.tableView.tableFooterView = self.addFooterButton;
}

- (void)reloadList {
    self.listTodos = [AITodoManager todosOnDay:self.selectedDay];
    NSCalendar *cal = [NSCalendar currentCalendar];
    BOOL isToday = [[cal startOfDayForDate:self.selectedDay] isEqualToDate:
                    [cal startOfDayForDate:[NSDate date]]];
    if (isToday) {
        self.listHeaderLabel.text = [NSString stringWithFormat:@"今日待办（%lu）",
                                     (unsigned long)self.listTodos.count];
    } else {
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        fmt.dateFormat = @"M月d日";
        self.listHeaderLabel.text = [NSString stringWithFormat:@"%@ 待办（%lu）",
                                     [fmt stringFromDate:self.selectedDay],
                                     (unsigned long)self.listTodos.count];
    }
    [self.tableView reloadData];
    [self refreshDaysWithTodos];

    // 三个入口的数字实时刷新
    NSUInteger total = [AITodoManager allTodos].count;
    NSUInteger bookmarked = 0;
    for (MainTodoItem *m in [AITodoManager allTodos]) {
        if (m.isBookmarked) bookmarked++;
    }
    self.allTodosValueLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)total];
    self.bookmarkValueLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)bookmarked];
    // 今日统计：今天未完成数
    NSUInteger todayUndone = 0;
    NSDate *todayStart = [cal startOfDayForDate:[NSDate date]];
    NSDate *tomorrow = [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:todayStart options:0];
    for (MainTodoItem *m in [AITodoManager allTodos]) {
        if (!m.done &&
            [m.createTime compare:todayStart] != NSOrderedAscending &&
            [m.createTime compare:tomorrow] == NSOrderedAscending) {
            todayUndone++;
        }
    }
    self.statsValueLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)todayUndone];

    BOOL empty = (self.listTodos.count == 0);
    self.tableView.hidden = empty;
    self.emptyView.hidden = !empty;
    if (empty) {
        self.emptyIconLabel.text = @"📋";
        self.emptyLabel.text = @"这一天还没有待办";
        self.emptyButton.hidden = NO;
    }
    // 非今天且不在书签模式时，显示“回到今天”
    self.todayButton.hidden = isToday;
}

- (void)goToToday {
    self.selectedDay = [NSDate date];
    self.currentMonth = self.selectedDay;
    [self rebuildDays];
    [self reloadList];
}

- (void)refreshDaysWithTodos {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSMutableSet *set = [NSMutableSet set];
    for (MainTodoItem *m in [AITodoManager allTodos]) {
        NSDate *start = [cal startOfDayForDate:m.createTime];
        [set addObject:@([start timeIntervalSince1970])];
    }
    self.daysWithTodos = set;
    [self.calendarView reloadData];
}

#pragma mark - 交互

- (void)closeTapped {
    if (!self.navigationController && !self.presentingViewController) {
        todoCloseOverlay(); // 内嵌方式打开时直接关闭
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 二级页面（全部待办 / 全部书签 / 今日统计）

- (void)openAllTodos {
    [self presentListPage:[TodoListViewController allPage]];
}

- (void)openBookmarks {
    [self presentListPage:[TodoListViewController bookmarkPage]];
}

- (void)openStats {
    [self presentListPage:[[TodoStatsViewController alloc] init]];
}

- (void)presentListPage:(UIViewController *)vc {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    // 与编辑页一致：导航栏不透明白，避免顶部透明
    nav.navigationBar.translucent = NO;
    nav.navigationBar.barTintColor = [UIColor systemBackgroundColor];
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *app = [[UINavigationBarAppearance alloc] init];
        [app configureWithOpaqueBackground];
        app.backgroundColor = [UIColor systemBackgroundColor];
        app.shadowColor = [UIColor clearColor];
        nav.navigationBar.standardAppearance = app;
        nav.navigationBar.scrollEdgeAppearance = app;
    }
    nav.view.backgroundColor = [UIColor systemBackgroundColor];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)addTapped {
    [self presentMultilineInputWithTitle:@"新建待办"
                             initialText:@""
                              completion:^(NSString *text) {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (text.length == 0) {
            [self showToast:@"内容不能为空"];
            return;
        }
        MainTodoItem *item = [AITodoManager addTodo:trimmed atDate:[self dateOnSelectedDayAtCurrentTime]];
        if (item) {
            [self reloadList];
            [self scrollToTodoId:item.identifier];
            [self showToast:@"✅ 已添加"];
            if (@available(iOS 10.0, *)) {
                UIImpactFeedbackGenerator *g =
                    [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
                [g impactOccurred];
            }
        } else {
            [self showToast:@"⚠️ 添加失败，请重试"];
        }
    }];
}

- (void)scrollToTodoId:(NSInteger)todoId {
    for (NSUInteger i = 0; i < self.listTodos.count; i++) {
        if (self.listTodos[i].identifier == todoId) {
            [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]
                                  atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
            return;
        }
    }
}

- (void)showToast:(NSString *)message {
    CGFloat w = self.view.bounds.size.width;
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake((w - 180) / 2.0,
                                                               self.view.safeAreaInsets.top + 64,
                                                               180, 36)];
    toast.text = message;
    toast.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.88];
    toast.layer.cornerRadius = 18;
    toast.clipsToBounds = YES;
    toast.textAlignment = NSTextAlignmentCenter;
    toast.alpha = 0;
    [self.view addSubview:toast];
    [UIView animateWithDuration:0.25 animations:^{
        toast.alpha = 1;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.4 delay:1.2 options:0 animations:^{
            toast.alpha = 0;
        } completion:^(BOOL done) {
            [toast removeFromSuperview];
        }];
    }];
}

- (NSDate *)dateOnSelectedDayAtCurrentTime {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *d = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay)
                                 fromDate:self.selectedDay];
    NSDateComponents *t = [cal components:(NSCalendarUnitHour | NSCalendarUnitMinute)
                                 fromDate:[NSDate date]];
    d.hour = t.hour;
    d.minute = t.minute;
    d.second = 0;
    return [cal dateFromComponents:d];
}

// 刷新列表：操作后从磁盘重新读取最新数据，避免用旧对象刷新导致改动不显示
- (void)reloadRowForTodo:(MainTodoItem *)todo {
    (void)todo;
    [self reloadList];
}

- (void)editTitleForTodo:(MainTodoItem *)todo {
    [self presentMultilineInputWithTitle:@"编辑待办"
                             initialText:todo.title
                              completion:^(NSString *text) {
        [AITodoManager updateTodo:todo.identifier
                            title:text
                             note:todo.note
                              due:todo.dueDate
                       bookmarked:todo.isBookmarked];
        [self reloadList];
    }];
}

- (void)addSubTaskForTodo:(MainTodoItem *)todo {
    [self presentMultilineInputWithTitle:@"添加子任务"
                             initialText:@""
                              completion:^(NSString *text) {
        [AITodoManager addSubTask:text toTodo:todo.identifier];
        // 加完自动展开（内存态），让子任务立刻可见
        [self.expandedIds addObject:@(todo.identifier)];
        [self reloadList];
    }];
}

- (void)editSubTask:(SubTaskItem *)sub inTodo:(MainTodoItem *)todo {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"编辑"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self presentMultilineInputWithTitle:@"编辑子任务"
                                 initialText:sub.title
                                  completion:^(NSString *text) {
            [AITodoManager renameSubTask:sub.identifier inTodo:todo.identifier title:text];
            [self reloadRowForTodo:todo];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"删除"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [AITodoManager removeSubTask:sub.identifier inTodo:todo.identifier];
        [self reloadList];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

// 打开 Markdown 编辑页（新建/编辑待办与子任务共用）
- (void)presentMultilineInputWithTitle:(NSString *)title
                           initialText:(NSString *)initial
                            completion:(void (^)(NSString *text))completion {
    TodoEditorViewController *vc = [[TodoEditorViewController alloc] initWithTitle:title
                                                                      initialText:initial
                                                                       completion:completion];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    // 导航栏强制不透明白，避免顶部透明
    nav.navigationBar.translucent = NO;
    nav.navigationBar.barTintColor = [UIColor systemBackgroundColor];
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *app = [[UINavigationBarAppearance alloc] init];
        [app configureWithOpaqueBackground];
        app.backgroundColor = [UIColor systemBackgroundColor];
        app.shadowColor = [UIColor clearColor];
        nav.navigationBar.standardAppearance = app;
        nav.navigationBar.scrollEdgeAppearance = app;
    }
    nav.view.backgroundColor = [UIColor systemBackgroundColor];
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - 日历数据源/代理

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.days.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    CalendarDayCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"DayCell"
                                                                      forIndexPath:indexPath];
    NSDate *day = self.days[indexPath.row];
    NSCalendar *cal = [NSCalendar currentCalendar];
    BOOL selected = [[cal startOfDayForDate:day] isEqualToDate:
                     [cal startOfDayForDate:self.selectedDay]];
    BOOL isToday = [[cal startOfDayForDate:day] isEqualToDate:
                    [cal startOfDayForDate:[NSDate date]]];
    BOOL hasTodos = [self.daysWithTodos containsObject:
                     @([[cal startOfDayForDate:day] timeIntervalSince1970])];
    [cell setDay:day selected:selected isToday:isToday hasTodos:hasTodos];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    self.selectedDay = self.days[indexPath.row];
    self.currentMonth = self.selectedDay;
    [self.calendarView reloadData];
    [self updateMonthLabel];
    [self reloadList];
}

#pragma mark - 列表数据源/代理

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.listTodos.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CustomTodoTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TodoCardCell"];
    if (!cell) {
        cell = [[CustomTodoTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                              reuseIdentifier:@"TodoCardCell"];
    }
    MainTodoItem *todo = self.listTodos[indexPath.row];
    todo.isSelected = [self.expandedIds containsObject:@(todo.identifier)];
    [cell configureWithTodo:todo];
    cell.onToggleSelect = ^{
        if ([self.expandedIds containsObject:@(todo.identifier)]) {
            [self.expandedIds removeObject:@(todo.identifier)];
        } else {
            [self.expandedIds addObject:@(todo.identifier)];
        }
        [self reloadRowForTodo:todo];
    };
    cell.onAddSubTask = ^{
        [self addSubTaskForTodo:todo];
    };
    cell.onToggleDone = ^{
        [AITodoManager markTodo:todo.identifier done:!todo.done];
        [self reloadRowForTodo:todo];
    };
    cell.onToggleSubTask = ^(SubTaskItem *sub) {
        [AITodoManager toggleSubTask:sub.identifier inTodo:todo.identifier];
        [self reloadRowForTodo:todo];
    };
    cell.onEditSubTask = ^(SubTaskItem *sub) {
        [self editSubTask:sub inTodo:todo];
    };
    cell.onLongPress = ^{
        [self editTitleForTodo:todo];
    };
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    MainTodoItem *todo = self.listTodos[indexPath.row];
    todo.isSelected = [self.expandedIds containsObject:@(todo.identifier)];
    return [CustomTodoTableViewCell heightForTodo:todo width:tableView.bounds.size.width];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    MainTodoItem *todo = self.listTodos[indexPath.row];
    UIContextualAction *del = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:@"删除"
                          handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
        [AITodoManager deleteTodo:todo.identifier];
        [self reloadList];
        completion(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

// 右滑 = 收藏/取消收藏
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    MainTodoItem *todo = self.listTodos[indexPath.row];
    UIContextualAction *doneAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:todo.done ? @"取消完成" : @"完成"
                          handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
        [AITodoManager markTodo:todo.identifier done:!todo.done];
        [self reloadList];
        completion(YES);
    }];
    doneAction.backgroundColor = [UIColor systemGreenColor];
    UIContextualAction *bookmark = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:todo.isBookmarked ? @"取消书签" : @"书签"
                          handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
        [AITodoManager toggleBookmarkForTodo:todo.identifier];
        [self reloadList];
        completion(YES);
    }];
    bookmark.backgroundColor = [UIColor colorWithRed:0.88 green:0.65 blue:0.18 alpha:1.0]; // 金色
    return [UISwipeActionsConfiguration configurationWithActions:@[doneAction, bookmark]];
}

#pragma mark - 布局

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    UIEdgeInsets sa = self.view.safeAreaInsets;
    // 内嵌打开时子视图安全区顶部可能为 0，用窗口安全区兜底，避免顶部上天
    if (sa.top <= 0) {
        sa.top = [UIApplication sharedApplication].keyWindow.safeAreaInsets.top;
    }
    CGFloat w = b.size.width;

    // 顶栏：标题居中；整页弹出时才显示关闭按钮
    self.topBar.frame = CGRectMake(0, 0, w, sa.top + 48);
    if (self.closeButton) self.closeButton.frame = CGRectMake(8, sa.top, 44, 44);
    UILabel *title = [self.topBar viewWithTag:101];
    title.frame = CGRectMake(16, sa.top, w - 32, 44);

    // 白色日历卡片：月份行 + 日期条 + 底部行（书签/统计）
    CGFloat cardX = 16, cardW = w - 32; // 与页面其它元素同边距
    CGFloat cardY = sa.top + 48 + 10;
    CGFloat cardH = 12 + 32 + 8 + 78 + 12; // 142
    self.calendarCard.frame = CGRectMake(cardX, cardY, cardW, cardH);
    // 月份行
    self.prevMonthButton.frame = CGRectMake(28, 12, 32, 32);
    self.nextMonthButton.frame = CGRectMake(cardW - 60, 12, 32, 32);
    self.monthLabel.frame = CGRectMake(64, 12, cardW - 128, 32);
    self.calendarView.frame = CGRectMake(0, 52, cardW, 78);
    if (!self.didInitialScroll) {
        self.didInitialScroll = YES;
        [self scrollToSelectedDayAnimated:NO]; // 首次布局后再定位到今天，保证可见
    }
    // 全部待办 / 全部书签 / 今日统计：一行三块
    CGFloat rowY = cardY + cardH + 10;
    CGFloat filterH = 84;
    self.filterCard.frame = CGRectMake(cardX, rowY, cardW, filterH);
    CGFloat blockW = cardW / 3.0;
    self.allTodosRow.frame = CGRectMake(0, 0, blockW, filterH);
    self.bookmarkRow.frame = CGRectMake(blockW, 0, blockW, filterH);
    self.statsRow.frame = CGRectMake(blockW * 2, 0, blockW, filterH);
    for (UIButton *b in @[self.allTodosRow, self.bookmarkRow, self.statsRow]) {
        [[b viewWithTag:1] setFrame:CGRectMake(0, 14, blockW, 18)];
        [[b viewWithTag:2] setFrame:CGRectMake(0, 34, blockW, 28)];
    }
    if (self.filterDividers.count >= 2) {
        [self.filterDividers[0] setFrame:CGRectMake(blockW, 18, 0.5, filterH - 36)];
        [self.filterDividers[1] setFrame:CGRectMake(blockW * 2, 18, 0.5, filterH - 36)];
    }

    CGFloat headerY = rowY + filterH + 12;
    self.listHeaderLabel.frame = CGRectMake(16, headerY, w - 32, 24);
    self.listHeaderLabel.textAlignment = NSTextAlignmentCenter;
    self.todayButton.frame = CGRectMake(w - 110, headerY, 90, 24);

    CGFloat tableY = headerY + 24 + 4;
    self.tableView.frame = CGRectMake(0, tableY, w, b.size.height - tableY - sa.bottom);
    CGFloat evW = w - 64;
    self.emptyView.frame = CGRectMake(32, tableY + 60, evW, 150);
    self.emptyIconLabel.frame = CGRectMake(0, 0, evW, 48);
    self.emptyLabel.frame = CGRectMake(0, 52, evW, 44);
    self.emptyButton.frame = CGRectMake((evW - 140) / 2.0, 106, 140, 40);
}

@end
