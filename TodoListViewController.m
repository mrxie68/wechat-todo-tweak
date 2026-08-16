#import "TodoListViewController.h"
#import "AITodoManager.h"
#import "TodoEditorViewController.h"
#import "CustomTodoTableViewCell.h"
#import "AIConfig.h"

@interface TodoListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, assign) BOOL bookmarkMode;
@property (nonatomic, assign) NSInteger filterIndex; // 0 全部待办 / 1 已完成 / 2 未完成
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *segmentControl;
@property (nonatomic, strong) NSArray<MainTodoItem *> *items;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSMutableSet *expandedIds; // 展开状态只存内存
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
    self.expandedIds = [NSMutableSet set];

    // 全部页：顶部三段切换（全部待办 / 已完成 / 未完成）
    if (!self.bookmarkMode) {
        self.segmentControl = [[UISegmentedControl alloc] initWithItems:@[@"全部待办", @"已完成", @"未完成"]];
        self.segmentControl.selectedSegmentIndex = self.filterIndex;
        [self.segmentControl addTarget:self
                                action:@selector(segmentChanged)
                      forControlEvents:UIControlEventValueChanged];
        [self.view addSubview:self.segmentControl];
    }

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
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
    if (self.bookmarkMode) {
        self.emptyLabel.text = @"还没有书签\n在待办列表右滑卡片即可收藏";
    } else if (self.filterIndex == 1) {
        self.emptyLabel.text = @"还没有已完成的待办";
    } else if (self.filterIndex == 2) {
        self.emptyLabel.text = @"没有未完成的待办 🎉";
    } else {
        self.emptyLabel.text = @"还没有待办";
    }
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];

    [self reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    UIEdgeInsets sa = self.view.safeAreaInsets;
    if (self.segmentControl) {
        CGFloat segY = sa.top + 8;
        self.segmentControl.frame = CGRectMake(16, segY, b.size.width - 32, 32);
        CGFloat tableY = segY + 32 + 8;
        self.tableView.frame = CGRectMake(0, tableY, b.size.width,
                                          b.size.height - tableY - sa.bottom);
        self.emptyLabel.frame = CGRectMake(32, tableY + (b.size.height - tableY - sa.bottom) / 2.0 - 60,
                                           b.size.width - 64, 80);
    } else {
        self.tableView.frame = b;
        self.emptyLabel.frame = CGRectMake(32, b.size.height / 2.0 - 60,
                                           b.size.width - 64, 80);
    }
}

- (void)segmentChanged {
    self.filterIndex = self.segmentControl.selectedSegmentIndex;
    [self reloadData];
}

- (void)reloadData {
    NSMutableArray *arr = [[AITodoManager allTodos] mutableCopy];
    if (self.bookmarkMode) {
        NSMutableArray *bm = [NSMutableArray array];
        for (MainTodoItem *m in arr) {
            if (m.isBookmarked) [bm addObject:m];
        }
        arr = bm;
    } else if (self.filterIndex == 1) {
        NSMutableArray *done = [NSMutableArray array];
        for (MainTodoItem *m in arr) {
            if (m.done) [done addObject:m];
        }
        arr = done;
    } else if (self.filterIndex == 2) {
        NSMutableArray *undone = [NSMutableArray array];
        for (MainTodoItem *m in arr) {
            if (!m.done) [undone addObject:m];
        }
        arr = undone;
    }
    [arr sortUsingComparator:^NSComparisonResult(MainTodoItem *a, MainTodoItem *b) {
        return [b.createTime compare:a.createTime]; // 新的在前
    }];
    self.items = arr;
    self.tableView.hidden = (arr.count == 0);
    self.emptyLabel.hidden = (arr.count > 0);
    if (self.bookmarkMode) {
        self.emptyLabel.text = @"还没有书签\n在待办列表右滑卡片即可收藏";
    } else if (self.filterIndex == 1) {
        self.emptyLabel.text = @"还没有已完成的待办";
    } else if (self.filterIndex == 2) {
        self.emptyLabel.text = @"没有未完成的待办 🎉";
    } else {
        self.emptyLabel.text = @"还没有待办";
    }
    [self.tableView reloadData];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)addTapped {
    [self presentMultilineInputWithTitle:@"新建待办"
                             initialText:@""
                              completion:^(NSString *text) {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) return;
        MainTodoItem *m = [AITodoManager addTodo:trimmed];
        if (self.bookmarkMode && m) {
            [AITodoManager toggleBookmarkForTodo:m.identifier]; // 书签页新建默认加书签
        }
        [self reloadData];
    }];
}

#pragma mark - 编辑/子任务（与主页行为一致）

- (void)presentMultilineInputWithTitle:(NSString *)title
                           initialText:(NSString *)initial
                            completion:(void (^)(NSString *text))completion {
    TodoEditorViewController *vc = [[TodoEditorViewController alloc] initWithTitle:title
                                                                      initialText:initial
                                                                       completion:completion];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
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

- (void)editTitleForTodo:(MainTodoItem *)todo {
    [self presentMultilineInputWithTitle:@"编辑待办"
                             initialText:todo.title
                              completion:^(NSString *text) {
        [AITodoManager updateTodo:todo.identifier
                            title:text
                             note:todo.note
                              due:todo.dueDate
                       bookmarked:todo.isBookmarked];
        [self reloadData];
    }];
}

- (void)addSubTaskForTodo:(MainTodoItem *)todo {
    [self presentMultilineInputWithTitle:@"添加子任务"
                             initialText:@""
                              completion:^(NSString *text) {
        [AITodoManager addSubTask:text toTodo:todo.identifier];
        [self.expandedIds addObject:@(todo.identifier)];
        [self reloadData];
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
            [self reloadData];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"删除"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [AITodoManager removeSubTask:sub.identifier inTodo:todo.identifier];
        [self reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - UITableView（复用主页浅紫色条目）

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CustomTodoTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TodoCardCell"];
    if (!cell) {
        cell = [[CustomTodoTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                              reuseIdentifier:@"TodoCardCell"];
    }
    MainTodoItem *todo = self.items[indexPath.row];
    todo.isSelected = [self.expandedIds containsObject:@(todo.identifier)];
    [cell configureWithTodo:todo];
    cell.onToggleSelect = ^{
        if ([self.expandedIds containsObject:@(todo.identifier)]) {
            [self.expandedIds removeObject:@(todo.identifier)];
        } else {
            [self.expandedIds addObject:@(todo.identifier)];
        }
        [self reloadData];
    };
    cell.onAddSubTask = ^{
        [self addSubTaskForTodo:todo];
    };
    cell.onToggleDone = ^{
        [AITodoManager markTodo:todo.identifier done:!todo.done];
        [self reloadData];
    };
    cell.onToggleSubTask = ^(SubTaskItem *sub) {
        [AITodoManager toggleSubTask:sub.identifier inTodo:todo.identifier];
        [self reloadData];
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
    MainTodoItem *todo = self.items[indexPath.row];
    todo.isSelected = [self.expandedIds containsObject:@(todo.identifier)];
    return [CustomTodoTableViewCell heightForTodo:todo width:tableView.bounds.size.width];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    MainTodoItem *todo = self.items[indexPath.row];
    UIContextualAction *del = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:@"删除"
                          handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
        [AITodoManager deleteTodo:todo.identifier];
        [self reloadData];
        completion(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

// 右滑 = 收藏/取消收藏
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    MainTodoItem *todo = self.items[indexPath.row];
    UIContextualAction *doneAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:todo.done ? @"取消完成" : @"完成"
                          handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
        [AITodoManager markTodo:todo.identifier done:!todo.done];
        [self reloadData];
        completion(YES);
    }];
    doneAction.backgroundColor = [UIColor systemGreenColor];
    UIContextualAction *bookmark = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:todo.isBookmarked ? @"取消书签" : @"书签"
                          handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
        [AITodoManager toggleBookmarkForTodo:todo.identifier];
        [self reloadData];
        completion(YES);
    }];
    bookmark.backgroundColor = [UIColor colorWithRed:0.88 green:0.65 blue:0.18 alpha:1.0]; // 金色
    return [UISwipeActionsConfiguration configurationWithActions:@[doneAction, bookmark]];
}

@end
