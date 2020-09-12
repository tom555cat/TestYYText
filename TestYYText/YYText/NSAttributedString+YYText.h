//
//  NSAttributedString+YYText.h
//  TestYYText
//
//  Created by tongleiming on 2020/9/6.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSAttributedString (YYText)

/**
 Returns all discontinuous attribute keys, such as RunDelegate/Attachment/Ruby.
 
 @discussion These attributes can only set to a specified range of text, and
 should not extend to other range when editing text.
 */
// 所有不连续的属性，只能存在于指定的range中，不能扩展到其他range中。
+ (NSArray<NSString *> *)yy_allDiscontinuousAttributeKeys;

@end

NS_ASSUME_NONNULL_END
