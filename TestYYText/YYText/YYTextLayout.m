//
//  YYTextLayout.m
//  TestYYText
//
//  Created by tongleiming on 2020/9/4.
//

#import "YYTextLayout.h"
#import "YYTextLine.h"

const CGSize YYTextContainerMaxSize = (CGSize){0x100000, 0x100000};

typedef struct {
    CGFloat head;
    CGFloat foot;
} YYRowEdge;

@implementation YYTextContainer {
    @package
    BOOL _readonly; ///< used only in YYTextLayout.implementation
    dispatch_semaphore_t _lock;
    
    CGSize _size;
    UIBezierPath *_path;
    BOOL _pathFillEvenOdd;
    // 就是判断是不是垂直的文本
    BOOL _verticalForm;
    NSUInteger _maximumNumberOfRows;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _lock = dispatch_semaphore_create(1);
    _pathFillEvenOdd = YES;
    return self;
}

#warning 保证线程安全的宏

#define Getter(...) \
dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER); \
__VA_ARGS__; \
dispatch_semaphore_signal(_lock);

#define Setter(...) \
if (_readonly) { \
@throw [NSException exceptionWithName:NSInternalInconsistencyException \
reason:@"Cannot change the property of the 'container' in 'YYTextLayout'." userInfo:nil]; \
return; \
} \
dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER); \
__VA_ARGS__; \
dispatch_semaphore_signal(_lock);

- (CGSize)size {
    Getter(CGSize size = _size) return size;
}

- (void)setSize:(CGSize)size {
    Setter(if(!_path) _size = YYTextClipCGSize(size));
}

- (UIBezierPath *)path {
    Getter(UIBezierPath *path = _path) return path;
}

- (void)setPath:(UIBezierPath *)path {
    Setter(
           _path = path.copy;
           if (_path) {
               CGRect bounds = _path.bounds;
               CGSize size = bounds.size;
               UIEdgeInsets insets = UIEdgeInsetsZero;
               if (bounds.origin.x < 0) size.width += bounds.origin.x;
               if (bounds.origin.x > 0) insets.left = bounds.origin.x;
               if (bounds.origin.y < 0) size.height += bounds.origin.y;
               if (bounds.origin.y > 0) insets.top = bounds.origin.y;
               _size = size;
               _insets = insets;
           }
    );
}

- (BOOL)isVerticalForm {
    Getter(BOOL v = _verticalForm) return v;
}

- (void)setVerticalForm:(BOOL)verticalForm {
    Setter(_verticalForm = verticalForm);
}

// 预处理的结果是：
//- (NSUInteger)maximumNumberOfRows {
//    dispatch_semaphore_wait(_lock, (~0ull)); NSUInteger num = _maximumNumberOfRows; dispatch_semaphore_signal(_lock); return num;
//}
//
//- (void)setMaximumNumberOfRows:(NSUInteger)maximumNumberOfRows {
//    if (_readonly) { @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Cannot change the property of the 'container' in 'YYTextLayout'." userInfo:((void *)0)]; return; } dispatch_semaphore_wait(_lock, (~0ull)); _maximumNumberOfRows = maximumNumberOfRows; dispatch_semaphore_signal(_lock);;
//}

- (NSUInteger)maximumNumberOfRows {
    Getter(NSUInteger num = _maximumNumberOfRows) return num;
}

- (void)setMaximumNumberOfRows:(NSUInteger)maximumNumberOfRows {
    Setter(_maximumNumberOfRows = maximumNumberOfRows);
}

- (void)setLinePositionModifier:(id<YYTextLinePositionModifier>)linePositionModifier {
    Setter(_linePositionModifier = [(NSObject *)linePositionModifier copy]);
}

- (id<YYTextLinePositionModifier>)linePositionModifier {
    Getter(id<YYTextLinePositionModifier> m = _linePositionModifier) return m;
}

#undef Getter
#undef Setter

@end

@interface YYTextLayout ()

@property (nonatomic, readwrite) YYTextContainer *container;
@property (nonatomic, readwrite) NSAttributedString *text;
@property (nonatomic, readwrite) NSRange range;

@property (nonatomic, readwrite) BOOL needDrawText;

@end

@implementation YYTextLayout

- (instancetype)_init {
    self = [super init];
    return self;
}

+ (YYTextLayout *)layoutWithContainer:(YYTextContainer *)container text:(NSAttributedString *)text {
    return [self layoutWithContainer:container text:text range:NSMakeRange(0, text.length)];
}

+ (YYTextLayout *)layoutWithContainer:(YYTextContainer *)container text:(NSAttributedString *)text range:(NSRange)range {
    YYTextLayout *layout = NULL;
    CGPathRef cgPath = nil;
    CGRect cgPathBox = {0};
    BOOL isVerticalForm = NO;
    BOOL rowMaySeparated = NO;
    NSMutableDictionary *frameAttrs = nil;
    CTFramesetterRef ctSetter = NULL;
    CTFrameRef ctFrame = NULL;
    CFArrayRef ctLines = nil;
    CGPoint *lineOrigins = NULL;
    NSUInteger lineCount = 0;
    NSMutableArray *lines = nil;
    NSMutableArray *attachments = nil;
    NSMutableArray *attachmentRanges = nil;
    NSMutableArray *attachmentRects = nil;
    NSMutableSet *attachmentContentsSet = nil;
    BOOL needTruncation = NO;
    NSAttributedString *truncationToken = nil;
    // 最后一行被截断之后重新绘制的行
    YYTextLine *truncatedLine = nil;
    YYRowEdge *lineRowsEdge = NULL;
    NSUInteger *lineRowsIndex = NULL;
    NSRange visibleRange;
    NSUInteger maximumNumberOfRows = 0;
    BOOL constraintSizeIsExtended = NO;
    CGRect constraintRectBeforeExtended = {0};
    
    text = text.mutableCopy;
    container = container.copy;
    if (!text || !container) return nil;
    if (range.location + range.length > text.length) return nil;
    // 设置为只读之后，如何后续再写，那么会抛异常
    container->_readonly = YES;
    maximumNumberOfRows = container.maximumNumberOfRows;
    
    // CoreText bug when draw joined emoji since iOS 8.3.
    // See -[NSMutableAttributedString setClearColorToJoinedEmoji] for more information.
    static BOOL needFixJoinedEmojiBug = NO;
    // It may use larger constraint size when create CTFrame with
    // CTFramesetterCreateFrame in iOS 10.
    static BOOL needFixLayoutSizeBug = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        double systemVersionDouble = [UIDevice currentDevice].systemVersion.doubleValue;
        if (8.3 <= systemVersionDouble && systemVersionDouble < 9) {
            needFixJoinedEmojiBug = YES;
        }
        if (systemVersionDouble >= 10) {
            needFixLayoutSizeBug = YES;
        }
    });
#warning 这是个什么bug?
    if (needFixJoinedEmojiBug) {
        [((NSMutableAttributedString *)text) yy_setClearColorToJoinedEmoji];
    }
    
    layout = [[YYTextLayout alloc] _init];
    layout.text = text;
    layout.container = container;
    layout.range = range;
    isVerticalForm = container.verticalForm;
    
    // set cgPath and cgPathBox
    if (container.path == nil && container.exclusionPaths.count == 0) {
        if (container.size.width <= 0 || container.size.height <= 0) goto fail;
        // rect以container的size为基础
        CGRect rect = (CGRect) {CGPointZero, container.size };
        if (needFixLayoutSizeBug) {
            constraintSizeIsExtended = YES;
            // 根据insets，在rect的基础上得到内部的rect
            constraintRectBeforeExtended = UIEdgeInsetsInsetRect(rect, container.insets);
            constraintRectBeforeExtended = CGRectStandardize(constraintRectBeforeExtended);
            if (container.isVerticalForm) {
#warning 这是个什么bug?
#warning 不太确定？？为什么要这样设置
                rect.size.width = YYTextContainerMaxSize.width;
            } else {
                rect.size.height = YYTextContainerMaxSize.height;
            }
        }
        rect = UIEdgeInsetsInsetRect(rect, container.insets);
        rect = CGRectStandardize(rect);
        cgPathBox = rect;
        // 进行上下翻转，，，后续ctFrame使用到的rect就是从这里计算出来的★★★★★★★★★★★★★★
        rect = CGRectApplyAffineTransform(rect, CGAffineTransformMakeScale(1, -1));
        cgPath = CGPathCreateWithRect(rect, NULL); // let CGPathIsRect() returns true
    } else if (container.path && CGPathIsRect(container.path.CGPath, &cgPathBox) && container.exclusionPaths.count == 0) {   // 定义path先不考虑
        CGRect rect = CGRectApplyAffineTransform(cgPathBox, CGAffineTransformMakeScale(1, -1));
        cgPath = CGPathCreateWithRect(rect, NULL); // let CGPathIsRect() returns true
    } else {
        // 这里也暂时先不考虑
    }
    if (!cgPath) goto fail;
    
    // 暂时跳过，没有执行
    // frame setter config
    frameAttrs = [NSMutableDictionary dictionary];
    if (container.isPathFillEvenOdd == NO) {
        frameAttrs[(id)kCTFramePathFillRuleAttributeName] = @(kCTFramePathFillWindingNumber);
    }
    if (container.pathLineWidth > 0) {
        frameAttrs[(id)kCTFramePathWidthAttributeName] = @(container.pathLineWidth);
    }
    if (container.isVerticalForm == YES) {
        frameAttrs[(id)kCTFrameProgressionAttributeName] = @(kCTFrameProgressionRightToLeft);
    }
    
    // create CoreText objects
    ctSetter = CTFramesetterCreateWithAttributedString((CFTypeRef)text);
    if (!ctSetter) goto fail;
    
    // 创建ctFrame
    ctFrame = CTFramesetterCreateFrame(ctSetter, YYTextCFRangeFromNSRange(range), cgPath, (CFTypeRef)frameAttrs);
    if (!ctFrame) goto fail;
    
    lines = [NSMutableArray new];
    ctLines = CTFrameGetLines(ctFrame);
    lineCount = CFArrayGetCount(ctLines);
    if (lineCount > 0) {
        lineOrigins = malloc(lineCount * sizeof(CGPoint));
        if (lineOrigins == NULL) goto fail;
        CTFrameGetLineOrigins(ctFrame, CFRangeMake(0, lineCount), lineOrigins);
    }
    
    // textBoundingRect就是所有文本行的rect
    CGRect textBoundingRect = CGRectZero;
    // textBoundingSize是包住textBoundingRect的size
    CGSize textBoundingSize = CGSizeZero;
    NSInteger rowIdx = -1;
    // rowCount是根据提供的rect(考虑进了insets)之后实际能绘制的行数
    NSUInteger rowCount = 0;
    // 默认不是vertical的
    CGRect lastRect = CGRectMake(0, -FLT_MAX, 0, 0);
    CGPoint lastPosition = CGPointMake(0, -FLT_MAX);
    if (isVerticalForm) {
        lastRect = CGRectMake(FLT_MAX, 0, 0, 0);
        lastPosition = CGPointMake(FLT_MAX, 0);
    }
    
    // calculate line frame
    NSUInteger lineCurrentIdx = 0;
    for (NSUInteger i = 0; i < lineCount; i++) {
        CTLineRef ctLine = CFArrayGetValueAtIndex(ctLines, i);
        // 获取每行中的ctruns
        CFArrayRef ctRuns = CTLineGetGlyphRuns(ctLine);
        // 没有ctruns就直接下一行
        if (!ctRuns || CFArrayGetCount(ctRuns) == 0) continue;
        
        // CoreText coordinate system
        // 获取origin
        CGPoint ctLineOrigin = lineOrigins[i];
        
        // UIKit coordinate system
        // cgPathBox是UIKit的坐标系，所以计算出来的position是UIKit的坐标系
        CGPoint position;
        position.x = cgPathBox.origin.x + ctLineOrigin.x;
        position.y = cgPathBox.size.height + cgPathBox.origin.y - ctLineOrigin.y;
        
        YYTextLine *line = [YYTextLine lineWithCTLine:ctLine position:position vertical:isVerticalForm];
        CGRect rect = line.bounds;
        
        if (constraintSizeIsExtended) {   // 修正bug时此变量为YES
            if (isVerticalForm) {
                if (rect.origin.x + rect.size.width >
                    constraintRectBeforeExtended.origin.x +
                    constraintRectBeforeExtended.size.width) break;
            } else {
                // 正常是走下边，也就是说如果当前CTLine的origin.y偏移再加上rect.size.height超过了你当初限制的rect大小，那么就结束
                if (rect.origin.y + rect.size.height > constraintRectBeforeExtended.origin.y + constraintRectBeforeExtended.size.height) break;
            }
        }
        
        BOOL newRow = YES;
        if (rowMaySeparated && position.x != lastPosition.x) {
#warning 暂时走不到了里
            if (isVerticalForm) {
                if (rect.size.width > lastRect.size.width) {
                    if (rect.origin.x > lastPosition.x && lastPosition.x > rect.origin.x - rect.size.width) newRow = NO;
                } else {
                    if (lastRect.origin.x > position.x && position.x > lastRect.origin.x - lastRect.size.width) newRow = NO;
                }
            } else {
                if (rect.size.height > lastRect.size.height) {
                    if (rect.origin.y < lastPosition.y && lastPosition.y < rect.origin.y + rect.size.height) newRow = NO;
                } else {
                    if (lastRect.origin.y < position.y && position.y < lastRect.origin.y + lastRect.size.height) newRow = NO;
                }
            }
        }
        
        if (newRow) rowIdx++;
        // lastRect保存的是当前行的rect
        lastRect = rect;
        lastPosition = position;
        
        line.index = lineCurrentIdx;
        line.row = rowIdx;
        [lines addObject:line];
        rowCount = rowIdx + 1;
        lineCurrentIdx ++;
        
        if (i == 0) textBoundingRect = rect;
        else {
            // maximumNumberOfRows是我自己指定的
            if (maximumNumberOfRows == 0 || rowIdx < maximumNumberOfRows) {
                // 不断地将新的行的rect融合进textBoundingRect中
                textBoundingRect = CGRectUnion(textBoundingRect, rect);
            }
        }
    }
    
    // rowCount是根据提供的rect(考虑进了insets)之后实际能绘制的行数
    if (rowCount > 0) {
        // 1. 根据自己设定的maximumNumberOfRows决定是否需要截断
        if (maximumNumberOfRows > 0) {
            if (rowCount > maximumNumberOfRows) {
                // 实际行数超过了最大限制行数，需要进行截断
                needTruncation = YES;
                rowCount = maximumNumberOfRows;
                do {
                    YYTextLine *line = lines.lastObject;
                    if (!line) break;
                    // 要绘制rowCount行，少了就停止移除
                    if (line.row < rowCount) break;
                    [lines removeLastObject];
                } while (1);
            }
        }
        // 2. 根据文字是否显示完整决定是否要进行截断
        YYTextLine *lastLine = lines.lastObject;
        if (!needTruncation && lastLine.range.location + lastLine.range.length < text.length) {
            needTruncation = YES;
        }
        
        // 给用户提供一个修改line的position的机会
        if (container.linePositionModifier) {
            // container.linePositionModifier是个代理
            [container.linePositionModifier modifyLines:lines fromText:text inContainer:container];
            textBoundingRect = CGRectZero;
            for (NSUInteger i = 0, max = lines.count; i < max; i++) {
                YYTextLine *line = lines[i];
                if (i == 0) textBoundingRect = line.bounds;
                else textBoundingRect = CGRectUnion(textBoundingRect, line.bounds);
            }
        }
        
        // 记录每一行的高度边界
        lineRowsEdge = calloc(rowCount, sizeof(YYRowEdge));
        if (lineRowsEdge == NULL) goto fail;
        lineRowsIndex = calloc(rowCount, sizeof(NSUInteger));
        if (lineRowsIndex == NULL) goto fail;
        NSInteger lastRowIdx = -1;
        CGFloat lastHead = 0;
        CGFloat lastFoot = 0;
        for (NSUInteger i = 0, max = lines.count; i < max; i++) {
            YYTextLine *line = lines[i];
            CGRect rect = line.bounds;
            if ((NSInteger)line.row != lastRowIdx) {
                // 第一次lastRowIdx为-1，不会执行
                if (lastRowIdx >= 0) {
                    lineRowsEdge[lastRowIdx] = (YYRowEdge) {.head = lastHead, .foot = lastFoot };
                }
                lastRowIdx = line.row;
                // 构建row和rowIndex的关联
                lineRowsIndex[lastRowIdx] = i;
                if (isVerticalForm) {
                    lastHead = rect.origin.x + rect.size.width;
                    lastFoot = lastHead - rect.size.width;
                } else {
                    lastHead = rect.origin.y;
                    lastFoot = lastHead + rect.size.height;
                }
            } else {
#warning 暂时没有走到这里
                if (isVerticalForm) {
                    lastHead = MAX(lastHead, rect.origin.x + rect.size.width);
                    lastFoot = MIN(lastFoot, rect.origin.x);
                } else {
                    lastHead = MIN(lastHead, rect.origin.y);
                    lastFoot = MAX(lastFoot, rect.origin.y + rect.size.height);
                }
            }
        }
        // 记录最后一行的起始和结束高度
        lineRowsEdge[lastRowIdx] = (YYRowEdge) {.head = lastHead, .foot = lastFoot };
        
        for (NSUInteger i = 1; i < rowCount; i++) {
            // 上一行的边界
            YYRowEdge v0 = lineRowsEdge[i - 1];
            // 当前行的边界
            YYRowEdge v1 = lineRowsEdge[i];
            // 上一行的下边界和当前行的上边界中和一下
            lineRowsEdge[i - 1].foot = lineRowsEdge[i].head = (v0.foot + v1.head) * 0.5;
        }
    }
    
    {
        //
        CGRect rect = textBoundingRect;
        if (container.path) {
            if (container.pathLineWidth > 0) {
                CGFloat inset = container.pathLineWidth / 2;
                rect = CGRectInset(rect, -inset, -inset);
            }
        } else {
            rect = UIEdgeInsetsInsetRect(rect,YYTextUIEdgeInsetsInvert(container.insets));
        }
        rect = CGRectStandardize(rect);
        
        // 一般情况下，经过上述步骤rect不会发生变化。
        // 计算size，
        CGSize size = rect.size;
        if (container.verticalForm) {
            size.width += container.size.width - (rect.origin.x + rect.size.width);
        } else {
            size.width += rect.origin.x;
        }
        size.height += rect.origin.y;
        if (size.width < 0) size.width = 0;
        if (size.height < 0) size.height = 0;
        // 有取整的步骤出现！！！！！！！！！！！！！！
        size.width = ceil(size.width);
        size.height = ceil(size.height);
        textBoundingSize = size;
    }
    
    visibleRange = YYTextNSRangeFromCFRange(CTFrameGetVisibleStringRange(ctFrame));
    if (needTruncation) {
        YYTextLine *lastLine = lines.lastObject;
        NSRange lastRange = lastLine.range;
        // 调整可见区的长度，visibleRange.location为0
        visibleRange.length = lastRange.location + lastRange.length - visibleRange.location;
        
        // 创建截断行。根据截断类型创建截断行
        if (container.truncationType != YYTextTruncationTypeNone) {
            CTLineRef truncationTokenLine = NULL;
            if (container.truncationToken) {
#warning 一般不走这里
                truncationToken = container.truncationToken;
                truncationTokenLine = CTLineCreateWithAttributedString((CFAttributedStringRef)truncationToken);
            } else {
                CFArrayRef runs = CTLineGetGlyphRuns(lastLine.CTLine);
                NSUInteger runCount = CFArrayGetCount(runs);
                NSMutableDictionary *attrs = nil;
                if (runCount > 0) {
                    CTRunRef run = CFArrayGetValueAtIndex(runs, runCount - 1);
                    attrs = (id)CTRunGetAttributes(run);
                    attrs = attrs ? attrs.mutableCopy : [NSMutableArray new];
                    // 移除不连续的属性
                    [attrs removeObjectsForKeys:[NSMutableAttributedString yy_allDiscontinuousAttributeKeys]];
#warning 对字体进行了处理，为什么要这样处理？
                    CTFontRef font = (__bridge CFTypeRef)attrs[(id)kCTFontAttributeName];
                    CGFloat fontSize = font ? CTFontGetSize(font) : 12.0;
                    UIFont *uiFont = [UIFont systemFontOfSize:fontSize * 0.9];
                    if (uiFont) {
                        font = CTFontCreateWithName((__bridge CFStringRef)uiFont.fontName, uiFont.pointSize, NULL);
                    } else {
                        font = NULL;
                    }
                    if (font) {
                        attrs[(id)kCTFontAttributeName] = (__bridge id)(font);
                        uiFont = nil;
                        CFRelease(font);
                    }
#warning 对字体颜色做了额外的处理
                    CGColorRef color = (__bridge CGColorRef)(attrs[(id)kCTForegroundColorAttributeName]);
                    if (color && CFGetTypeID(color) == CGColorGetTypeID() && CGColorGetAlpha(color) == 0) {
                        // ignore clear color
                        [attrs removeObjectForKey:(id)kCTForegroundColorAttributeName];
                    }
                    if (!attrs) attrs = [NSMutableDictionary new];
                }
                // 创建显示截断内容的字符串
                truncationToken = [[NSAttributedString alloc] initWithString:YYTextTruncationToken attributes:attrs];
                // 从attributedStr中创建CTLine
                truncationTokenLine = CTLineCreateWithAttributedString((CFAttributedStringRef)truncationToken);
            }
            if (truncationTokenLine) {
                // 默认设置一个尾截断
                CTLineTruncationType type = kCTLineTruncationEnd;
                if (container.truncationType == YYTextTruncationTypeStart) {
                    type = kCTLineTruncationStart;
                } else if (container.truncationType == YYTextTruncationTypeMiddle) {
                    type = kCTLineTruncationMiddle;
                }
                NSMutableAttributedString *lastLineText = [text attributedSubstringFromRange:lastLine.range].mutableCopy;
                [lastLineText appendAttributedString:truncationToken];
                CTLineRef ctLastLineExtend = CTLineCreateWithAttributedString((CFAttributedStringRef)lastLineText);
                if (ctLastLineExtend) {
                    CGFloat truncatedWidth = lastLine.width;
                    CGRect cgPathRect = CGRectZero;
                    // 将cgPath转换为rect
                    if (CGPathIsRect(cgPath, &cgPathRect)) {
                        if (isVerticalForm) {
                            truncatedWidth = cgPathRect.size.height;
                        } else {
                            truncatedWidth = cgPathRect.size.width;
                        }
                    }
                    // 根据line创建一个truncated line。
                    // ctLastLineExtend是已经加入truncateToken的attributedStr创建的line
                    // truncationTokenLine是truncateToken创建的line
                    // truncatedWidth是截断宽度，超过的话就会被截断
                    CTLineRef ctTruncatedLine = CTLineCreateTruncatedLine(ctLastLineExtend, truncatedWidth, type, truncationTokenLine);
                    CFRelease(ctLastLineExtend);
                    if (ctTruncatedLine) {
                        truncatedLine = [YYTextLine lineWithCTLine:ctTruncatedLine position:lastLine.position vertical:isVerticalForm];
                        truncatedLine.index = lastLine.index;
                        truncatedLine.row = lastLine.row;
                        CFRelease(ctTruncatedLine);
                    }
                }
                CFRelease(truncationTokenLine);
            }
        }
    }
    
    if (isVerticalForm) {
#warning 暂时不用管
    }
    
    if (visibleRange.length > 0) {
        layout.needDrawText = YES;
        
#warning 绘制更细节内容的东西，暂时不看
        void (^block)(NSDictionary *attrs, NSRange range, BOOL *stop) = ^(NSDictionary *attrs, NSRange range, BOOL *stop) {
            if (attrs[YYTextHighlightAttributeName]) layout.containsHighlight = YES;
            if (attrs[YYTextBlockBorderAttributeName]) layout.needDrawBlockBorder = YES;
            if (attrs[YYTextBackgroundBorderAttributeName]) layout.needDrawBackgroundBorder = YES;
            if (attrs[YYTextShadowAttributeName] || attrs[NSShadowAttributeName]) layout.needDrawShadow = YES;
            if (attrs[YYTextUnderlineAttributeName]) layout.needDrawUnderline = YES;
            if (attrs[YYTextAttachmentAttributeName]) layout.needDrawAttachment = YES;
            if (attrs[YYTextInnerShadowAttributeName]) layout.needDrawInnerShadow = YES;
            if (attrs[YYTextStrikethroughAttributeName]) layout.needDrawStrikethrough = YES;
            if (attrs[YYTextBorderAttributeName]) layout.needDrawBorder = YES;
        };
        
        [layout.text enumerateAttributesInRange:visibleRange options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired usingBlock:block];
        if (truncatedLine) {
            [truncationToken enumerateAttributesInRange:NSMakeRange(0, truncationToken.length) options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired usingBlock:block];
        }
    }
    
#warning 暂时没有attachments
    attachments = [NSMutableArray new];
    attachmentRanges = [NSMutableArray new];
    attachmentRects = [NSMutableArray new];
    attachmentContentsSet = [NSMutableSet new];
    for (NSUInteger i = 0, max = lines.count; i < max; i++) {
        YYTextLine *line = lines[i];
        if (truncatedLine && line.index == truncatedLine.index) line = truncatedLine;
        if (line.attachments.count > 0) {
            [attachments addObjectsFromArray:line.attachments];
            [attachmentRanges addObjectsFromArray:line.attachmentRanges];
            [attachmentRects addObjectsFromArray:line.attachmentRects];
            for (YYTextAttachment *attachment in line.attachments) {
                if (attachment.content) {
                    [attachmentContentsSet addObject:attachment.content];
                }
            }
        }
    }
    if (attachments.count == 0) {
        attachments = attachmentRanges = attachmentRects = nil;
    }
    
    layout.frameSetter = ctSetter;
    layout.frame = ctFrame;
    layout.lines = lines;
    layout.truncatedLine = truncatedLine;
    layout.attachments = attachments;
    layout.attachmentRanges = attachmentRanges;
    layout.attachmentRects = attachmentRects;
    layout.attachmentContentsSet = attachmentContentsSet;
    layout.rowCount = rowCount;
    layout.visibleRange = visibleRange;
    layout.textBoundingRect = textBoundingRect;
    layout.textBoundingSize = textBoundingSize;
    layout.lineRowsEdge = lineRowsEdge;
    layout.lineRowsIndex = lineRowsIndex;
    CFRelease(cgPath);
    CFRelease(ctSetter);
    CFRelease(ctFrame);
    if (lineOrigins) free(lineOrigins);
    return layout;
    
fail:
    if (cgPath) CFRelease(cgPath);
    if (ctSetter) CFRelease(ctSetter);
    if (ctFrame) CFRelease(ctFrame);
    if (lineOrigins) free(lineOrigins);
    if (lineRowsEdge) free(lineRowsEdge);
    if (lineRowsIndex) free(lineRowsIndex);
    return nil;
}

static void YYTextDrawRun(YYTextLine *line, CTRunRef run, CGContextRef context, CGSize size, BOOL isVertical, NSArray *runRanges, CGFloat verticalOffset) {
 
    // ......
    CTRunDraw(run, context, CFRangeMake(0, 0));
    // ......
}

// 这是一个静态方法，绘制什么没有关系
static void YYTextDrawText(YYTextLayout *layout, CGContextRef context, CGSize size, CGPoint point, BOOL (^cancel)(void)) {
    CGContextSaveGState(context); {
        
        CGContextTranslateCTM(context, point.x, point.y);
        CGContextTranslateCTM(context, 0, size.height);
        CGContextScaleCTM(context, 1, -1);
        
        BOOL isVertical = layout.container.verticalForm;
        CGFloat verticalOffset = isVertical ? (size.width - layout.container.size.width) : 0;
        
        NSArray *lines = layout.lines;
        for (NSUInteger l = 0, lMax = lines.count; l < lMax; l++) {
            YYTextLine *line = lines[l];
            if (layout.truncatedLine && layout.truncatedLine.index == line.index) line = layout.truncatedLine;
            NSArray *lineRunRanges = line.verticalRotateRange;
            CGFloat posX = line.position.x + verticalOffset;
            CGFloat posY = size.height - line.position.y;
            CFArrayRef runs = CTLineGetGlyphRuns(line.CTLine);
            for (NSUInteger r = 0, rMax = CFArrayGetCount(runs); r < rMax; r++) {
                CTRunRef run = CFArrayGetValueAtIndex(runs, r);
                CGContextSetTextMatrix(context, CGAffineTransformIdentity);
                CGContextSetTextPosition(context, posX, posY);
                YYTextDrawRun(line, run, context, size, isVertical, lineRunRanges[r], verticalOffset);
            }
            if (cancel && cancel()) break;
        }
        
        // Use this to draw frame for test/debug.
        // CGContextTranslateCTM(context, verticalOffset, size.height);
        // CTFrameDraw(layout.frame, context);
        
    } CGContextRestoreGState(context);
}

- (void)drawInContext:(CGContextRef)context
                 size:(CGSize)size
                point:(CGPoint)point
                 view:(UIView *)view
                layer:(CALayer *)layer
                debug:(YYTextDebugOption *)debug
                cancel:(BOOL (^)(void))cancel{
    @autoreleasepool {
#warning 为什么在这里就需要加上autoreleasepool?
        // .....
        if (self.needDrawText && context) {
            if (cancel && cancel()) return;
            YYTextDrawText(self, context, size, point, cancel);
        }
        // .....
    }
}

@end
