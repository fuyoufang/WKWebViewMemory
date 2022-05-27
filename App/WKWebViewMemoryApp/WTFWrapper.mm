//
//  WTFWrapper.m
//  WKWebViewMemoryApp
//
//  Created by fuyoufang on 2022/5/27.
//

#import "WTFWrapper.h"
#import <wtf/MemoryPressureHandler.h>

// 这个文件必须名称为 .mm 类型，否自会编译错误
@implementation WTFWrapper

+ (size_t)thresholdForMemoryKillOfActiveProcess {
//    WTF::thresholdForMemoryKillOfActiveProcess();
//    WTF::MemoryPressureHandler::singleton().install();
//    WTF::MemoryPressureHandler::Configuration c = WTF::MemoryPressureHandler::Configuration();
//    WTF::MemoryPressureHandler::singleton().setConfiguration(c);
//    WTF::MemoryPressureHandler::singleton().thresholdForMemoryKill();
    
    return WTF::thresholdForMemoryKillOfActiveProcess(1);
}

+ (size_t)thresholdForMemoryKillOfInactiveProcess {    
    return WTF::thresholdForMemoryKillOfInactiveProcess(1);
}
@end
