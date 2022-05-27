//
//  MemoryPressureWrapper.h
//  Example
//
//  Created by Edward Hyde on 18/11/2018.
//  Copyright © 2018 Edward Hyde. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MemoryPressureWrapper: NSObject

+ (size_t)thresholdForMemoryKillOfActiveProcess;

+ (size_t)thresholdForMemoryKillOfInactiveProcess;

@end
