#ifndef MemoryPressure_hpp
#define MemoryPressure_hpp

#pragma once
#include <string>
class MemoryPressure {
public:
    size_t jetsamLimit();
    size_t memorySizeAccordingToKernel();
    size_t computeAvailableMemory();
    size_t availableMemory();
    size_t computeRAMSize();
    size_t ramSize();
    size_t thresholdForMemoryKillOfActiveProcess(unsigned tabCount);
    size_t thresholdForMemoryKillOfInactiveProcess(unsigned tabCount);
};
#endif /* MemoryPressure_hpp */

