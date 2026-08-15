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
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
            return trait.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor systemGray5Color]
                : [UIColor colorWithRed:0.85 green:0.78 blue:0.95 alpha:1.0]; // 稍深浅紫
        }];
    }
    return [UIColor colorWithRed:0.85 green:0.78 blue:0.95 alpha:1.0];
}

// 估算子任务文字行数
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

        // 时间：卡片内左上（两行布局的第一行）
        _timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _timeLabel.font = [UIFont systemFontOfSize:12];
        _timeLabel.textColor = [UIColor secondaryLabelColor];

        _cardView = [[UIView alloc] initWithFrame:CGRectZero];
        _cardView.layer.cornerRadius = 14;
        _cardView.clipsToBounds = YES;
        [self.contentView addSubview:_cardView];
        [self.cardView addSubview:_timeLabel];

        // 金色书签条（薄条，收藏时显示，不改变卡片高度）
        _bookmarkStrip = [[UIView alloc] initWithFrame:CGRectZero];
        _bookmarkStrip.backgroundColor = [UIColor colorWithRed:0.88 green:0.65 blue:0.18 alpha:1.0];
        [self.cardView addSubview:_bookmarkStrip];

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
    _bookmarkStrip.hidden = !todo.isBookmarked; // 收藏时顶部一条金

    // 图标
    _iconBg.backgroundColor = todo.isSelected
        ? [UIColor colorWithRed:0.78 green:0.68 blue:0.94 alpha:1.0]
        : [UIColor colorWithRed:0.84 green:0.77 blue:0.95 alpha:1.0];
    _iconView.tintColor = todo.done
        ? [UIColor systemGray3Color]
        : (todo.isSelected
           ? [UIColor colorWithRed:0.42 green:0.30 blue:0.72 alpha:1.0]
           : [UIColor colorWithRed:0.45 green:0.34 blue:0.72 alpha:1.0]);

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
        _titleLabel.textColor = [UIColor labelColor];
    }

    // 加号
    UIImage *plus = [UIImage systemImageNamed:@"plus.circle.fill"];
    [_plusButton setImage:plus forState:UIControlStateNormal];
    _plusButton.tintColor = [UIColor secondaryLabelColor];

    // 子任务行（卡片下方，页面灰底，只有圈+文字）
    for (UIView *v in _subRows) [v removeFromSuperview];
    [_subRows removeAllObjects];
    if (todo.isSelected) {
        if (todo.subTasks.count == 0) {
            // 空子任务提示行：点它添加子任务
            UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
            [self.contentView addSubview:row];
            UIImageView *check = [[UIImageView alloc] initWithFrame:CGRectZero];
            check.tag = 1;
            check.contentMode = UIViewContentModeScaleAspectFit;
            [row addSubview:check];
            UITapGestureRecognizer *rowTap =
                [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(subRowTapped:)];
            [row addGestureRecognizer:rowTap];
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
            label.tag = 2;
            label.font = [UIFont systemFontOfSize:13];
            label.textColor = [UIColor secondaryLabelColor];
            [row addSubview:label];
            [_subRows addObject:row];
        }
        for (SubTaskItem *sub in todo.subTasks) {
            UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
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
            UITapGestureRecognizer *rowTap =
                [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(subRowTapped:)];
            [rowTap requireGestureRecognizerToFail:rowLongPress];
            [row addGestureRecognizer:rowTap];
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
            label.tag = 2;
            label.font = [UIFont systemFontOfSize:13];
            label.numberOfLines = 0;
            label.lineBreakMode = NSLineBreakByWordWrapping;
            [row addSubview:label];
            [_subRows addObject:row];
        }
    }
}

- (void)plusTapped {
    if (self.onAddSubTask) self.onAddSubTask();
}

- (void)subRowTapped:(UITapGestureRecognizer *)gesture {
    NSUInteger idx = [_subRows indexOfObject:gesture.view];
    if (idx != NSNotFound && idx < _todo.subTasks.count) {
        if (self.onToggleSubTask) self.onToggleSubTask(_todo.subTasks[idx]);
    } else if (idx != NSNotFound) {
        if (self.onAddSubTask) self.onAddSubTask(); // 空子任务提示行
    }
}

- (void)subRowLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    NSUInteger idx = [_subRows indexOfObject:gesture.view];
    if (idx != NSNotFound && idx < _todo.subTasks.count) {
        if (self.onEditSubTask) self.onEditSubTask(_todo.subTasks[idx]);
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer == self.cardTapGesture ||
        gestureRecognizer == self.cardLongPressGesture) {
        if ([touch.view isKindOfClass:[UIControl class]]) return NO;
        for (UIView *row in _subRows) {
            if ([touch.view isDescendantOfView:row]) return NO;
        }
        return YES;
    }
    return YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat timeH = 20;
    CGFloat mainY = 26;
    CGFloat mainH = 58;
    CGFloat cardX = 16;
    CGFloat cardW = w - cardX - 16;

    _cardView.frame = CGRectMake(cardX, 4, cardW, timeH + mainH);
    _bookmarkStrip.frame = CGRectMake(0, 0, cardW, 4);
    _timeLabel.frame = CGRectMake(12, 6, 120, 16);

    CGFloat iconSize = 34;
    _iconBg.frame = CGRectMake(12, mainY + (mainH - iconSize) / 2.0, iconSize, iconSize);
    _iconView.frame = CGRectInset(_iconBg.bounds, 8, 8);
    _plusButton.frame = CGRectMake(cardW - 12 - 38, mainY + (mainH - 38) / 2.0, 38, 38);
    _titleLabel.frame = CGRectMake(56, mainY + 4, cardW - 56 - 60, mainH - 8);

    CGFloat y = 4 + timeH + mainH + 4;
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
                label.textColor = [UIColor labelColor];
            }
        } else {
            // 空子任务提示行
            check.hidden = YES;
            label.text = @"＋ 添加子任务";
            label.textColor = [UIColor secondaryLabelColor];
        }
        y += rowH;
    }
}

+ (CGFloat)heightForTodo:(MainTodoItem *)todo width:(CGFloat)width {
    CGFloat subH = 0;
    if (todo.isSelected) {
        CGFloat cardX = 16, cardRight = 16; // 与 layoutSubviews 保持一致
        CGFloat cardW = width - cardX - cardRight;
        CGFloat labelW = cardW - 14 - 32;
        if (todo.subTasks.count == 0) {
            subH += 34; // 空子任务提示行
        } else {
            for (SubTaskItem *s in todo.subTasks) {
                NSInteger lines = todoSubLines(s.title, labelW);
                subH += MAX(34, lines * 17 + 14);
            }
        }
    }
    return 4 + 20 + 58 + 4 + subH + 4;
}

@end
