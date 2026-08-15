#import "CustomTodoTableViewCell.h"
#import "AIConfig.h"
#import "TodoMarkdown.h"

static UIColor *cardUnselectedColor(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
            return trait.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor secondarySystemGroupedBackgroundColor]
                : [UIColor colorWithRed:0.93 green:0.90 blue:0.97 alpha:1.0]; // 浅紫
        }];
    }
    return [UIColor colorWithRed:0.93 green:0.90 blue:0.97 alpha:1.0];
}

static UIColor *cardSelectedColor(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
            return trait.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor systemGray5Color]
                : [UIColor colorWithRed:0.85 green:0.78 blue:0.95 alpha:1.0]; // 稍深浅紫
        }];
    }
    return [UIColor colorWithRed:0.85 green:0.78 blue:0.95 alpha:1.0];
}

// 估算子任务文字行数（中文按字号宽度，英文近似）
static NSInteger todoSubLines(NSString *text, CGFloat width) {
    if (text.length == 0) return 1;
    CGFloat perLine = MAX(1.0, width / 13.0);
    return MAX(1, (NSInteger)ceil(text.length / perLine));
}

@interface CustomTodoTableViewCell () <UIGestureRecognizerDelegate>
@end

@implementation CustomTodoTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _timeLabel.font = [UIFont systemFontOfSize:13];
        _timeLabel.textColor = [UIColor secondaryLabelColor];
        [self.contentView addSubview:_timeLabel];

        _cardView = [[UIView alloc] initWithFrame:CGRectZero];
        _cardView.layer.cornerRadius = 14;
        _cardView.clipsToBounds = YES;
        [self.contentView addSubview:_cardView];

        _iconBg = [[UIView alloc] initWithFrame:CGRectZero];
        _iconBg.layer.cornerRadius = 9;
        [self.cardView addSubview:_iconBg];

        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        UIImage *cam = [UIImage systemImageNamed:@"camera.fill"];
        _iconView.image = cam ?: [UIImage systemImageNamed:@"tag.fill"];
        [self.iconBg addSubview:_iconView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.numberOfLines = 2;
        _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        [self.cardView addSubview:_titleLabel];

        _bookmarkButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_bookmarkButton addTarget:self action:@selector(bookmarkTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.cardView addSubview:_bookmarkButton];

        _plusButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_plusButton addTarget:self action:@selector(plusTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.cardView addSubview:_plusButton];

        self.cardTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                     action:@selector(cardTapped)];
        self.cardTapGesture.delegate = self;
        [self.cardView addGestureRecognizer:self.cardTapGesture];
        self.cardLongPressGesture =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(cardLongPressed:)];
        self.cardLongPressGesture.minimumPressDuration = 0.35;
        self.cardLongPressGesture.delegate = self;
        [self.cardView addGestureRecognizer:self.cardLongPressGesture];

        _subRows = [NSMutableArray array];
    }
    return self;
}

- (void)cardTapped {
    if (self.onToggleSelect) self.onToggleSelect();
}

- (void)cardLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan && self.onLongPress) {
        self.onLongPress();
    }
}

- (void)configureWithTodo:(MainTodoItem *)todo {
    _todo = todo;
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm";
    _timeLabel.text = [fmt stringFromDate:todo.createTime];

    _cardView.backgroundColor = todo.isSelected ? cardSelectedColor() : cardUnselectedColor();

    // 图标
    _iconBg.backgroundColor = todo.isSelected
        ? [UIColor colorWithRed:0.78 green:0.68 blue:0.94 alpha:1.0]
        : [UIColor colorWithRed:0.84 green:0.77 blue:0.95 alpha:1.0];
    _iconView.tintColor = todo.isSelected
        ? [UIColor colorWithRed:0.42 green:0.30 blue:0.72 alpha:1.0]
        : [UIColor colorWithRed:0.45 green:0.34 blue:0.72 alpha:1.0];

    // 标题（按 Markdown 渲染）
    NSMutableAttributedString *titleAtt = [todoMarkdownString(todo.title ?: @"", 15) mutableCopy];
    if (todo.done) {
        [titleAtt addAttribute:NSStrikethroughStyleAttributeName value:@(NSUnderlineStyleSingle)
                         range:NSMakeRange(0, titleAtt.length)];
        [titleAtt addAttribute:NSForegroundColorAttributeName value:[UIColor secondaryLabelColor]
                         range:NSMakeRange(0, titleAtt.length)];
    } else {
        [titleAtt addAttribute:NSForegroundColorAttributeName value:[UIColor labelColor]
                         range:NSMakeRange(0, titleAtt.length)];
    }
    _titleLabel.attributedText = titleAtt;

    // 书签
    UIImage *book = [UIImage systemImageNamed:@"bookmark.fill"];
    [_bookmarkButton setImage:book forState:UIControlStateNormal];
    _bookmarkButton.tintColor = [UIColor colorWithRed:0.88 green:0.65 blue:0.18 alpha:1.0];
    _bookmarkButton.alpha = todo.isBookmarked ? 1.0 : 0.25;

    // 加号
    UIImage *plus = [UIImage systemImageNamed:@"plus.circle.fill"];
    [_plusButton setImage:plus forState:UIControlStateNormal];
    _plusButton.tintColor = [UIColor secondaryLabelColor];

    // 子任务行
    for (UIView *v in _subRows) [v removeFromSuperview];
    [_subRows removeAllObjects];
    if (todo.isSelected) {
        for (SubTaskItem *sub in todo.subTasks) {
            UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
            // 子任务行放在卡片下方（页面灰底上），不要背景，只有圈+文字
            [self.contentView addSubview:row];
            UIImageView *check = [[UIImageView alloc] initWithFrame:CGRectZero];
            check.tag = 1;
            check.contentMode = UIViewContentModeScaleAspectFit;
            [row addSubview:check];
            UILongPressGestureRecognizer *rowLongPress =
                [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                              action:@selector(subRowLongPressed:)];
            rowLongPress.minimumPressDuration = 0.35;
            rowLongPress.delegate = self;
            [row addGestureRecognizer:rowLongPress];
            // 整行点击 = 完成/取消完成
            UITapGestureRecognizer *rowTap =
                [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(subRowTapped:)];
            [rowTap requireGestureRecognizerToFail:rowLongPress];
            [row addGestureRecognizer:rowTap];
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
            label.tag = 2;
            label.font = [UIFont systemFontOfSize:13];
            label.numberOfLines = 0; // 长文字自动换行，完整显示
            label.lineBreakMode = NSLineBreakByWordWrapping;
            [row addSubview:label];
            [_subRows addObject:row];
        }
    }
}

- (void)bookmarkTapped {
    if (self.onToggleBookmark) self.onToggleBookmark();
}

- (void)plusTapped {
    if (self.onAddSubTask) self.onAddSubTask();
}

- (void)subRowTapped:(UITapGestureRecognizer *)gesture {
    UIView *row = gesture.view;
    NSUInteger idx = [_subRows indexOfObject:row];
    if (idx != NSNotFound && idx < _todo.subTasks.count) {
        if (self.onToggleSubTask) self.onToggleSubTask(_todo.subTasks[idx]);
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer == self.cardTapGesture ||
        gestureRecognizer == self.cardLongPressGesture) {
        // 卡片手势：按钮（加号/书签/勾选）和子任务行不触发
        if ([touch.view isKindOfClass:[UIControl class]]) return NO;
        for (UIView *row in _subRows) {
            if ([touch.view isDescendantOfView:row]) return NO;
        }
        return YES;
    }
    return YES; // 子任务行长按等其它手势照常接收
}

- (void)subRowLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    NSUInteger idx = [_subRows indexOfObject:gesture.view];
    if (idx != NSNotFound && idx < _todo.subTasks.count) {
        if (self.onEditSubTask) self.onEditSubTask(_todo.subTasks[idx]);
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    CGFloat timeW = 44;
    _timeLabel.frame = CGRectMake(12, (h - 18) / 2.0, timeW, 18);

    CGFloat mainH = 64;
    CGFloat cardX = 64;
    CGFloat cardW = w - cardX - 12;
    _cardView.frame = CGRectMake(cardX, 4, cardW, mainH);

    CGFloat iconSize = 34;
    _iconBg.frame = CGRectMake(12, (mainH - iconSize) / 2.0, iconSize, iconSize);
    _iconView.frame = CGRectInset(_iconBg.bounds, 8, 8);

    CGFloat rightX = cardW - 12;
    _plusButton.frame = CGRectMake(rightX - 38, (mainH - 38) / 2.0, 38, 38);
    _bookmarkButton.frame = CGRectMake(rightX - 30, mainH - 28, 24, 24);
    _titleLabel.frame = CGRectMake(56, 6, cardW - 56 - 52, mainH - 12);

    CGFloat y = 4 + mainH + 4;
    for (NSUInteger i = 0; i < _subRows.count; i++) {
        UIView *row = _subRows[i];
        UIImageView *check = (UIImageView *)[row viewWithTag:1];
        UILabel *label = [row viewWithTag:2];

        SubTaskItem *sub = (i < _todo.subTasks.count) ? _todo.subTasks[i] : nil;
        CGFloat rowW = cardW - 14;
        CGFloat labelW = rowW - 32;
        NSInteger lines = sub ? todoSubLines(sub.title, labelW) : 1;
        CGFloat rowH = MAX(34, lines * 17 + 14);
        row.frame = CGRectMake(cardX + 14, y, rowW, rowH);
        check.frame = CGRectMake(0, (rowH - 24) / 2.0, 24, 24);
        label.frame = CGRectMake(32, 4, labelW, rowH - 8);
        if (sub) {
            UIImage *img = [UIImage systemImageNamed:sub.isCompleted ? @"checkmark.circle.fill" : @"circle"];
            img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            check.image = img;
            check.tintColor = sub.isCompleted ? kAITodoAccentColor : [UIColor systemGray3Color];
            // 子任务文字（按 Markdown 渲染）
            NSMutableAttributedString *subAtt = [todoMarkdownString(sub.title ?: @"", 13) mutableCopy];
            if (sub.isCompleted) {
                [subAtt addAttribute:NSStrikethroughStyleAttributeName value:@(NSUnderlineStyleSingle)
                               range:NSMakeRange(0, subAtt.length)];
                [subAtt addAttribute:NSForegroundColorAttributeName value:[UIColor secondaryLabelColor]
                               range:NSMakeRange(0, subAtt.length)];
            } else {
                [subAtt addAttribute:NSForegroundColorAttributeName value:[UIColor labelColor]
                               range:NSMakeRange(0, subAtt.length)];
            }
            label.attributedText = subAtt;
        }
        y += rowH;
    }
}

+ (CGFloat)heightForTodo:(MainTodoItem *)todo width:(CGFloat)width {
    CGFloat mainH = 64;
    CGFloat subH = 0;
    if (todo.isSelected) {
        CGFloat cardX = 64, cardRight = 12;
        CGFloat cardW = width - cardX - cardRight;
        CGFloat labelW = cardW - 14 - 32;
        for (SubTaskItem *s in todo.subTasks) {
            NSInteger lines = todoSubLines(s.title, labelW);
            subH += MAX(34, lines * 17 + 14);
        }
    }
    return 4 + mainH + 4 + subH + 4;
}

@end
