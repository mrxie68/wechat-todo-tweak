#import "TodoMarkdown.h"

static UIFont *todoFontWithTraits(UIFont *base, BOOL bold, BOOL italic) {
    UIFontDescriptorSymbolicTraits traits = 0;
    if (bold) traits |= UIFontDescriptorTraitBold;
    if (italic) traits |= UIFontDescriptorTraitItalic;
    UIFontDescriptor *desc = [base.fontDescriptor fontDescriptorWithSymbolicTraits:traits];
    return desc ? [UIFont fontWithDescriptor:desc size:base.pointSize] : base;
}

static NSAttributedString *todoStyled(NSString *text, UIFont *font,
                                      BOOL bold, BOOL italic, BOOL strike, BOOL code) {
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:text];
    UIFont *f = code ? [UIFont fontWithName:@"Menlo" size:font.pointSize - 1] : font;
    if (bold || italic) f = todoFontWithTraits(f, bold, italic);
    [a addAttribute:NSFontAttributeName value:f range:NSMakeRange(0, a.length)];
    if (strike) {
        [a addAttribute:NSStrikethroughStyleAttributeName value:@(NSUnderlineStyleSingle)
                  range:NSMakeRange(0, a.length)];
    }
    if (code) {
        [a addAttribute:NSBackgroundColorAttributeName
                  value:[UIColor systemGray6Color] range:NSMakeRange(0, a.length)];
    }
    return a;
}

// 行内解析 ** * ` ~~
static NSAttributedString *todoInline(NSString *line, UIFont *baseFont) {
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    NSArray *dels = @[@"**", @"~~", @"`", @"*"];
    NSMutableString *buf = [NSMutableString string];
    BOOL bold = NO, italic = NO, strike = NO, code = NO;
    NSInteger len = line.length;
    NSInteger i = 0;
    while (i < len) {
        BOOL matched = NO;
        for (NSString *d in dels) {
            if (code && ![d isEqualToString:@"`"]) continue; // 代码段内只认反引号
            if (i + d.length <= len &&
                [[line substringWithRange:NSMakeRange(i, d.length)] isEqualToString:d]) {
                if (buf.length > 0) {
                    [out appendAttributedString:todoStyled(buf, baseFont, bold, italic, strike, code)];
                    [buf setString:@""];
                }
                if ([d isEqualToString:@"**"]) bold = !bold;
                else if ([d isEqualToString:@"*"]) italic = !italic;
                else if ([d isEqualToString:@"`"]) code = !code;
                else strike = !strike;
                i += d.length;
                matched = YES;
                break;
            }
        }
        if (!matched) {
            [buf appendString:[line substringWithRange:NSMakeRange(i, 1)]];
            i++;
        }
    }
    if (buf.length > 0) {
        [out appendAttributedString:todoStyled(buf, baseFont, bold, italic, strike, code)];
    }
    return out;
}

NSAttributedString *todoMarkdownString(NSString *raw, CGFloat baseSize) {
    if (raw.length == 0) return [[NSAttributedString alloc] initWithString:@""];
    UIFont *base = [UIFont systemFontOfSize:baseSize];
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSArray *lines = [raw componentsSeparatedByString:@"\n"];
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineSpacing = 3;

    for (NSUInteger li = 0; li < lines.count; li++) {
        NSString *line = lines[li];
        NSString *stripped = line;
        NSString *prefix = @"";
        UIFont *lineFont = base;
        if ([line hasPrefix:@"### "]) {
            stripped = [line substringFromIndex:4];
            lineFont = [UIFont boldSystemFontOfSize:baseSize + 1];
        } else if ([line hasPrefix:@"## "]) {
            stripped = [line substringFromIndex:3];
            lineFont = [UIFont boldSystemFontOfSize:baseSize + 2];
        } else if ([line hasPrefix:@"# "]) {
            stripped = [line substringFromIndex:2];
            lineFont = [UIFont boldSystemFontOfSize:baseSize + 3];
        } else if ([line hasPrefix:@"- [x] "]) {
            stripped = [line substringFromIndex:6];
            prefix = @"☑ ";
        } else if ([line hasPrefix:@"- [ ] "]) {
            stripped = [line substringFromIndex:6];
            prefix = @"☐ ";
        } else if ([line hasPrefix:@"- "]) {
            stripped = [line substringFromIndex:2];
            prefix = @"• ";
        } else if ([line hasPrefix:@"* "]) {
            stripped = [line substringFromIndex:2];
            prefix = @"• ";
        }

        NSAttributedString *inlineAtt = todoInline(stripped, lineFont);
        NSMutableAttributedString *lineAtt = [[NSMutableAttributedString alloc] init];
        if (prefix.length > 0) {
            [lineAtt appendAttributedString:
                [[NSAttributedString alloc] initWithString:prefix
                                                attributes:@{NSFontAttributeName: lineFont}]];
        }
        [lineAtt appendAttributedString:inlineAtt];
        [lineAtt addAttribute:NSParagraphStyleAttributeName value:para
                        range:NSMakeRange(0, lineAtt.length)];
        [result appendAttributedString:lineAtt];
        if (li < lines.count - 1) {
            [result appendAttributedString:
                [[NSAttributedString alloc] initWithString:@"\n"
                                                attributes:@{NSParagraphStyleAttributeName: para}]];
        }
    }
    return result;
}
