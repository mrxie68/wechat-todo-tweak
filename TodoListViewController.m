#import "TodoListViewController.h"
#import "AITodoManager.h"
#import "TodoEditorViewController.h"
#import "AIConfig.h"

@interface TodoListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, assign) BOOL bookmarkMode;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<MainTodoItem *> *items;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation TodoListViewController

+ (instancetype)allPage {
    TodoListViewController *vc = [[TodoListViewController alloc] init];
    vc.bookmarkMode = NO;
    return vc;
}

+ (instancetype)bookmarkPage {
    TodoListViewController *vc = [[TodoListViewController alloc] init];
    vc.bookmarkMode = YES;
    return vc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.bookmarkMode ? @"全部书签" : @"全部待办";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"关闭"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(closeTapped)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self
                                                      action:@selector(addTapped)];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.rowHeight = 64;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyLabel.font = [UIFont systemFontOfSize:14];
    self.emptyLabel.text = self.bookmarkMode ? @"还没有书签\n在待办列表右滑卡片即可收藏" : @"还没有待办";
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];

    [self reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.tableView.frame = self.view.bounds;
    self.emptyLabel.frame = CGRectMake(32, self.view.bounds.size.height / 2.0 - 60,
                                       self.view.bounds.size.width - 64, 80);
}

- (void)reloadData {
    NSMutableArray *arr = [[AITodoManager allTodos] mutableCopy];
    if (self.bookmarkMode) {
        NSMutableArray *bm = [NSMutableArray array];
        for (MainTodoItem *m in arr) {
            if (m.isBookmarked) [bm addObject:m];
        }
        arr = bm;
    }
    [arr sortUsingComparator:^NSComparisonResult(MainTodoItem *a, MainTodoItem *b) {
        return [b.createTime compare:a.createTime]; // 新的在前
    }];
    self.items = arr;
    self.tableView.hidden = (arr.count == 0);
    self.emptyLabel.hidden = (arr.count > 0);
    [self.tableView reloadData];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)addTapped {
    TodoEditorViewController *vc = [[TodoEditorViewController alloc] initWithTitle:@"新建待办"
                                                                      initialText:@""
                                                                       completion:^(NSString *text) {
        if (text.length == 0) return;
        MainTodoItem *m = [AITodoManager addTodo:text];
        if (self.bookmarkMode && m) {
            [AITodoManager toggleBookmarkForTodo:m.identifier]; // 书签页新建默认加书签，方便继续记录
        }
        [self reloadData];
    }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - 时间格式化

- (NSString *)dateTextForItem:(MainTodoItem *)item {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    NSCalendar *cal = [NSCalendar currentCalendar];
    if ([[cal startOfDayForDate:item.createTime] isEqualToDate:
         [cal startOfDayForDate:[NSDate date]]]) {
        fmt.dateFormat = @"今天 HH:mm";
    } else {
        fmt.dateFormat = @"M月d日 HH:mm";
    }
    return [fmt stringFromDate:item.createTime];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *rid = @"TodoListCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:rid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:rid];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    MainTodoItem *m = self.items[indexPath.row];
    NSString *title = m.title.length > 0 ? m.title : @"（无标题）";
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.textLabel.textColor = m.done ? [UIColor secondaryLabelColor] : [UIColor labelColor];
    NSDictionary *attrs = m.done ? @{NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle)} : nil;
    cell.textLabel.attributedText = [[NSAttributedString alloc] initWithString:title attributes:attrs];
    cell.detailTextLabel.text = [self dateTextForItem:m];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];

    // 书签角标
    UILabel *bm = [UILabel new];
    bm.text = m.isBookmarked ? @"🔖" : @"";
    bm.font = [UIFont systemFontOfSize:16];
    [bm sizeToFit];
    cell.accessoryView = bm;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    MainTodoItem *m = self.items[indexPath.row];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:m.title
                                                                   message:[self dateTextForItem:m]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:(m.done ? @"标记未完成" : @"标记完成")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        [AITodoManager markTodo:m.identifier done:!m.done];
        [self reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"编辑内容"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        TodoEditorViewController *vc = [[TodoEditorViewController alloc] initWithTitle:@"编辑待办"
                                                                          initialText:m.title
                                                                           completion:^(NSString *text) {
            if (text.length == 0) return;
            [AITodoManager updateTodo:m.identifier title:text note:m.note
                                  due:m.dueDate bookmarked:m.isBookmarked];
            [self reloadData];
        }];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:nav animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:(m.isBookmarked ? @"取消收藏" : @"收藏")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        [AITodoManager toggleBookmarkForTodo:m.identifier];
        [self reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"删除"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) {
        [AITodoManager deleteTodo:m.identifier];
        [self reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
