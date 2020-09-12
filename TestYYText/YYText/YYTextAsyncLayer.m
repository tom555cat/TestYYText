//
//  YYTextAsyncLayer.m
//  TestYYText
//
//  Created by tongleiming on 2020/9/4.
//

#import "YYTextAsyncLayer.h"
#import <libkern/OSAtomic.h>

/// 自己创建队列，自己维护队列，从自己维护的队列数组中选择下一个队列，负载均衡？
/// 防止开辟太多的队列？
/// Global display queue, used for content rendering.
static dispatch_queue_t YYTextAsyncLayerGetDisplayQueue() {
#define MAX_QUEUE_COUNT 16
    static int queueCount;
    static dispatch_queue_t queues[MAX_QUEUE_COUNT];
    static dispatch_once_t onceToken;
    static int32_t counter = 0;
    dispatch_once(&onceToken, ^{
        queueCount = (int)[NSProcessInfo processInfo].activeProcessorCount;
        queueCount = queueCount < 1 ? 1 : queueCount > MAX_QUEUE_COUNT ? MAX_QUEUE_COUNT : queueCount;
        if ([UIDevice currentDevice].systemVersion.floatValue >= 8.0) {
            for (NSUInteger i = 0; i < queueCount; i++) {
                dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
                queues[i] = dispatch_queue_create("com.ibireme.text.render", attr);
            }
        } else {
            for (NSUInteger i = 0; i < queueCount; i++) {
                queues[i] = dispatch_queue_create("com.ibireme.text.render", DISPATCH_QUEUE_SERIAL);
                dispatch_set_target_queue(queues[i], dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
            }
        }
    });
    uint32_t cur = (uint32_t)OSAtomicIncrement32(&counter);
    return queues[(cur) % queueCount];
#undef MAX_QUEUE_COUNT
}

static dispatch_queue_t YYTextAsyncLayerGetReleaseQueue() {
#ifdef YYDispatchQueuePool_h
    return YYDispatchQueueGetForQOS(NSQualityOfServiceDefault);
#else
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
#endif
}

/// 一个线程安全的引用计算???
/// a thread safe incrementing counter.
@interface _YYTextSentinel : NSObject
/// Returns the current value of the counter.
@property (atomic, readonly) int32_t value;
/// Increase the value atomically. @return The new value.
- (int32_t)increase;
@end

@implementation _YYTextSentinel {
    int32_t _value;
}
- (int32_t)value {
    return _value;
}
- (int32_t)increase {
    // 线程安全地递增
    return OSAtomicIncrement32(&_value);
}
@end

@implementation YYTextAsyncLayerDisplayTask
@end

@implementation YYTextAsyncLayer {
    _YYTextSentinel *_sentinel;   // 中文名字是哨兵
}

- (instancetype)init {
    self = [super init];
    static CGFloat scale; //global
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        scale = [UIScreen mainScreen].scale;
    });
    self.contentsScale = scale;
    _sentinel = [_YYTextSentinel new];
    _displaysAsynchronously = YES;
    return self;
}

- (void)dealloc {
#warning 在dealloc中为什么要increase??????
    [_sentinel increase];
}

// 不要主动调用这个方法。layer会在合适的时候调用这个方法去更新layer的content。
// 如果layer有delegate，这个方法会尝试调用delegate的"displayLayer:"方法，
// 代理通过实现"displayLayer:"方法更新layer的contents。
// 如果代理不实现"displayLayer:"方法，这个方法会创建一个backing store，并且调用layer的drawInContext:方法会用content去填充backing store，新的backing store回去替换layer之前的content。
// 子类能够重写这个方法，能够使用它去设置layer的contents属性。你想要与众不同地更新layer时可以重写这个方法。
- (void)display {
    super.contents = super.contents;
    [self _displayAsync:_displaysAsynchronously];
}


#pragma mark - Private

- (void)_displayAsync:(BOOL)async {
    __strong id<YYTextAsyncLayerDelegate> delegate = (id)self.delegate;
    YYTextAsyncLayerDisplayTask *task = [delegate newAsyncDisplayTask];
    if (!task.display) {
        ///// 此时还是在主线程中！！！
        // 执行pre
        if (task.willDisplay) task.willDisplay(self);
        self.contents = nil;
        // 执行after
        if (task.didDisplay) task.didDisplay(self, YES);
        return;
    }
    
    if (async) {
        // 执行pre
        if (task.willDisplay) task.willDisplay(self);
#warning ???   哨兵和取消有关联？？？ 姑且直观地理解为是否取消
        _YYTextSentinel *sentinel = _sentinel;
        int32_t value = sentinel.value;
        BOOL (^isCancelled)() = ^BOOL() {
            return value != sentinel.value;
        };
        CGSize size = self.bounds.size;
        BOOL opaque = self.opaque;
        CGFloat scale = self.contentsScale;
        CGColorRef backgroundColor = (opaque && self.backgroundColor) ? CGColorRetain(self.backgroundColor) : NULL;
#warning 暂时忽略边界情况
        if (size.width < 1 || size.height < 1) {
            CGImageRef image = (__bridge_retained CGImageRef)(self.contents);
            self.contents = nil;
            if (image) {
                // 在非主线程上CGRelease
                dispatch_async(YYTextAsyncLayerGetReleaseQueue(), ^{
                    CFRelease(image);
                });
            }
            if (task.didDisplay) task.didDisplay(self, YES);
            CGColorRelease(backgroundColor);
            return;
        }
        
        // 异步就是体现在使用自己创建的队列上进行绘制
        dispatch_async(YYTextAsyncLayerGetDisplayQueue(), ^{
            if (isCancelled()) {
                CGColorRelease(backgroundColor);
                return;
            }
            
            // 创建了一个适用于图形操作的上下文
            UIGraphicsBeginImageContextWithOptions(size, opaque, scale);
            // 获得当前的图形上下文
            CGContextRef context = UIGraphicsGetCurrentContext();
            // 绘制背景色
            if (opaque && context) {
                CGContextSaveGState(context); {
                    if (!backgroundColor || CGColorGetAlpha(backgroundColor) < 1) {
                        CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
                        CGContextAddRect(context, CGRectMake(0, 0, size.width * scale, size.height * scale));
                        CGContextFillPath(context);
                    }
                    if (backgroundColor) {
                        CGContextSetFillColorWithColor(context, backgroundColor);
                        CGContextAddRect(context, CGRectMake(0, 0, size.width * scale, size.height * scale));
                        CGContextFillPath(context);
                    }
                } CGContextRestoreGState(context);
                CGColorRelease(backgroundColor);
            }
            // 执行代理提供的异步绘制任务
            task.display(context, size, isCancelled);
            if (isCancelled()) {
                // 如果取消，则关闭图形上下文
                UIGraphicsEndImageContext();
                // 在主线程上调用afterhook
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (task.didDisplay) task.didDisplay(self, NO);
                });
                return;
            }
            // 从当前上下文中获取一个UIImage对象
            UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
            // 关闭图形上下文
            UIGraphicsEndImageContext();
            if (isCancelled()) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (task.didDisplay) task.didDisplay(self, NO);
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (isCancelled()) {
                    if (task.didDisplay) task.didDisplay(self, NO);
                } else {
                    // ★★★★★★★★★★★在主线程中将image设置给layer的contents上。★★★★
                    self.contents = (__bridge id)(image.CGImage);
                    if (task.didDisplay) task.didDisplay(self, YES);
                }
            });
        });
    } else {
        
        [_sentinel increase];
        if (task.willDisplay) task.willDisplay(self);
        
        // 创建了一个适用于图形操作的上下文
        UIGraphicsBeginImageContextWithOptions(self.bounds.size, self.opaque, self.contentsScale);
        // 获得当前的图形上下文
        CGContextRef context = UIGraphicsGetCurrentContext();
        // 绘制背景色
        if (self.opaque && context) {
            CGSize size = self.bounds.size;
            size.width *= self.contentsScale;
            size.height *= self.contentsScale;
            CGContextSaveGState(context); {
                if (!self.backgroundColor || CGColorGetAlpha(self.backgroundColor) < 1) {
                    CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
                    CGContextAddRect(context, CGRectMake(0, 0, size.width, size.height));
                    CGContextFillPath(context);
                }
                if (self.backgroundColor) {
                    CGContextSetFillColorWithColor(context, self.backgroundColor);
                    CGContextAddRect(context, CGRectMake(0, 0, size.width, size.height));
                    CGContextFillPath(context);
                }
            } CGContextRestoreGState(context);
        }
        task.display(context, self.bounds.size, ^{return NO;});
        // 从当前上下文中获取一个UIImage对象
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        // 关闭图形上下文
        UIGraphicsEndImageContext();
        self.contents = (__bridge id)(image.CGImage);
        // 直接调用，没有使用自己创建的队列
        if (task.didDisplay) task.didDisplay(self, YES);
    }
}

@end
