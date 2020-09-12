//
//  YYTextUtilities.h
//  TestYYText
//
//  Created by tongleiming on 2020/9/6.
//

#ifndef YYTextUtilities_h
#define YYTextUtilities_h

#import <UIKit/UIKit.h>

UIKIT_EXTERN NSString *const YYTextTruncationToken; ///< Horizontal ellipsis (U+2026), used for text truncation  "…".

/**
 Convert CFRange to NSRange
 @param range CFRange @return NSRange
 */
static inline NSRange YYTextNSRangeFromCFRange(CFRange range) {
    return NSMakeRange(range.location, range.length);
}


#endif /* YYTextUtilities_h */
