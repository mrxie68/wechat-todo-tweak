#import "CustomTodoTableViewCell.h"
#import "AIConfig.h"

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
    return [UIColor colorWithRed:0.68 green:0.53 blue:0.40 alpha:1.0]; // 棕色
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
        ? [UIColor colorWithRed:0.92 green:0.85 blue:0.72 alpha:1.0]
        : [UIColor colorWithRed:0.84 green:0.77 blue:0.95 alpha:1.0];
    _iconView.tintColor = todo.isSelected
        ? [UIColor whiteColor]
        : [UIColor colorWithRed:0.45 green:0.34 blue:0.72 alpha:1.0];

    // 标题
    if (todo.done) {
        _titleLabel.attributedText =
            [[NSAttributedString alloc] initWithString:todo.title ?: @""
                                            attributes:@{
                                                NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle),
                                                NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
                                            }];
    } else {
        _titleLabel.attributedText = nil;
        _titleLabel.text = todo.title;
        _titleLabel.textColor = todo.isSelected ? [UIColor whiteColor] : [UIColor labelColor];
    }

    // 书签
    UIImage *book = [UIImage systemImageNamed:@"bookmark.fill"];
    [_bookmarkButton setImage:book forState:UIControlStateNormal];
    _bookmarkButton.tintColor = [UIColor colorWithRed:0.88 green:0.65 blue:0.18 alpha:1.0];
    _bookmarkButton.alpha = todo.isBookmarked ? 1.0 : 0.25;

    // 加号
    UIImage *plus = [UIImage systemImageNamed:@"plus.circle.fill"];
    [_plusButton setImage:plus forState:UIControlStateNormal];
    _plusButton.tintColor = todo.isSelected ? [UIColor whiteColor] : [UIColor secondaryLabelColor];

    // 子任务行
    for (UIView *v in _subRows) [v removeFromSuperview];
    [_subRows removeAllObjects];
    if (todo.isSelected) {
        for (SubTaskItem *sub in todo.subTasks) {
            UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
            [self.cardView addSubview:row];
            UIButton *check = [UIButton buttonWithType:UIButtonTypeSystem];
            check.tag = 1;
            [check addTarget:self action:@selector(subCheckTapped:) forControlEvents:UIControlEventTouchUpInside];
            [row addSubview:check];
            UILongPressGestureRecognizer *rowLongPress =
                [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                              action:@selector(subRowLongPressed:)];
            rowLongPress.minimumPressDuration = 0.35;
            rowLongPress.delegate = self;
            [row addGestureRecognizer:rowLongPress];
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
            label.tag = 2;
            label.font = [UIFont systemFontOfSize:13];
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

- (void)subCheckTapped:(UIButton *)sender {
    UIView *row = sender.superview;
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

    CGFloat cardX = 64;
    CGFloat cardW = w - cardX - 12;
    _cardView.frame = CGRectMake(cardX, 4, cardW, h - 8);

    CGFloat mainH = 64;
    CGFloat iconSize = 34;
    _iconBg.frame = CGRectMake(12, (mainH - iconSize) / 2.0, iconSize, iconSize);
    _iconView.frame = CGRectInset(_iconBg.bounds, 8, 8);

    CGFloat rightX = cardW - 12;
    _plusButton.frame = CGRectMake(rightX - 38, (mainH - 38) / 2.0, 38, 38);
    _bookmarkButton.frame = CGRectMake(rightX - 30, mainH - 28, 24, 24);
    _titleLabel.frame = CGRectMake(56, 6, cardW - 56 - 52, mainH - 12);

    CGFloat y = mainH;
    for (NSUInteger i = 0; i < _subRows.count; i++) {
        UIView *row = _subRows[i];
        row.frame = CGRectMake(0, y, cardW, 34);
        UIButton *check = [row viewWithTag:1];
        UILabel *label = [row viewWithTag:2];
        check.frame = CGRectMake(14, 6, 24, 24);
        label.frame = CGRectMake(44, 0, cardW - 44 - 34, 34);

        SubTaskItem *sub = (i < _todo.subTasks.count) ? _todo.subTasks[i] : nil;
        if (sub) {
            UIImage *img = [UIImage systemImageNamed:sub.isCompleted ? @"checkmark.circle.fill" : @"circle"];
            img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            [check setImage:img forState:UIControlStateNormal];
            check.tintColor = sub.isCompleted ? kAITodoAccentColor
                                              : (_todo.isSelected ? [UIColor whiteColor] : [UIColor systemGray3Color]);
            if (sub.isCompleted) {
                label.attributedText =
                    [[NSAttributedString alloc] initWithString:sub.title ?: @""
                                                    attributes:@{
                                                        NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle),
                                                        NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
                                                    }];
            } else {
                label.attributedText = nil;
                label.text = sub.title;
                label.textColor = _todo.isSelected ? [UIColor whiteColor] : [UIColor labelColor];
            }
        }
        y += 34;
    }
}

+ (CGFloat)heightForTodo:(MainTodoItem *)todo width:(CGFloat)width {
    CGFloat mainH = 64;
    CGFloat subH = todo.isSelected ? todo.subTasks.count * 34.0 : 0;
    return mainH + subH + 8;
}

@end
