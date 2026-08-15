#import "TodoDetailViewController.h"
#import "AITodoManager.h"
#import "AIConfig.h"

static NSString *todoDetailDateString(double ts) {
    if (ts <= 0) return @"";
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm";
    return [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:ts]];
}

@interface TodoDetailViewController () <UITextViewDelegate>
@property (nonatomic, strong) NSDictionary *todo;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UITextView *contentViewText;
@property (nonatomic, strong) UITextView *noteViewText;
@property (nonatomic, strong) UILabel *dueValueLabel;
@property (nonatomic, strong) UIButton *clearDueButton;
@property (nonatomic, strong) UISwitch *importantSwitch;
@property (nonatomic, strong) UISwitch *doneSwitch;
@property (nonatomic, assign) double dueValue;
@end

@implementation TodoDetailViewController

- (instancetype)initWithTodo:(NSDictionary *)todo {
    self = [super init];
    if (self) {
        _todo = [todo copy];
        _dueValue = [todo[@"due"] doubleValue];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"待办详情";
    self.view.backgroundColor = [UIColor colorWithRed:0.945 green:0.945 blue:0.957 alpha:1.0];
    self.edgesForExtendedLayout = UIRectEdgeNone;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone
                                        target:self action:@selector(saveTapped)];
    self.navigationItem.rightBarButtonItem.tintColor = [UIColor systemGreenColor];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];
    self.contentView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.scrollView addSubview:self.contentView];

    // 内容
    self.contentViewText = [self makeTextView];
    self.contentViewText.text = self.todo[@"content"] ?: @"";
    self.contentViewText.font = [UIFont systemFontOfSize:17];
    [self.contentView addSubview:self.contentViewText];

    // 截止时间
    UIButton *dueRow = [self makeRowButton];
    [dueRow addTarget:self action:@selector(dueTapped) forControlEvents:UIControlEventTouchUpInside];
    dueRow.tag = 101;
    [self.contentView addSubview:dueRow];
    UILabel *dueTitle = [self makeRowLabel:@"截止时间"];
    [dueRow addSubview:dueTitle];
    self.dueValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.dueValueLabel.font = [UIFont systemFontOfSize:15];
    self.dueValueLabel.textColor = [UIColor labelColor];
    self.dueValueLabel.textAlignment = NSTextAlignmentRight;
    [dueRow addSubview:self.dueValueLabel];
    self.clearDueButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearDueButton setTitle:@"清除" forState:UIControlStateNormal];
    [self.clearDueButton addTarget:self action:@selector(clearDueTapped) forControlEvents:UIControlEventTouchUpInside];
    [dueRow addSubview:self.clearDueButton];

    // 重要
    UIView *importantRow = [self makeRowView];
    importantRow.tag = 102;
    [self.contentView addSubview:importantRow];
    UILabel *importantTitle = [self makeRowLabel:@"重要"];
    [importantRow addSubview:importantTitle];
    self.importantSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.importantSwitch.onTintColor = [UIColor systemGreenColor];
    self.importantSwitch.on = [self.todo[@"important"] boolValue];
    [importantRow addSubview:self.importantSwitch];

    // 状态
    UIView *doneRow = [self makeRowView];
    doneRow.tag = 103;
    [self.contentView addSubview:doneRow];
    UILabel *doneTitle = [self makeRowLabel:@"已完成"];
    [doneRow addSubview:doneTitle];
    self.doneSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.doneSwitch.onTintColor = [UIColor systemGreenColor];
    self.doneSwitch.on = [self.todo[@"done"] boolValue];
    [doneRow addSubview:self.doneSwitch];

    // 备注
    UILabel *noteTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    noteTitle.text = @"备注";
    noteTitle.tag = 104;
    noteTitle.font = [UIFont systemFontOfSize:13];
    noteTitle.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:noteTitle];
    self.noteViewText = [self makeTextView];
    self.noteViewText.text = self.todo[@"note"] ?: @"";
    [self.contentView addSubview:self.noteViewText];

    // 信息
    UILabel *infoLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    infoLabel.font = [UIFont systemFontOfSize:12];
    infoLabel.textColor = [UIColor secondaryLabelColor];
    infoLabel.textAlignment = NSTextAlignmentCenter;
    double created = [self.todo[@"created"] doubleValue];
    double doneAt = [self.todo[@"doneAt"] doubleValue];
    infoLabel.text = [NSString stringWithFormat:@"#%@ · 创建于 %@%@",
                      self.todo[@"id"], todoDetailDateString(created),
                      doneAt > 0 ? [NSString stringWithFormat:@" · 完成于 %@", todoDetailDateString(doneAt)] : @""];
    infoLabel.tag = 105;
    [self.contentView addSubview:infoLabel];

    // 删除
    UIButton *deleteBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [deleteBtn setTitle:@"删除这条待办" forState:UIControlStateNormal];
    [deleteBtn setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    deleteBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    deleteBtn.backgroundColor = [UIColor whiteColor];
    deleteBtn.layer.cornerRadius = 12;
    [deleteBtn addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
    deleteBtn.tag = 106;
    [self.contentView addSubview:deleteBtn];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [self updateDueUI];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UITextView *)makeTextView {
    UITextView *v = [[UITextView alloc] initWithFrame:CGRectZero];
    v.font = [UIFont systemFontOfSize:15];
    v.backgroundColor = [UIColor whiteColor];
    v.layer.cornerRadius = 12;
    v.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
    return v;
}

- (UIView *)makeRowView {
    UIView *v = [[UIView alloc] initWithFrame:CGRectZero];
    v.backgroundColor = [UIColor whiteColor];
    v.layer.cornerRadius = 12;
    return v;
}

- (UIButton *)makeRowButton {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.backgroundColor = [UIColor whiteColor];
    b.layer.cornerRadius = 12;
    return b;
}

- (UILabel *)makeRowLabel:(NSString *)text {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = [UIFont systemFontOfSize:15];
    l.textColor = [UIColor labelColor];
    return l;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat inset = 16;
    CGFloat cardW = w - inset * 2;
    CGFloat y = 12;

    self.contentViewText.frame = CGRectMake(inset, y, cardW, 110);
    y += 110 + 12;

    CGFloat rowH = 48;
    UIView *dueRowV = [self.contentView viewWithTag:101];
    dueRowV.frame = CGRectMake(inset, y, cardW, rowH);
    ((UILabel *)dueRowV.subviews[0]).frame = CGRectMake(14, 0, 90, rowH);
    self.dueValueLabel.frame = CGRectMake(100, 0, cardW - 150, rowH);
    self.clearDueButton.frame = CGRectMake(cardW - 64, 0, 56, rowH);
    y += rowH + 12;

    UIView *importantRowV = [self.contentView viewWithTag:102];
    importantRowV.frame = CGRectMake(inset, y, cardW, rowH);
    ((UILabel *)importantRowV.subviews[0]).frame = CGRectMake(14, 0, 90, rowH);
    self.importantSwitch.frame = CGRectMake(cardW - 60, (rowH - 31) / 2.0, 51, 31);
    y += rowH + 12;

    UIView *doneRowV = [self.contentView viewWithTag:103];
    doneRowV.frame = CGRectMake(inset, y, cardW, rowH);
    ((UILabel *)doneRowV.subviews[0]).frame = CGRectMake(14, 0, 90, rowH);
    self.doneSwitch.frame = CGRectMake(cardW - 60, (rowH - 31) / 2.0, 51, 31);
    y += rowH + 12;

    UILabel *noteTitle = [self.contentView viewWithTag:104];
    noteTitle.frame = CGRectMake(inset + 4, y, cardW, 18);
    y += 18 + 6;
    self.noteViewText.frame = CGRectMake(inset, y, cardW, 80);
    y += 80 + 12;

    UILabel *infoLabel = [self.contentView viewWithTag:105];
    infoLabel.frame = CGRectMake(inset, y, cardW, 20);
    y += 20 + 12;

    UIButton *deleteBtn = [self.contentView viewWithTag:106];
    deleteBtn.frame = CGRectMake(inset, y, cardW, 46);
    y += 46 + 20;

    self.contentView.frame = CGRectMake(0, 0, w, y);
    self.scrollView.contentSize = CGSizeMake(w, y);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateDueUI];
}

- (void)updateDueUI {
    if (self.dueValue > 0) {
        self.dueValueLabel.text = todoDetailDateString(self.dueValue);
        self.dueValueLabel.textColor = [UIColor labelColor];
        self.clearDueButton.hidden = NO;
    } else {
        self.dueValueLabel.text = @"未设置";
        self.dueValueLabel.textColor = [UIColor secondaryLabelColor];
        self.clearDueButton.hidden = YES;
    }
}

- (void)dueTapped {
    UIAlertController *al = [UIAlertController alertControllerWithTitle:@"设置截止时间"
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleAlert];
    UIViewController *holder = [[UIViewController alloc] init];
    holder.preferredContentSize = CGSizeMake(280, 180);
    UIDatePicker *picker = [[UIDatePicker alloc] initWithFrame:CGRectMake(10, 0, 260, 180)];
    picker.datePickerMode = UIDatePickerModeDateAndTime;
    if (@available(iOS 13.4, *)) {
        picker.preferredDatePickerStyle = UIDatePickerStyleWheels;
    }
    picker.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    if (self.dueValue > 0) {
        picker.date = [NSDate dateWithTimeIntervalSince1970:self.dueValue];
    } else {
        picker.date = [NSDate dateWithTimeInterval:3600 sinceDate:[NSDate date]];
    }
    [holder.view addSubview:picker];
    [al setValue:holder forKey:@"contentViewController"];
    [al addAction:[UIAlertAction actionWithTitle:@"清除"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *action) {
        self.dueValue = 0;
        [self updateDueUI];
    }]];
    [al addAction:[UIAlertAction actionWithTitle:@"确定"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *action) {
        self.dueValue = picker.date.timeIntervalSince1970;
        [self updateDueUI];
    }]];
    [al addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:al animated:YES completion:nil];
}

- (void)clearDueTapped {
    self.dueValue = 0;
    [self updateDueUI];
}

- (void)saveTapped {
    NSString *content = [self.contentViewText.text stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (content.length == 0) {
        UIAlertController *warn = [UIAlertController alertControllerWithTitle:@"内容为空"
                                                                      message:@"待办内容不能为空。"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [warn addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:warn animated:YES completion:nil];
        return;
    }
    BOOL ok = [AITodoManager updateTodo:[self.todo[@"id"] integerValue]
                                content:content
                                   note:self.noteViewText.text
                                    due:self.dueValue
                              important:self.importantSwitch.isOn];
    if (self.doneSwitch.isOn != [self.todo[@"done"] boolValue]) {
        [AITodoManager markTodo:[self.todo[@"id"] integerValue] done:self.doneSwitch.isOn];
    }
    if (ok) [self dismissOrPop];
}

- (void)cancelTapped {
    [self dismissOrPop];
}

- (void)deleteTapped {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"删除待办"
                                                                     message:@"确定删除这条待办吗？"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"删除"
                                                style:UIAlertActionStyleDestructive
                                              handler:^(UIAlertAction *action) {
        [AITodoManager deleteTodo:[self.todo[@"id"] integerValue]];
        [self dismissOrPop];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)dismissOrPop {
    if (self.navigationController.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    } else if (self.navigationController) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)keyboardWillChange:(NSNotification *)note {
    CGRect kbEnd = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat bottom = 0;
    if (!CGRectIsNull(kbEnd)) {
        CGRect kbInView = [self.view convertRect:kbEnd fromView:nil];
        bottom = MAX(0, CGRectIntersection(self.view.bounds, kbInView).size.height);
        if (bottom > self.view.bounds.size.height * 0.75) bottom = 0;
    }
    self.scrollView.contentInset = UIEdgeInsetsMake(0, 0, bottom, 0);
    self.scrollView.scrollIndicatorInsets = self.scrollView.contentInset;
}

@end
