//
//  YYTextLine.h
//  TestYYText
//
//  Created by tongleiming on 2020/9/4.
//

#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>

NS_ASSUME_NONNULL_BEGIN

// 对CTLineRef的封装
@interface YYTextLine : NSObject

+ (instancetype)lineWithCTLine:(CTLineRef)CTLine position:(CGPoint)position vertical:(BOOL)isVertical;

// 这个index就是根据CTFrame中的Line进行遍历时的index
@property (nonatomic) NSUInteger index;
@property (nonatomic) NSUInteger row;

@property (nonatomic, readonly) CTLineRef CTLine;   ///< CoreText line
// 是和当前CTLine相对应的文本的range
@property (nonatomic, readonly) NSRange range;      ///< string range
// 是否是垂直文本
@property (nonatomic, readonly) BOOL vertical;      ///< vertical form

// bounds是通过_position计算出来的，所以bounds也是UIKit的坐标系
@property (nonatomic, readonly) CGRect bounds;      ///< bounds
@property (nonatomic, readonly) CGFloat width;      ///< bounds.size.width

// baseline的position，这个position通过函数传递进来的是UIKit的坐标系
@property (nonatomic)   CGPoint position;   ///< baseline position
@property (nonatomic, readonly) CGFloat ascent;     ///< line ascent
@property (nonatomic, readonly) CGFloat descent;    ///< line descent
@property (nonatomic, readonly) CGFloat leading;    ///< line leading
@property (nonatomic, readonly) CGFloat lineWidth;  ///< line width
// 当前CTLine中尾随的空格长度
@property (nonatomic, readonly) CGFloat trailingWhitespaceWidth;

//暂时用不到attachment，所以先不看
@property (nullable, nonatomic, readonly) NSArray<YYTextAttachment *> *attachments; ///< YYTextAttachment
@property (nullable, nonatomic, readonly) NSArray<NSValue *> *attachmentRanges;     ///< NSRange(NSValue)
@property (nullable, nonatomic, readonly) NSArray<NSValue *> *attachmentRects;      ///< CGRect(NSValue)
@end

NS_ASSUME_NONNULL_END
