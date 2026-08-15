#import "TodoTableViewCell.h"
#import "AIConfig.h"

@implementation TodoTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor systemBackgroundColor];
        self.selectionStyle = UITableViewCellSelectionStyleDefault;

        _checkButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_checkButton addTarget:self
                         action:@selector(checkTapped)
               forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_checkButton];

        _contentLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _contentLabel.numberOfLines = 2;
        _contentLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _contentLabel.font = [UIFont systemFontOfSize:17];
        [self.contentView addSubview:_contentLabel];

        _metaLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _metaLabel.font = [UIFont systemFontOfSize:12];
        _metaLabel.textColor = [UIColor secondaryLabelColor];
        [self.contentView addSubview:_metaLabel];
    }
    return self;
}

- (void)checkTapped {
    if (self.onToggle) self.onToggle();
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.contentView.bounds.size.height;
    CGFloat w = self.contentView.bounds.size.width;
    _checkButton.frame = CGRectMake(4, (h - 44) / 2.0, 44, 44);
    CGFloat x = 56;
    _metaLabel.frame = CGRectMake(x, h - 26, w - x - 14, 18);
    _contentLabel.frame = CGRectMake(x, 10, w - x - 14, MAX(20, _metaLabel.frame.origin.y - 18));
}

- (void)setDone:(BOOL)done important:(BOOL)important overdue:(BOOL)overdue
        content:(NSString *)content meta:(NSString *)meta {
    UIImage *img = [UIImage systemImageNamed:done ? @"checkmark.circle.fill" : @"circle"];
    if (!img) img = [UIImage systemImageNamed:done ? @"checkmark.circle" : @"circle"];
    img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [_checkButton setImage:img forState:UIControlStateNormal];
    _checkButton.tintColor = done ? kAITodoAccentColor : [UIColor systemGray3Color];

    if (done) {
        _contentLabel.attributedText =
            [[NSAttributedString alloc] initWithString:content ?: @""
                                            attributes:@{NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle)}];
        _contentLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        _contentLabel.attributedText = nil;
        _contentLabel.text = content;
        _contentLabel.textColor = [UIColor labelColor];
    }
    _metaLabel.text = meta;
    _metaLabel.textColor = overdue ? [UIColor systemRedColor] : [UIColor secondaryLabelColor];
}

@end
