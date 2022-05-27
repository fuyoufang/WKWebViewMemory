//
//  WKWebViewMemoryAppWrapper.m
//  WKWebViewMemoryApp
//
//  Created by fuyoufang on 2022/5/27.
//

#import "WKWebViewMemoryAppWrapper.h"
#import <wtf/MemoryPressureHandler.h>

// 这个文件必须名称为 .mm 类型，否自会编译错误
@implementation WKWebViewMemoryAppWrapper

- (size_t)thresholdForMemoryKillOfActiveProcess {
//    WTF::thresholdForMemoryKillOfActiveProcess();
    MemoryPressureHandler::singleton();
    return 1;
}
@end
