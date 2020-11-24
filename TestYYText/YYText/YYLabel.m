//
//  YYLabel.m
//  TestYYText
//
//  Created by tongleiming on 2020/9/4.
//

#import "YYLabel.h"
#import "YYTextAsyncLayer.h"
#import "YYTextLayout.h"

static dispatch_queue_t YYLabelGetReleaseQueue() {
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
}

// YYLabel实现了异步绘制的代理
@interface YYLabel() <YYTextAsyncLayerDelegate> {
    NSMutableAttributedString *_innerText; ///< nonnull
    YYTextLayout *_innerLayout;
    YYTextContainer *_innerContainer;
    
    NSMutableArray *_attachmentViews;
    NSMutableArray *_attachmentLayers;
    
    struct {
        unsigned int layoutNeedUpdate : 1;
        unsigned int showingHighlight : 1;
        
        unsigned int trackingTouch : 1;
        unsigned int swallowTouch : 1;
        unsigned int touchMoved : 1;
        
        unsigned int hasTapAction : 1;
        unsigned int hasLongPressAction : 1;
        
        unsigned int contentsNeedFade : 1;
    } _state;
}

@end

@implementation YYLabel

#pragma mark - Private

- (void)_setLayoutNeedUpdate {
    _state.layoutNeedUpdate = YES;
    [self _clearInnerLayout];
    [self _setLayoutNeedRedraw];
}

- (void)_setLayoutNeedRedraw {
    [self.layer setNeedsDisplay];
}

- (void)_clearInnerLayout {
#warning _innerLayout为空，暂时不用看
    if (!_innerLayout) return;
    YYTextLayout *layout = _innerLayout;
    _innerLayout = nil;
    _shrinkInnerLayout = nil;
    dispatch_async(YYLabelGetReleaseQueue(), ^{
        NSAttributedString *text = [layout text]; // capture to block and release in background
        if (layout.attachments.count) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [text length]; // capture to block and release in main thread (maybe there's UIView/CALayer attachments).
            });
        }
    });
}

- (UIFont *)_defaultFont {
    return [UIFont systemFontOfSize:17];
}

- (void)_clearContents {
    CGImageRef image = (__bridge_retained CGImageRef)(self.layer.contents);
    self.layer.contents = nil;
    if (image) {
#warning 为什么需要在指定队列中释放？
        /// 在非主线程释放，优化主线程时间
        dispatch_async(YYLabelGetReleaseQueue(), ^{
            CFRelease(image);
        });
    }
}

- (void)_initLabel {
    ((YYTextAsyncLayer *)self.layer).displaysAsynchronously = NO;
    self.layer.contentsScale = [UIScreen mainScreen].scale;
    
    // The option to redisplay the view when the bounds change by invoking the setNeedsDisplay method.
    self.contentMode = UIViewContentModeRedraw;
    
    _attachmentViews = [NSMutableArray new];
    _attachmentLayers = [NSMutableArray new];
    
#warning debugOption暂时忽略
    _debugOption = [YYTextDebugOption sharedDebugOption];
    [YYTextDebugOption addDebugTarget:self];
    
    _font = [self _defaultFont];
    _textColor = [UIColor blackColor];
    _textVerticalAlignment = YYTextVerticalAlignmentCenter;
    _numberOfLines = 1;
    _textAlignment = NSTextAlignmentNatural;
    _lineBreakMode = NSLineBreakByTruncatingTail;
    
    // 这个多关注一下
    _innerText = [NSMutableAttributedString new];
    
    _innerContainer = [YYTextContainer new];
    _innerContainer.truncationType = YYTextTruncationTypeEnd;
    _innerContainer.maximumNumberOfRows = _numberOfLines;
    _clearContentsBeforeAsynchronouslyDisplay = YES;
    _fadeOnAsynchronouslyDisplay = YES;
    _fadeOnHighlight = YES;
    
    self.isAccessibilityElement = YES;
}

+ (YYTextLayout *)_shrinkLayoutWithLayout:(YYTextLayout *)layout {
    if (layout.text.length && layout.lines.count == 0) {
    } else {
        return nil;
    }
}



#pragma mark - Override
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    [self _initLabel];
    self.frame = frame;
    return self;
}

- (void)setFrame:(CGRect)frame {
    CGSize oldSize = self.bounds.size;
    [super setFrame:frame];
    CGSize newSize = self.bounds.size;
    if (!CGSizeEqualToSize(oldSize, newSize)) {
        // 设置innterContainer的size
        _innerContainer.size = self.bounds.size;
        if (!_ignoreCommonProperties) {
            _state.layoutNeedUpdate = YES;
        }
        if (_displaysAsynchronously && _clearContentsBeforeAsynchronouslyDisplay) {
            [self _clearContents];
        }
        // 设置了layer setNeedDisplay
        [self _setLayoutNeedRedraw];
    }
}

#pragma mark - Property

- (void)setText:(NSString *)text {
    if (_text == text || [_text isEqualToString:text]) return;
    _text = text.copy;
    BOOL needAddAttributes = _innerText.length == 0 && text.length > 0;
    [_innerText replaceCharactersInRange:NSMakeRange(0, _innerText.length) withString:text ? text : @""];
    [_innerText yy_removeDiscontinuousAttributesInRange:NSMakeRange(0, _innerText.length)];
    // 设置的属性最终会关联到innerText这个attributedStr上。
    if (needAddAttributes) {
        _innerText.yy_font = _font;
        _innerText.yy_color = _textColor;
        _innerText.yy_shadow = [self _shadowFromProperties];
        _innerText.yy_alignment = _textAlignment;
        switch (_lineBreakMode) {
            case NSLineBreakByWordWrapping:
            case NSLineBreakByCharWrapping:
            case NSLineBreakByClipping: {
                _innerText.yy_lineBreakMode = _lineBreakMode;
            } break;
            case NSLineBreakByTruncatingHead:
            case NSLineBreakByTruncatingTail:
            case NSLineBreakByTruncatingMiddle: {
                _innerText.yy_lineBreakMode = NSLineBreakByWordWrapping;
            } break;
            default: break;
        }
    }
#warning 一般情况下_textParser是nil
/// 在设置文字的时候就解析了表情，保存在了attributedString中，对应的style的key设置成了"YYTextAttachmentAttributeName"；
/// 设置的attachment是自定义的YYTextAttachment，其为NSCopying，但是对于YYTextAttachment的content在复制的时候，如果
    /// content遵守NSCopying，那么就copy，否则就直接强引用。这是否会导致content为图片时的多线程操作问题?
    ///
    ///
    ///
/// 在异步绘制的时候，由于复制了attributedText，所以在后续可以拿到对应的YYTextAttachment。
/// 由于这些东西都保存进了text中，所以复制的时候也就一起复制了。
    if ([_textParser parseText:_innerText selectedRange:NULL]) {
        [self _updateOuterTextProperties];
    }
    
    if (!_ignoreCommonProperties) {
        if (_displaysAsynchronously && _clearContentsBeforeAsynchronouslyDisplay) {
            // 清理contents
            [self _clearContents];
        }
        // 内部会调用self.layer setNeedsDisplay
        [self _setLayoutNeedUpdate];
        [self _endTouch];
        [self invalidateIntrinsicContentSize];
    }
}

- (void)setDisplaysAsynchronously:(BOOL)displaysAsynchronously {
    _displaysAsynchronously = displaysAsynchronously;
    
    // 设置自己的layer的异步绘制属性
    ((YYTextAsyncLayer *)self.layer).displaysAsynchronously = displaysAsynchronously;
}

#pragma mark - YYTextAsyncLayerDelegate

- (YYTextAsyncLayerDisplayTask *)newAsyncDisplayTask {
    // 拿到了当前的一堆状态
    // capture current context
    BOOL contentsNeedFade = _state.contentsNeedFade;
    NSAttributedString *text = _innerText;
    YYTextContainer *container = _innerContainer;
    YYTextVerticalAlignment verticalAlignment = _textVerticalAlignment;
    YYTextDebugOption *debug = _debugOption;
    NSMutableArray *attachmentViews = _attachmentViews;
    NSMutableArray *attachmentLayers = _attachmentLayers;
    BOOL layoutNeedUpdate = _state.layoutNeedUpdate;
    BOOL fadeForAsync = _displaysAsynchronously && _fadeOnAsynchronouslyDisplay;
#warning 暂时为空
    __block YYTextLayout *layout = (_state.showingHighlight && _highlightLayout) ? self._highlightLayout : self._innerLayout;
    __block YYTextLayout *shrinkLayout = nil;
    __block BOOL layoutUpdated = NO;
    if (layoutNeedUpdate) {
        text = text.copy;
        container = container.copy;
    }
    
    // 创建任务
    // create display task
    YYTextAsyncLayerDisplayTask *task = [YYTextAsyncLayerDisplayTask new];
    
    // 清理一些attachment
    task.willDisplay = ^(CALayer *layer) {
        [layer removeAnimationForKey:@"contents"];
        
        // If the attachment is not in new layout, or we don't know the new layout currently,
        // the attachment should be removed.
        for (UIView *view in attachmentViews) {
            if (layoutNeedUpdate || ![layout.attachmentContentsSet containsObject:view]) {
                if (view.superview == self) {
                    [view removeFromSuperview];
                }
            }
        }
        for (CALayer *layer in attachmentLayers) {
            if (layoutNeedUpdate || ![layout.attachmentContentsSet containsObject:layer]) {
                if (layer.superlayer == self.layer) {
                    [layer removeFromSuperlayer];
                }
            }
        }
        [attachmentViews removeAllObjects];
        [attachmentLayers removeAllObjects];
    };
    
    task.display = ^(CGContextRef context, CGSize size, BOOL (^isCancelled)(void)) {
        if (isCancelled()) return;
        if (text.length == 0) return;
        
        YYTextLayout *drawLayout = layout;
        if (layoutNeedUpdate) {
            // 重新创建了一个layout，text(NSAttributedString)也是在内部进行了拷贝，防止多线程操作。
            // 相关的attachment是又重新解析出来的，独立保存在layout.attachments中。
            layout = [YYTextLayout layoutWithContainer:container text:text];
            // shrinkLayout一般为nil
            shrinkLayout = [YYLabel _shrinkLayoutWithLayout:layout];
            if (isCancelled()) return;
            layoutUpdated = YES;
            drawLayout = shrinkLayout ? shrinkLayout : layout;
        }
        
        CGSize boundingSize = drawLayout.textBoundingSize;
        CGPoint point = CGPointZero;
        if (verticalAlignment == YYTextVerticalAlignmentCenter) {
            if (drawLayout.container.isVerticalForm) {
                point.x = -(size.width - boundingSize.width) * 0.5;
            } else {
                // 一般会进入到这里
                // size为layer的bounds的size；
                // boundingSize为文字的包围size；
                // 这里是计算文字部分在layer内部的point位置有多少？
                point.y = (size.height - boundingSize.height) * 0.5;
            }
        } else if (verticalAlignment == YYTextVerticalAlignmentBottom) {
            if (drawLayout.container.isVerticalForm) {
                point.x = -(size.width - boundingSize.width);
            } else {
                point.y = (size.height - boundingSize.height);
            }
        }
        // 像素对齐部分，我们也需要像素对齐的修正
        point = YYTextCGPointPixelRound(point);
        [drawLayout drawInContext:context size:size point:point view:nil layer:nil debug:debug cancel:isCancelled];
    };
    
    task.didDisplay = ^(CALayer * _Nonnull layer, BOOL finished) {
        YYTextLayout *drawLayout = layout;
        if (layoutUpdated && shrinkLayout) {
            drawLayout = shrinkLayout;
        }
        if (!finished) {
            // If the display task is cancelled, we should clear the attachments.
            for (YYTextAttachment *a in drawLayout.attachments) {
                if ([a.content isKindOfClass:[UIView class]]) {
                    if (((UIView *)a.content).superview == layer.delegate) {
                        [((UIView *)a.content) removeFromSuperview];
                    }
                } else if ([a.content isKindOfClass:[CALayer class]]) {
                    if (((CALayer *)a.content).superlayer == layer) {
                        [((CALayer *)a.content) removeFromSuperlayer];
                    }
                }
            }
            return;
        }
        [layer removeAnimationForKey:@"contents"];
        
        __strong YYLabel *view = (YYLabel *)layer.delegate;
        if (!view) return;
        if (view->_state.layoutNeedUpdate && layoutUpdated) {
            view->_innerLayout = layout;
            view->_shrinkInnerLayout = shrinkLayout;
            view->_state.layoutNeedUpdate = NO;
        }
        
        CGSize size = layer.bounds.size;
        CGSize boundingSize = drawLayout.textBoundingSize;
        CGPoint point = CGPointZero;
        if (verticalAlignment == YYTextVerticalAlignmentCenter) {
            if (drawLayout.container.isVerticalForm) {
#warning todo
            } else {
                point.y = (size.height - boundingSize.height) * 0.5;
            }
        } else {
#warning todo
        }
        // 像素对齐
        point = YYTextCGPointPixelRound(point);
        [drawLayout drawInContext:nil size:size point:point view:view layer:layer debug:nil cancel:NULL];
        for (YYTextAttachment *a in drawLayout.attachments) {
            if ([a.content isKindOfClass:[UIView class]]) [attachmentViews addObject:a.content];
            else if ([a.content isKindOfClass:[CALayer class]]) [attachmentLayers addObject:a.content];
        }
        
        if (contentsNeedFade) {
            CATransition *transition = [CATransition animation];
            transition.duration = kHighlightFadeDuration;
            transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            transition.type = kCATransitionFade;
            [layer addAnimation:transition forKey:@"contents"];
        } else if (fadeForAsync) {
            CATransition *transition = [CATransition animation];
            transition.duration = kAsyncFadeDuration;
            transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            transition.type = kCATransitionFade;
            [layer addAnimation:transition forKey:@"contents"];
        }
    };
}

@end
