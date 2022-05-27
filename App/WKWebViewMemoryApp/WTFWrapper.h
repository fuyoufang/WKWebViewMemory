//
//  WTFWrapper.h
//  WKWebViewMemoryApp
//
//  Created by fuyoufang on 2022/5/27.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WTFWrapper : NSObject

+ (size_t)thresholdForMemoryKillOfActiveProcess;
+ (size_t)thresholdForMemoryKillOfInactiveProcess;

@end

NS_ASSUME_NONNULL_END
