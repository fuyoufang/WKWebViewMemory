#ifndef CppTest_hpp
#define CppTest_hpp

#pragma once
#include <string>
class CppTest {
public:
    size_t thresholdForMemoryKillOfActiveProcess();
    size_t jetsamLimit();
    
    size_t memorySizeAccordingToKernel();
    size_t computeAvailableMemory();
    size_t availableMemory();
    size_t computeRAMSize();
    size_t ramSize();
    size_t thresholdForMemoryKillOfActiveProcess2(unsigned tabCount);
    size_t thresholdForMemoryKillOfInactiveProcess(unsigned tabCount);
};
#endif /* CPerson_hpp */

