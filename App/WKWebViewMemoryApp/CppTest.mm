#include "CppTest.hpp"
#include <iostream>
#include <mutex>
#include <array>
#include <mutex>
#import <algorithm>
#import <dispatch/dispatch.h>
#import <mach/host_info.h>
#import <mach/mach.h>
#import <mach/mach_error.h>
#import <math.h>

#define MEMORYSTATUS_CMD_GET_MEMLIMIT_PROPERTIES 8
static constexpr size_t kB = 1024;
static constexpr size_t MB = kB * kB;
static constexpr size_t GB = kB * kB * kB;
static constexpr size_t availableMemoryGuess = 512 * MB;


#if __has_include(<System/sys/kern_memorystatus.h>)
extern "C" {
#include <System/sys/kern_memorystatus.h>
}
#else
extern "C" {
using namespace std;

typedef struct memorystatus_memlimit_properties {
    int32_t memlimit_active;                /* jetsam memory limit (in MB) when process is active */
    uint32_t memlimit_active_attr;
    int32_t memlimit_inactive;              /* jetsam memory limit (in MB) when process is inactive */
    uint32_t memlimit_inactive_attr;
} memorystatus_memlimit_properties_t;

#define MEMORYSTATUS_CMD_GET_MEMLIMIT_PROPERTIES 8
#define MEMORYSTATUS_CMD_SET_PROCESS_IS_FREEZABLE 18
#define MEMORYSTATUS_CMD_GET_PROCESS_IS_FREEZABLE 19

}
#endif // __has_include(<System/sys/kern_memorystatus.h>)

extern "C" {
int memorystatus_control(uint32_t command, int32_t pid, uint32_t flags, void *buffer, size_t buffersize);
}

size_t CppTest::jetsamLimit()
{
    memorystatus_memlimit_properties_t properties;
    pid_t pid = getpid();
    if (memorystatus_control(MEMORYSTATUS_CMD_GET_MEMLIMIT_PROPERTIES, pid, 0, &properties, sizeof(properties)))
        return 840 * MB;
    if (properties.memlimit_active < 0)
        return std::numeric_limits<size_t>::max();
    return static_cast<size_t>(properties.memlimit_active) * MB;
}

size_t CppTest::memorySizeAccordingToKernel()
{
    host_basic_info_data_t hostInfo;

    mach_port_t host = mach_host_self();
    mach_msg_type_number_t count = HOST_BASIC_INFO_COUNT;
    kern_return_t r = host_info(host, HOST_BASIC_INFO, (host_info_t)&hostInfo, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (r != KERN_SUCCESS)
        return availableMemoryGuess;

    if (hostInfo.max_mem > std::numeric_limits<size_t>::max())
        return std::numeric_limits<size_t>::max();

    return static_cast<size_t>(hostInfo.max_mem);
}

size_t CppTest::computeAvailableMemory()
{
    size_t sizeAccordingToKernel = memorySizeAccordingToKernel();
    sizeAccordingToKernel = std::min(sizeAccordingToKernel, jetsamLimit());
    size_t multiple = 128 * MB;

    // Round up the memory size to a multiple of 128MB because max_mem may not be exactly 512MB
    // (for example) and we have code that depends on those boundaries.
    return ((sizeAccordingToKernel + multiple - 1) / multiple) * multiple;
}


size_t CppTest::availableMemory()
{
    static size_t availableMemory;
    static std::once_flag onceFlag;
    std::call_once(onceFlag, [this] {
        availableMemory = computeAvailableMemory();
    });
    return availableMemory;
}


size_t CppTest::computeRAMSize()
{
    return availableMemory();
}

size_t CppTest::ramSize()
{
    static size_t ramSize;
    static std::once_flag onceFlag;
    std::call_once(onceFlag, [this] {
        ramSize = computeRAMSize();
    });
    return ramSize;
}


size_t CppTest::thresholdForMemoryKillOfActiveProcess2(unsigned tabCount)
{
    cout << "ramSize:" << ramSize() << "\n";
    
    size_t baseThreshold = ramSize() > 16 * GB ? 15 * GB : 7 * GB;
    return baseThreshold + tabCount * GB;
}

size_t CppTest::thresholdForMemoryKillOfInactiveProcess(unsigned tabCount)
{
//#if CPU(X86_64) || CPU(ARM64)
//    size_t baseThreshold = 3 * GB + tabCount * GB;
//#else
    size_t baseThreshold = tabCount > 1 ? 3 * GB : 2 * GB;
//#endif
    return std::min(baseThreshold, static_cast<size_t>(ramSize() * 0.9));
}

size_t CppTest::thresholdForMemoryKillOfActiveProcess() {
//    MemoryPressureHandler::singleton();
    cout << "ActiveProcess:" << thresholdForMemoryKillOfActiveProcess2(1) << "\n";
    return thresholdForMemoryKillOfInactiveProcess(1);
    
}
