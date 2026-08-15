#import "CustomCalendarTodoViewController.h"
#import "CustomTodoTableViewCell.h"
#import "AITodoManager.h"
#import "AIConfig.h"

#pragma mark - 日历日期 Cell

@interface CalendarDayCell : UICollectionViewCell
@property (nonatomic, strong) UILabel *weekLabel;
@property (nonatomic, strong) UILabel *dayLabel;
@property (nonatomic, strong) UIView *dotView;
- (void)setDay:(NSDate *)day selected:(BOOL)selected isToday:(BOOL)isToday;
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

- (void)setDay:(NSDate *)day selected:(BOOL)selected isToday:(BOOL)isToday {
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
        _dotView.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        self.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        _weekLabel.textColor = [UIColor secondaryLabelColor];
        _dayLabel.textColor = isToday ? kAITodoAccentColor : [UIColor labelColor];
        _dotView.backgroundColor = kAITodoAccentColor;
    }
    _dotView.hidden = !isToday; // 小黄点只标今天
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
@property (nonatomic, strong) UILabel *monthLabel;
@property (nonatomic, strong) UICollectionView *calendarView;
@property (nonatomic, strong) UILabel *listHeaderLabel;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSArray<MainTodoItem *> *listTodos;
@property (nonatomic, assign) BOOL didInitialScroll;
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
    self.selectedDay = [NSDate date];
    self.currentMonth = [NSDate date];

    [self buildTopBar];
    [self buildMonthRow];
    [self buildCalendar];
    [self buildList];
    [self rebuildDays];
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

    UIButton *closeBtn = [self topBarButton:@"xmark"];
    closeBtn.tag = 0;
    [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:closeBtn];

    UIButton *pieBtn = [self topBarButton:@"chart.pie.fill"];
    pieBtn.tag = 1;
    [pieBtn addTarget:self action:@selector(statsTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:pieBtn];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"待办";
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textAlignment = NSTextAlignmentCenter;
    title.tag = 101;
    [self.topBar addSubview:title];

    UIButton *addBtn = [self topBarButton:@"plus.circle"];
    addBtn.tag = 3;
    [addBtn addTarget:self action:@selector(addTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:addBtn];
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
    UIButton *prev = [UIButton buttonWithType:UIButtonTypeSystem];
    [prev setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    [prev addTarget:self action:@selector(prevMonth) forControlEvents:UIControlEventTouchUpInside];
    prev.tag = 201;
    [self.view addSubview:prev];

    self.monthLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.monthLabel.font = [UIFont boldSystemFontOfSize:16];
    self.monthLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.monthLabel];

    UIButton *next = [UIButton buttonWithType:UIButtonTypeSystem];
    [next setImage:[UIImage systemImageNamed:@"chevron.right"] forState:UIControlStateNormal];
    [next addTarget:self action:@selector(nextMonth) forControlEvents:UIControlEventTouchUpInside];
    next.tag = 202;
    [self.view addSubview:next];
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

#pragma mark - 交互

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)statsTapped {
    NSArray *all = [AITodoManager allTodos];
    NSUInteger undone = [AITodoManager unfinishedCount];
    NSUInteger bookmarked = 0;
    for (MainTodoItem *m in all) {
        if (m.isBookmarked) bookmarked++;
    }
    UIAlertController *al = [UIAlertController alertControllerWithTitle:@"统计"
                                                                message:[NSString stringWithFormat:
                                                                         @"全部：%lu\n未完成：%lu\n已书签：%lu",
                                                                         (unsigned long)all.count,
                                                                         (unsigned long)undone,
                                                                         (unsigned long)bookmarked]
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [al addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:al animated:YES completion:nil];
}

- (void)addTapped {
    UIAlertController *al = [UIAlertController alertControllerWithTitle:@"新建待办"
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [al addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"写点什么…";
    }];
    [al addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [al addAction:[UIAlertAction actionWithTitle:@"添加"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *action) {
        NSString *text = [al.textFields.firstObject.text stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (text.length == 0) return;
        [AITodoManager addTodo:text atDate:[self dateOnSelectedDayAtCurrentTime]];
        [self reloadList];
    }]];
    [self presentViewController:al animated:YES completion:nil];
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

// 刷新某一行（勾选子任务后触发划线动画）
- (void)reloadRowForTodo:(MainTodoItem *)todo {
    NSUInteger idx = [self.listTodos indexOfObject:todo];
    if (idx != NSNotFound) {
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:idx inSection:0]]
                              withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (void)editTitleForTodo:(MainTodoItem *)todo {
    UIAlertController *al = [UIAlertController alertControllerWithTitle:@"编辑待办"
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [al addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = todo.title;
    }];
    [al addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [al addAction:[UIAlertAction actionWithTitle:@"保存"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *action) {
        [AITodoManager updateTodo:todo.identifier
                            title:al.textFields.firstObject.text
                             note:todo.note
                              due:todo.dueDate
                       bookmarked:todo.isBookmarked];
        [self reloadList];
    }]];
    [self presentViewController:al animated:YES completion:nil];
}

- (void)addSubTaskForTodo:(MainTodoItem *)todo {
    UIAlertController *al = [UIAlertController alertControllerWithTitle:@"添加子任务"
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [al addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"子任务内容…";
    }];
    [al addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [al addAction:[UIAlertAction actionWithTitle:@"添加"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *action) {
        [AITodoManager addSubTask:al.textFields.firstObject.text toTodo:todo.identifier];
        [self reloadList];
    }]];
    [self presentViewController:al animated:YES completion:nil];
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
    [cell setDay:day selected:selected isToday:isToday];
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
    [cell configureWithTodo:todo];
    cell.onToggleSelect = ^{
        [AITodoManager setTodo:todo.identifier selected:!todo.isSelected];
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
    cell.onLongPress = ^{
        [self editTitleForTodo:todo];
    };
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    MainTodoItem *todo = self.listTodos[indexPath.row];
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

    self.topBar.frame = CGRectMake(0, 0, w, sa.top + 44);
    UIButton *closeBtn = [self buttonInView:self.topBar tag:0];
    UIButton *pieBtn = [self buttonInView:self.topBar tag:1];
    UIButton *addBtn = [self buttonInView:self.topBar tag:3];
    closeBtn.frame = CGRectMake(8, sa.top, 44, 44);
    pieBtn.frame = CGRectMake(52, sa.top, 44, 44);
    addBtn.frame = CGRectMake(w - 52, sa.top, 44, 44);
    UILabel *title = [self.topBar viewWithTag:101];
    title.frame = CGRectMake(100, sa.top, w - 200, 44);

    CGFloat monthY = sa.top + 44 + 6;
    UIButton *prev = [self buttonInView:self.view tag:201];
    UIButton *next = [self buttonInView:self.view tag:202];
    prev.frame = CGRectMake(16, monthY, 40, 32);
    next.frame = CGRectMake(w - 56, monthY, 40, 32);
    self.monthLabel.frame = CGRectMake(60, monthY, w - 120, 32);

    CGFloat calY = monthY + 32 + 8;
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

- (UIButton *)buttonInView:(UIView *)view tag:(NSInteger)tag {
    return (UIButton *)[view viewWithTag:tag];
}

@end
