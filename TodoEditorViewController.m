#import "TodoEditorViewController.h"
#import "TodoMarkdown.h"
#import "AIConfig.h"
#import <objc/runtime.h>

static char kMdStartKey;
static char kMdEndKey;

@interface TodoEditorViewController ()
@property (nonatomic, copy) NSString *editorTitle;
@property (nonatomic, copy) void (^completion)(NSString *text);
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UIView *toolbar;
@property (nonatomic, strong) NSString *rawText;
@property (nonatomic, assign) BOOL previewing;
@property (nonatomic, strong) NSArray *toolButtons;
@property (nonatomic, assign) CGFloat keyboardInset;
@end

@implementation TodoEditorViewController

- (instancetype)initWithTitle:(NSString *)title
                  initialText:(NSString *)text
                   completion:(void (^)(NSString *text))completion {
    self = [super init];
    if (self) {
        _editorTitle = [title copy];
        _rawText = [text copy] ?: @"";
        _completion = [completion copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.editorTitle ?: @"编辑";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.edgesForExtendedLayout = UIRectEdgeNone;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone
                                        target:self action:@selector(saveTapped)];
    self.navigationItem.rightBarButtonItem.tintColor = kAITodoAccentColor;

    // 文本框
    self.textView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.textView.font = [UIFont systemFontOfSize:16];
    self.textView.text = self.rawText;
    self.textView.backgroundColor = [UIColor systemBackgroundColor];
    self.textView.layer.cornerRadius = 14;
    self.textView.textContainerInset = UIEdgeInsetsMake(12, 10, 12, 10);
    self.textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.textView];

    // 底部工具条
    self.toolbar = [[UIView alloc] initWithFrame:CGRectZero];
    self.toolbar.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    [self.view addSubview:self.toolbar];

    NSArray *defs = @[
        @{@"t": @"B",   @"s": @"**", @"a": @""},
        @{@"t": @"I",   @"s": @"*",  @"a": @""},
        @{@"t": @"H",   @"s": @"\n# ", @"a": @""},
        @{@"t": @"•",   @"s": @"\n- ", @"a": @""},
        @{@"t": @"☑",   @"s": @"\n- [ ] ", @"a": @""},
        @{@"t": @"`",   @"s": @"`",  @"a": @""},
        @{@"t": @"~~",  @"s": @"~~", @"a": @""},
    ];
    NSMutableArray *btns = [NSMutableArray array];
    for (NSDictionary *d in defs) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:d[@"t"] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        b.layer.cornerRadius = 8;
        b.backgroundColor = [UIColor systemBackgroundColor];
        objc_setAssociatedObject(b, &kMdStartKey, d[@"s"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(b, &kMdEndKey, d[@"a"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [b addTarget:self action:@selector(toolTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.toolbar addSubview:b];
        [btns addObject:b];
    }
    UIButton *preview = [UIButton buttonWithType:UIButtonTypeSystem];
    [preview setTitle:@"预览" forState:UIControlStateNormal];
    preview.titleLabel.font = [UIFont systemFontOfSize:13];
    preview.layer.cornerRadius = 8;
    preview.backgroundColor = kAITodoAccentColor;
    [preview setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [preview addTarget:self action:@selector(togglePreview) forControlEvents:UIControlEventTouchUpInside];
    [self.toolbar addSubview:preview];
    self.toolButtons = @[preview];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.textView becomeFirstResponder];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    UIEdgeInsets sa = self.view.safeAreaInsets;
    CGFloat toolH = 46;
    CGFloat toolBottom = b.size.height - self.keyboardInset;
    CGFloat toolBarH = toolH + (self.keyboardInset > 0 ? 0 : sa.bottom);
    self.toolbar.frame = CGRectMake(0, toolBottom - toolBarH, b.size.width, toolBarH);
    self.textView.frame = CGRectMake(16, 12, b.size.width - 32,
                                     CGRectGetMinY(self.toolbar.frame) - 24);

    // 工具按钮布局：8 个按钮等分
    NSArray *all = [self.toolbar.subviews filteredArrayUsingPredicate:
                    [NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary *bindings) {
        return [obj isKindOfClass:[UIButton class]];
    }]];
    CGFloat bw = (b.size.width - 16) / all.count;
    for (NSUInteger i = 0; i < all.count; i++) {
        UIButton *btn = all[i];
        btn.frame = CGRectMake(8 + i * bw, 6, bw - 8, 34);
    }
}

- (void)toolTapped:(UIButton *)sender {
    if (self.previewing) return;
    NSString *start = objc_getAssociatedObject(sender, &kMdStartKey);
    NSString *end = objc_getAssociatedObject(sender, &kMdEndKey) ?: @"";
    if ([start hasPrefix:@"\n"]) {
        // 行前缀（标题/列表/任务项）：插到当前行首
        [self insertLinePrefix:start];
        return;
    }
    [self wrapSelectionWith:start end:end];
}

- (void)wrapSelectionWith:(NSString *)start end:(NSString *)end {
    NSRange sel = self.textView.selectedRange;
    NSString *text = self.textView.text;
    if (sel.location == NSNotFound) sel = NSMakeRange(text.length, 0);
    NSString *selText = (sel.length > 0) ? [text substringWithRange:sel] : @"";
    NSString *replacement = [NSString stringWithFormat:@"%@%@%@", start, selText, end];
    self.textView.text = [text stringByReplacingCharactersInRange:sel withString:replacement];
    self.textView.selectedRange = NSMakeRange(sel.location + start.length + selText.length, 0);
}

- (void)insertLinePrefix:(NSString *)prefix {
    NSRange sel = self.textView.selectedRange;
    NSString *text = self.textView.text;
    if (sel.location == NSNotFound) sel = NSMakeRange(text.length, 0);
    NSRange line = [text lineRangeForRange:sel];
    NSString *lineText = [text substringWithRange:line];
    NSString *newText = [text stringByReplacingCharactersInRange:line
                                                      withString:[prefix stringByAppendingString:lineText]];
    self.textView.text = newText;
    self.textView.selectedRange = NSMakeRange(line.location + prefix.length, 0);
}

- (void)togglePreview {
    self.previewing = !self.previewing;
    UIButton *preview = self.toolButtons.firstObject;
    if (self.previewing) {
        self.rawText = self.textView.text;
        self.textView.attributedText = todoMarkdownString(self.rawText, 16);
        self.textView.editable = NO;
        [self.textView resignFirstResponder];
        [preview setTitle:@"编辑" forState:UIControlStateNormal];
    } else {
        self.textView.editable = YES;
        self.textView.text = self.rawText;
        [preview setTitle:@"预览" forState:UIControlStateNormal];
    }
}

- (void)saveTapped {
    NSString *text = self.previewing ? self.rawText : self.textView.text;
    if (self.completion) self.completion(text ?: @"");
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)keyboardWillChange:(NSNotification *)note {
    CGRect kbEnd = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat bottom = 0;
    if (!CGRectIsNull(kbEnd)) {
        CGRect kbInView = [self.view convertRect:kbEnd fromView:nil];
        bottom = MAX(0, CGRectIntersection(self.view.bounds, kbInView).size.height);
        if (bottom > self.view.bounds.size.height * 0.75) bottom = 0;
    }
    self.keyboardInset = bottom;
    [self.view setNeedsLayout];
}

@end
