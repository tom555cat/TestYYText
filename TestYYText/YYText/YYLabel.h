//
//  YYLabel.h
//  TestYYText
//
//  Created by tongleiming on 2020/9/4.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface YYLabel : UIView

// 设置该属性会替换`attributedText`中的text，获取的时候
// 返回的是`attributedText`中的plain text。
@property (nullable, nonatomic, copy) NSString *text;

// 默认17系统字体。
// 设置该属性，同时会给全局的`attributedText`设置字体。
@property (null_resettable, nonatomic, strong) UIFont *font;
// 设置该属性，同时会给全局的`attributedText`设置字体颜色。
@property (null_resettable, nonatomic, strong) UIColor *textColor;

/**
 A Boolean value indicating whether the layout and rendering codes are running
 asynchronously on background threads.
 
 The default value is `NO`.
 */
// 布局和渲染代码是否异步地执行在后台线程中，默认为NO
@property (nonatomic) BOOL displaysAsynchronously;

// 如果值为YES，那么layer是异步渲染时，在display之前，会设置label.layer.contents为nil。
// 如果不清理的话，如果卡，那么旧的内容仍然会显示。
@property (nonatomic) BOOL clearContentsBeforeAsynchronouslyDisplay;

// 异步渲染时，当内容发生变化时加一个fade动画
@property (nonatomic) BOOL fadeOnAsynchronouslyDisplay;

// 加一个高亮动画
@property (nonatomic) BOOL fadeOnHighlight;

// 忽略通用属性(比如text,font,textColor,attributedText,...)，只
// 使用textLayout来展示内容。
// 默认值为NO。
// 如果你"只"通过"textLayout"来控制label内容，你可以设置该值为YES来获取更高的性能。
@property (nonatomic) BOOL ignoreCommonProperties;

@end

NS_ASSUME_NONNULL_END
