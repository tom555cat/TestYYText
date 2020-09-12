//
//  YYTextLine.m
//  TestYYText
//
//  Created by tongleiming on 2020/9/4.
//

#import "YYTextLine.h"

@implementation YYTextLine {
    // baseline第一个glyph的position，是x轴，一般是0
    CGFloat _firstGlyphPos;
}

+ (instancetype)lineWithCTLine:(CTLineRef)CTLine position:(CGPoint)position vertical:(BOOL)isVertical {
    if (!CTLine) return nil;
    YYTextLine *line = [self new];
    line->_position = position;
    line->_vertical = isVertical;
    [line setCTLine:CTLine];
    return line;
}

- (void)setCTLine:(_Nonnull CTLineRef)CTLine {
    if (_CTLine != CTLine) {
        if (CTLine) CFRetain(CTLine);
        if (_CTLine) CFRelease(_CTLine);
        _CTLine = CTLine;
        if (_CTLine) {
            _lineWidth = CTLineGetTypographicBounds(_CTLine, &_ascent, &_descent, &_leading);
            CFRange range = CTLineGetStringRange(_CTLine);
            _range = NSMakeRange(range.location, range.length);
            // glyph是字形的意思，CTLineGetGlyphCount就是获取CTLine中有多少个字
            if (CTLineGetGlyphCount(_CTLine) > 0) {
                /// 获取当前CTLine的position，和frame没有多少关系
                CFArrayRef runs = CTLineGetGlyphRuns(_CTLine);
                CTRunRef run = CFArrayGetValueAtIndex(runs, 0);
                CGPoint pos;
                CTRunGetPositions(run, CFRangeMake(0, 1), &pos);
                _firstGlyphPos = pos.x;
            } else {
                _firstGlyphPos = 0;
            }
            // 获取该行尾随的空格长度
            _trailingWhitespaceWidth = CTLineGetTrailingWhitespaceWidth(_CTLine);
        } else {
            _lineWidth = _ascent = _descent = _leading = _firstGlyphPos = _trailingWhitespaceWidth = 0;
            _range = NSMakeRange(0, 0);
        }
        // 重新计算bounds属性
        [self reloadBounds];
    }
}

- (void)reloadBounds {
    if (_vertical) {
        _bounds = CGRectMake(_position.x - _descent, _position.y, _ascent + _descent, _lineWidth);
    } else {
        // 正常的布局是走这里
        _bounds = CGRectMake(_position.x, _position.y - _ascent, _lineWidth, _ascent + _descent);
        _bounds.origin.x += _firstGlyphPos;
    }
    
    _attachments = nil;
    _attachmentRanges = nil;
    _attachmentRects = nil;
    if (!_CTLine) return;
    CFArrayRef runs = CTLineGetGlyphRuns(_CTLine);
    NSUInteger runCount = CFArrayGetCount(runs);
    if (runCount == 0) return;
    
    NSMutableArray *attachments = [NSMutableArray new];
    NSMutableArray *attachmentRanges = [NSMutableArray new];
    NSMutableArray *attachmentRects = [NSMutableArray new];
    for (NSUInteger r = 0; r < runCount; r++) {
        CTRunRef run = CFArrayGetValueAtIndex(runs, r);
        // 获取CTRun中的字符
        CFIndex glyphCount = CTRunGetGlyphCount(run);
        if (glyphCount == 0) continue;
        NSDictionary *attrs = (id)CTRunGetAttributes(run);
        YYTextAttachment *attachment = attrs[YYTextAttachmentAttributeName];
        if (attachment) {
#warning TODO, 表情图片是否也可以通过attachment来解析，避免消耗太多时间
        }
    }
    
    _attachments = attachments.count ? attachments : nil;
    _attachmentRanges = attachmentRanges.count ? attachmentRanges : nil;
    _attachmentRects = attachmentRects.count ? attachmentRects : nil;
}

- (CGFloat)width {
    return CGRectGetWidth(_bounds);
}

@end
