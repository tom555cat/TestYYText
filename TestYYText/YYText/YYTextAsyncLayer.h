//
//  YYTextAsyncLayer.h
//  TestYYText
//
//  Created by tongleiming on 2020/9/4.
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@class YYTextAsyncLayerDisplayTask;

NS_ASSUME_NONNULL_BEGIN


/// YYTextAsyncLayer是一个用来异步渲染的CALayer子类。
/// 当layer需要更新其内容时，layer询问(其)代理来获取一个异步展示任务，异步展示任务在后台展示内容。
@interface YYTextAsyncLayer : CALayer
/// Whether the render code is executed in background. Default is YES.
/// 渲染代码是否在后台线程执行，默认为YES
@property BOOL displaysAsynchronously;
@end

/**
 The YYTextAsyncLayer's delegate protocol. The delegate of the YYTextAsyncLayer (typically a UIView)
 must implements the method in this protocol.
 */
// YYTextAsyncLayer的代理必须遵守的协议
@protocol YYTextAsyncLayerDelegate <NSObject>
@required
/// This method is called to return a new display task when the layer's contents need update.
/// 在layer的content需要更新的时候，该方法返回一个display task
- (YYTextAsyncLayerDisplayTask *)newAsyncDisplayTask;
@end

/**
 A display task used by YYTextAsyncLayer to render the contents in background queue.
 */
/// 一个display task，当YYTextAsyncLayer使用这个task去异步渲染其content
@interface YYTextAsyncLayerDisplayTask : NSObject


/**
 This block will be called before the asynchronous drawing begins.
 It will be called on the main thread.
 
 block param layer: The layer.
 */
/// prehook，在主线程上调用，需要自己手动控制在主线程
@property (nullable, nonatomic, copy) void (^willDisplay)(CALayer *layer);

/**
 This block is called to draw the layer's contents.
 
 @discussion This block may be called on main thread or background thread,
 so is should be thread-safe.
 
 block param context:      A new bitmap content created by layer.
 block param size:         The content size (typically same as layer's bound size).
 block param isCancelled:  If this block returns `YES`, the method should cancel the
 drawing process and return as quickly as possible.
 */
/// 绘制的回调，该回调可以在主线程/非主线程调用，需要保证线程安全。
@property (nullable, nonatomic, copy) void (^display)(CGContextRef context, CGSize size, BOOL(^isCancelled)(void));

/**
 This block will be called after the asynchronous drawing finished.
 It will be called on the main thread.
 
 block param layer:  The layer.
 block param finished:  If the draw process is cancelled, it's `NO`, otherwise it's `YES`;
 */
/// afterhook，在主线程上调用
@property (nullable, nonatomic, copy) void (^didDisplay)(CALayer *layer, BOOL finished);

@end

NS_ASSUME_NONNULL_END
