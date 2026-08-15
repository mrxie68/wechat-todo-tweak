#import "CustomCalendarTodoViewController.h"
#import "CustomTodoTableViewCell.h"
#import "AITodoManager.h"
#import "AISettings.h"
#import "TodoEditorViewController.h"
#import "AIConfig.h"

extern void todoEnsureAccount(void); // 由 WeChatTodoTweak.m 提供

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
    _dotView.frame = CGRectMake((w - 4) / 2.0, 64, 4, 4);
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
        _weekLabel.textColor = [UIColor systemBackgroundColor];
        _dayLabel.textColor = [UIColor systemBackgroundColor];
        _dotView.hidden = YES; // 选中日不显示圆点，避免出现小白圈
    } else {
        self.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
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
@property (nonatomic, strong) UIButton *statsButton;
@property (nonatomic, strong) UIButton *addButton;
@property (nonatomic, strong) UIButton *prevMonthButton;
@property (nonatomic, strong) UIButton *nextMonthButton;
@property (nonatomic, strong) UILabel *monthLabel;
@property (nonatomic, strong) UICollectionView *calendarView;
@property (nonatomic, strong) UILabel *listHeaderLabel;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
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
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    todoEnsureAccount(); // 重进微信后立即拿到当前账号，保证待办目录正确
    // 恢复上次选中的日期，避免退出重进后默认回到“今天”而看不到之前那天的待办
    double saved = [[NSUserDefaults standardUserDefaults] doubleForKey:[self selectedDayKey]];
    self.selectedDay = saved > 0 ? [NSDate dateWithTimeIntervalSince1970:saved] : [NSDate date];
    self.currentMonth = self.selectedDay;
    self.expandedIds = [NSMutableSet set];

    [self buildTopBar];
    [self buildMonthRow];
    [self buildCalendar];
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

    self.closeButton = [self topBarButton:@"xmark"];
    [self.closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.closeButton];

    self.statsButton = [self topBarButton:@"chart.pie.fill"];
    [self.statsButton addTarget:self action:@selector(statsTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.statsButton];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"待办";
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textAlignment = NSTextAlignmentCenter;
    title.tag = 101;
    [self.topBar addSubview:title];

    self.addButton = [self topBarButton:@"plus.circle"];
    [self.addButton addTarget:self action:@selector(addTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.addButton];
}

- (UIButton *)topBarButton:(NSString *)symbol {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *img = [UIImage systemImageNamed:symbol];
    [b setImage:img forState:UIControlStateNormal];
    b.tintColor = [UIColor labelColor];
    return b;
}

#pragma mark - 月份选择 + 日历

- (void)buildMonthRow {
    self.prevMonthButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.prevMonthButton setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    [self.prevMonthButton addTarget:self action:@selector(prevMonth) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.prevMonthButton];

    self.monthLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.monthLabel.font = [UIFont boldSystemFontOfSize:16];
    self.monthLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.monthLabel];

    self.nextMonthButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.nextMonthButton setImage:[UIImage systemImageNamed:@"chevron.right"] forState:UIControlStateNormal];
    [self.nextMonthButton addTarget:self action:@selector(nextMonth) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.nextMonthButton];
}

- (void)buildCalendar {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.itemSize = CGSizeMake(52, 82);
    layout.minimumLineSpacing = 10;
    layout.minimumInteritemSpacing = 10;
    layout.sectionInset = UIEdgeInsetsMake(0, 16, 0, 16);
    self.calendarView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.calendarView.backgroundColor = [UIColor clearColor];
    self.calendarView.showsHorizontalScrollIndicator = NO;
    self.calendarView.dataSource = self;
    self.calendarView.delegate = self;
    [self.calendarView registerClass:[CalendarDayCell class] forCellWithReuseIdentifier:@"DayCell"];
    [self.view addSubview:self.calendarView];
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
    [self saveSelectedDay];
}

- (NSString *)selectedDayKey {
    NSString *acc = [AISettings currentAccount];
    if (acc.length == 0) return @"WeChatTodoLastSelectedDay";
    return [@"WeChatTodoLastSelectedDay_" stringByAppendingString:acc];
}

- (void)saveSelectedDay {
    NSDate *start = [[NSCalendar currentCalendar] startOfDayForDate:self.selectedDay];
    [[NSUserDefaults standardUserDefaults] setDouble:[start timeIntervalSince1970]
                                             forKey:[self selectedDayKey]];
    [[NSUserDefaults standardUserDefaults] synchronize];
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
    self.listHeaderLabel.font = [UIFont boldSystemFontOfSize:17];
    self.listHeaderLabel.textColor = [UIColor labelColor];
    [self.view addSubview:self.listHeaderLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyLabel.font = [UIFont systemFontOfSize:14];
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
}

- (void)reloadList {
    self.listTodos = [AITodoManager todosOnDay:self.selectedDay];
    [self.tableView reloadData];
    [self refreshDaysWithTodos];

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
    BOOL empty = (self.listTodos.count == 0);
    self.tableView.hidden = empty;
    self.emptyLabel.hidden = !empty;
    self.emptyLabel.text = @"这一天还没有待办\n点右上角 + 添加一条";
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
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)statsTapped {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *start = [cal startOfDayForDate:self.selectedDay];
    NSDate *end = [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:start options:0];
    NSUInteger dayUndone = 0, dayDone = 0;
    NSArray *all = [AITodoManager allTodos];
    NSUInteger globalUndone = 0;
    NSUInteger bookmarked = 0;
    for (MainTodoItem *m in all) {
        if (!m.done) globalUndone++;
        if (m.isBookmarked) bookmarked++;
        if ([m.createTime compare:start] != NSOrderedAscending &&
            [m.createTime compare:end] == NSOrderedAscending) {
            if (m.done) dayDone++;
            else dayUndone++;
        }
    }
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    fmt.dateFormat = @"M月d日";
    UIAlertController *al = [UIAlertController alertControllerWithTitle:@"统计"
                                                                message:[NSString stringWithFormat:
                                                                         @"%@（当前所选）\n当日：未完成 %lu · 已完成 %lu\n\n全部：%lu 条（未完成 %lu · 已书签 %lu）",
                                                                         [fmt stringFromDate:self.selectedDay],
                                                                         (unsigned long)dayUndone,
                                                                         (unsigned long)dayDone,
                                                                         (unsigned long)all.count,
                                                                         (unsigned long)globalUndone,
                                                                         (unsigned long)bookmarked]
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [al addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:al animated:YES completion:nil];
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
    self.listTodos = [AITodoManager todosOnDay:self.selectedDay];
    [self.tableView reloadData];
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
    [self presentMultilineInputWithTitle:@"编辑子任务"
                             initialText:sub.title
                              completion:^(NSString *text) {
        [AITodoManager renameSubTask:sub.identifier inTodo:todo.identifier title:text];
        [self reloadRowForTodo:todo];
    }];
}

// 打开 Markdown 编辑页（新建/编辑待办与子任务共用）
- (void)presentMultilineInputWithTitle:(NSString *)title
                           initialText:(NSString *)initial
                            completion:(void (^)(NSString *text))completion {
    TodoEditorViewController *vc = [[TodoEditorViewController alloc] initWithTitle:title
                                                                      initialText:initial
                                                                       completion:completion];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
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
    [self saveSelectedDay];
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
    cell.onToggleBookmark = ^{
        [AITodoManager toggleBookmarkForTodo:todo.identifier];
        [self reloadRowForTodo:todo];
    };
    cell.onAddSubTask = ^{
        [self addSubTaskForTodo:todo];
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

#pragma mark - 布局

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    UIEdgeInsets sa = self.view.safeAreaInsets;
    CGFloat w = b.size.width;

    self.topBar.frame = CGRectMake(0, 0, w, sa.top + 48);
    self.closeButton.frame = CGRectMake(8, sa.top, 44, 44);
    self.statsButton.frame = CGRectMake(52, sa.top, 44, 44);
    self.addButton.frame = CGRectMake(w - 52, sa.top, 44, 44);
    UILabel *title = [self.topBar viewWithTag:101];
    title.frame = CGRectMake(100, sa.top, w - 200, 44);

    CGFloat monthY = sa.top + 48 + 10;
    self.prevMonthButton.frame = CGRectMake(16, monthY, 44, 34);
    self.nextMonthButton.frame = CGRectMake(w - 60, monthY, 44, 34);
    self.monthLabel.frame = CGRectMake(64, monthY, w - 128, 34);

    CGFloat calY = monthY + 34 + 10;
    self.calendarView.frame = CGRectMake(0, calY, w, 84);
    if (!self.didInitialScroll) {
        self.didInitialScroll = YES;
        [self scrollToSelectedDayAnimated:NO]; // 首次布局后再定位到今天，保证可见
    }

    CGFloat headerY = calY + 84 + 12;
    self.listHeaderLabel.frame = CGRectMake(20, headerY, w - 40, 24);

    CGFloat tableY = headerY + 24 + 4;
    self.tableView.frame = CGRectMake(0, tableY, w, b.size.height - tableY - sa.bottom);
    self.emptyLabel.frame = CGRectMake(32, tableY + 80, w - 64, 80);
}

@end
