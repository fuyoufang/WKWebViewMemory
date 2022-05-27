//
//  CPP-Wrapper.mm
//  Example
//
//  Created by Edward Hyde on 18/11/2018.
//  Copyright © 2018 Edward Hyde. All rights reserved.
//

#import "MemoryPressureWrapper.h"
#import "MemoryPressure.hpp"
//#import <wtf/Deque.h>
//#import <wtf/MemoryPressureHandler.h>

@implementation MemoryPressureWrapper

+ (size_t)thresholdForMemoryKillOfActiveProcess {
    MemoryPressure cpp;
    return cpp.thresholdForMemoryKillOfActiveProcess(1);
}

+ (size_t)thresholdForMemoryKillOfInactiveProcess {
    MemoryPressure cpp;
    return cpp.thresholdForMemoryKillOfInactiveProcess(1);
}

@end
