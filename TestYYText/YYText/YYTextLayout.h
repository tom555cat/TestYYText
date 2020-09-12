//
//  YYTextLayout.h
//  TestYYText
//
//  Created by tongleiming on 2020/9/4.
//

#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#import "YYTextLine.h"

NS_ASSUME_NONNULL_BEGIN

// YYTextContainer定义了文字布局的一块区域。
// YYTextLayout使用一个或多个YYTextContainer对象去生成布局。

// YYTextContainer定义矩形区域(`size`和`insets`)，或非矩形shapes(`path`)；
// 你能够在text container的bunding rectangle中定义exclusion paths，来使
// 文字在布局时围绕在exclusion path周围。

// 该类的所有方法都是线程安全的。

/*
 
Example:

    ┌─────────────────────────────┐  <------- container
    │                             │
    │    asdfasdfasdfasdfasdfa   <------------ container insets
    │    asdfasdfa   asdfasdfa    │
    │    asdfas         asdasd    │
    │    asdfa        <----------------------- container exclusion path
    │    asdfas         adfasd    │
    │    asdfasdfa   asdfasdfa    │
    │    asdfasdfasdfasdfasdfa    │
    │                             │
    └─────────────────────────────┘
*/
 
@interface YYTextContainer : NSObject <NSCoding, NSCopying>

/// The constrained size. (if the size is larger than YYTextContainerMaxSize, it will be clipped)
@property CGSize size;

/// The insets for constrained size. The inset value should not be negative. Default is UIEdgeInsetsZero.
@property UIEdgeInsets insets;

/// Custom constrained path. Set this property to ignore `size` and `insets`. Default is nil.
// 如果定义了path，就会忽略size和insets，默认为空
@property (nullable, copy) UIBezierPath *path;

/// An array of `UIBezierPath` for path exclusion. Default is nil.
@property (nullable, copy) NSArray<UIBezierPath *> *exclusionPaths;

/// Whether the text is vertical form (may used for CJK text layout). Default is NO.
@property (getter=isVerticalForm) BOOL verticalForm;

/// Maximum number of rows, 0 means no limit. Default is 0.
// 最大行，0表示无限制，默认为0
@property NSUInteger maximumNumberOfRows;
/// The line truncation type, default is none.
@property YYTextTruncationType truncationType;

/// The truncation token. If nil, the layout will use "…" instead. Default is nil.
@property (nullable, copy) NSAttributedString *truncationToken;

/// This modifier is applied to the lines before the layout is completed,
/// give you a chance to modify the line position. Default is nil.
/// 给你自己修改line position的一个机会
@property (nullable, copy) id<YYTextLinePositionModifier> linePositionModifier;

@end

// YYTextLinePositionModifier协议声明了一个必须实现的方法，
// 在text layout过程中修改line的position.
@protocol YYTextLinePositionModifier <NSObject, NSCopying>
@required

// 在布局完成之前调用，这个方法应该是线程安全的。
// lines：YYTextLine的数组
// text：全文本
// container：layout container
- (void)modifyLines:(NSArray<YYTextLine *> *)lines fromText:(NSAttributedString *)text inContainer:(YYTextContainer *)container;

@end

@interface YYTextLayout : NSObject

+ (YYTextLayout *)layoutWithContainer:(YYTextContainer *)container text:(NSAttributedString *)text;

///< The full text
/// 全部文本
@property (nonatomic, strong, readonly) NSAttributedString *text;

//// textBoundingRect就是所有文本行的rect
//CGRect textBoundingRect = CGRectZero;
//// textBoundingSize是包住textBoundingRect的size
//CGSize textBoundingSize = CGSizeZero;
@property (nonatomic, readonly) CGSize textBoundingSize;

// size是layer的size;
// point是绘制起始位置
- (void)drawInContext:(nullable CGContextRef)context
                 size:(CGSize)size
                point:(CGPoint)point
                 view:(nullable UIView *)view
                layer:(nullable CALayer *)layer
                debug:(nullable YYTextDebugOption *)debug
               cancel:(nullable BOOL (^)(void))cancel;

@end

NS_ASSUME_NONNULL_END
