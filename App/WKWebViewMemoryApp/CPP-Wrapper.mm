//
//  CPP-Wrapper.mm
//  Example
//
//  Created by Edward Hyde on 18/11/2018.
//  Copyright © 2018 Edward Hyde. All rights reserved.
//

#import "CPP-Wrapper.h"
#import "CppTest.hpp"
//#import <wtf/Deque.h>
//#import <wtf/MemoryPressureHandler.h>

@implementation CPP_Wrapper
- (size_t)thresholdForMemoryKillOfActiveProcess {
    CppTest cpp;
    return cpp.thresholdForMemoryKillOfActiveProcess();
}
@end
