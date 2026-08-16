#import "TodoStatsViewController.h"
#import "AITodoManager.h"

@interface TodoStatsViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@end

@implementation TodoStatsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"今日统计";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"关闭"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(closeTapped)];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];
    self.contentView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.scrollView addSubview:self.contentView];

    [self buildUI];
}

- (void)buildUI {
    NSDictionary *stats = [self computeStats];
    NSArray *today = stats[@"today"];   // @[新增, 已完成, 未完成]
    NSArray *all = stats[@"all"];       // @[总数, 已完成, 未完成, 已书签]
    NSArray *week = stats[@"week"];     // @[@{@"label":, @"text":}, ...]

    CGFloat y = 12;
    y = [self addCardTitle:@"今日" y:y];
    y = [self addCardRows:@[
        @{@"title": @"新增", @"value": today[0]},
        @{@"title": @"已完成", @"value": today[1]},
        @{@"title": @"未完成", @"value": today[2]},
    ] y:y];

    y += 12;
    y = [self addCardTitle:@"全部" y:y];
    y = [self addCardRows:@[
        @{@"title": @"全部待办", @"value": all[0]},
        @{@"title": @"已完成", @"value": all[1]},
        @{@"title": @"未完成", @"value": all[2]},
        @{@"title": @"已书签", @"value": all[3]},
    ] y:y];

    y += 12;
    y = [self addCardTitle:@"近 7 天" y:y];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *d in week) {
        [rows addObject:@{@"title": d[@"label"], @"value": d[@"text"]}];
    }
    y = [self addCardRows:rows y:y];

    CGFloat width = self.view.bounds.size.width;
    self.contentView.frame = CGRectMake(0, 0, width, y + 20);
    self.scrollView.contentSize = CGSizeMake(width, y + 20);
}

- (CGFloat)addCardTitle:(NSString *)text y:(CGFloat)y {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, y, 200, 28)];
    label.text = text;
    label.font = [UIFont systemFontOfSize:13];
    label.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:label];
    return y + 28 + 4;
}

- (CGFloat)addCardRows:(NSArray<NSDictionary *> *)rows y:(CGFloat)y {
    CGFloat width = self.view.bounds.size.width;
    CGFloat cardW = width - 32;
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, y, cardW, rows.count * 44)];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 12;
    card.layer.masksToBounds = YES;
    [self.contentView addSubview:card];

    for (NSUInteger i = 0; i < rows.count; i++) {
        NSDictionary *row = rows[i];
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, i * 44, cardW - 150, 44)];
        title.text = row[@"title"];
        title.font = [UIFont systemFontOfSize:16];
        title.textColor = [UIColor labelColor];
        [card addSubview:title];
        UILabel *value = [[UILabel alloc] initWithFrame:CGRectMake(cardW - 140, i * 44, 124, 44)];
        value.text = [NSString stringWithFormat:@"%@", row[@"value"]];
        value.font = [UIFont systemFontOfSize:15];
        value.textColor = [UIColor secondaryLabelColor];
        value.textAlignment = NSTextAlignmentRight;
        [card addSubview:value];
    }
    return y + rows.count * 44;
}

- (NSDictionary *)computeStats {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *todayStart = [cal startOfDayForDate:[NSDate date]];
    NSDate *tomorrow = [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:todayStart options:0];

    NSUInteger dayAdd = 0, dayDone = 0, dayUndone = 0;
    NSUInteger total = 0, allDone = 0, allUndone = 0, bookmarked = 0;
    for (MainTodoItem *m in [AITodoManager allTodos]) {
        total++;
        if (m.done) allDone++; else allUndone++;
        if (m.isBookmarked) bookmarked++;
        if ([m.createTime compare:todayStart] != NSOrderedAscending &&
            [m.createTime compare:tomorrow] == NSOrderedAscending) {
            dayAdd++;
            if (m.done) dayDone++; else dayUndone++;
        }
    }

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    fmt.dateFormat = @"M月d日 EEE";

    NSMutableArray *week = [NSMutableArray array];
    for (NSInteger i = 6; i >= 0; i--) {
        NSDate *day = [cal dateByAddingUnit:NSCalendarUnitDay value:-i toDate:[NSDate date] options:0];
        NSDate *start = [cal startOfDayForDate:day];
        NSDate *end = [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:start options:0];
        NSUInteger add = 0, done = 0;
        for (MainTodoItem *m in [AITodoManager allTodos]) {
            if ([m.createTime compare:start] != NSOrderedAscending &&
                [m.createTime compare:end] == NSOrderedAscending) {
                add++;
                if (m.done) done++;
            }
        }
        [week addObject:@{@"label": [fmt stringFromDate:day],
                          @"text": [NSString stringWithFormat:@"新增 %lu · 完成 %lu",
                                    (unsigned long)add, (unsigned long)done]}];
    }

    return @{
        @"today": @[@(dayAdd), @(dayDone), @(dayUndone)],
        @"all": @[@(total), @(allDone), @(allUndone), @(bookmarked)],
        @"week": week
    };
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
