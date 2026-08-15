#import "TodoEditorViewController.h"
#import "AIConfig.h"

@interface TodoEditorViewController () <UITextViewDelegate>
@property (nonatomic, copy) NSString *editorTitle;
@property (nonatomic, copy) NSString *initialText;
@property (nonatomic, copy) void (^completion)(NSString *text);
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, assign) CGFloat keyboardInset;
@end

@implementation TodoEditorViewController

- (instancetype)initWithTitle:(NSString *)title
                  initialText:(NSString *)text
                   completion:(void (^)(NSString *text))completion {
    self = [super init];
    if (self) {
        _editorTitle = [title copy];
        _completion = [completion copy];
        _initialText = [text copy] ?: @"";
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

    // 大圆角文本框
    self.textView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.textView.font = [UIFont systemFontOfSize:16];
    self.textView.text = self.initialText;
    self.textView.backgroundColor = [UIColor systemBackgroundColor];
    self.textView.layer.cornerRadius = 16;
    self.textView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.textView.layer.shadowOpacity = 0.05;
    self.textView.layer.shadowOffset = CGSizeMake(0, 2);
    self.textView.layer.shadowRadius = 8;
    self.textView.textContainerInset = UIEdgeInsetsMake(16, 12, 16, 12);
    self.textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.textView.delegate = self;
    [self.view addSubview:self.textView];

    // 占位提示
    self.placeholderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.placeholderLabel.text = @"写点什么…";
    self.placeholderLabel.font = [UIFont systemFontOfSize:16];
    self.placeholderLabel.textColor = [UIColor systemGray3Color];
    self.placeholderLabel.hidden = (self.initialText.length > 0);
    [self.view addSubview:self.placeholderLabel];

    // 字数统计
    self.countLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.countLabel.font = [UIFont systemFontOfSize:12];
    self.countLabel.textColor = [UIColor secondaryLabelColor];
    self.countLabel.textAlignment = NSTextAlignmentRight;
    [self.view addSubview:self.countLabel];
    [self updateCount];

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
    CGFloat bottom = b.size.height - self.keyboardInset;
    self.textView.frame = CGRectMake(16, 12, b.size.width - 32, bottom - 12 - 34);
    self.placeholderLabel.frame = CGRectMake(16 + 12 + 4, 12 + 16 + 2,
                                             b.size.width - 32 - 32, 24);
    self.countLabel.frame = CGRectMake(16, CGRectGetMaxY(self.textView.frame) + 6,
                                       b.size.width - 32, 20);
}

- (void)textViewDidChange:(UITextView *)textView {
    self.placeholderLabel.hidden = (textView.text.length > 0);
    [self updateCount];
}

- (void)updateCount {
    self.countLabel.text = [NSString stringWithFormat:@"%lu 字",
                            (unsigned long)self.textView.text.length];
}

- (void)saveTapped {
    if (self.completion) self.completion(self.textView.text ?: @"");
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
