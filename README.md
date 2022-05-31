# WKWebView 线程终止的原因

> - [WKWebView 线程终止的原因——之 OOM 的控制逻辑](https://juejin.cn/post/7103463814246760485)
> - [WKWebView 线程终止的原因——之 OOM 的数值](https://juejin.cn/editor/drafts/7103465810747736095)


最近在 WKWebView 中展示三维图像渲染的功能时，经常遇到 WKWebView 莫名其妙的 reload 的现象。

> WKWebView 会在 APP 的进程外执行其所有的工作，并且 WKWebView 的内存使用量与 APP 的内存使用量分开计算。这样当 WKWebView 进程超出其内存限制时，就不会导致 APP 程序终止，最多也就是导致空白视图。

为了定位具体的原因，先查看一下 WKWebView 的代理提供的回调方法。在 `WKNavigationDelegate` 中定义了回调方法 `webViewWebContentProcessDidTerminate(_)`：

```swift
/** @abstract Invoked when the web view's web content process is terminated.
@param webView The web view whose underlying web content process was terminated.
*/
@available(iOS 9.0, *)
optional func webViewWebContentProcessDidTerminate(_ webView: WKWebView)
```

当 web 视图的内容进程终止时，将通过此回调通知 APP，然而并没有提供更多的错误信息。

可以通过 [https://github.com/WebKit/WebKit](https://github.com/WebKit/WebKit) 看到 WKWebView 的源码。通过搜索 `webViewWebContentProcessDidTerminate`的方法，可以一步步知道 WKWebView 的异常流程。

## WKWebView 进程异常的流程

### WKWebView 的终止代理流程

在 WebKit 的 NavigationState.mm 文件中，调用了 `webViewWebContentProcessDidTerminate` 方法：

```cpp
bool NavigationState::NavigationClient::processDidTerminate(WebPageProxy& page, ProcessTerminationReason reason)
{
    if (!m_navigationState)
        return false;

    if (!m_navigationState->m_navigationDelegateMethods.webViewWebContentProcessDidTerminate
        && !m_navigationState->m_navigationDelegateMethods.webViewWebContentProcessDidTerminateWithReason
        && !m_navigationState->m_navigationDelegateMethods.webViewWebProcessDidCrash)
        return false;

    auto navigationDelegate = m_navigationState->m_navigationDelegate.get();
    if (!navigationDelegate)
        return false;

    if (m_navigationState->m_navigationDelegateMethods.webViewWebContentProcessDidTerminateWithReason) {
        [static_cast<id <WKNavigationDelegatePrivate>>(navigationDelegate.get()) _webView:m_navigationState->m_webView webContentProcessDidTerminateWithReason:wkProcessTerminationReason(reason)];
        return true;
    }

    // We prefer webViewWebContentProcessDidTerminate: over _webViewWebProcessDidCrash:.
    if (m_navigationState->m_navigationDelegateMethods.webViewWebContentProcessDidTerminate) {
        [navigationDelegate webViewWebContentProcessDidTerminate:m_navigationState->m_webView];
        return true;
    }

    ASSERT(m_navigationState->m_navigationDelegateMethods.webViewWebProcessDidCrash);
    [static_cast<id <WKNavigationDelegatePrivate>>(navigationDelegate.get()) _webViewWebProcessDidCrash:m_navigationState->m_webView];
    return true;
}
```

在 `processDidTerminate()` 方法中，当线程终止时的处理流程为：

- 若未设置代理方法，则返回 false；
- 如果代理实现了 `_webView:webViewWebContentProcessDidTerminateWithReason:`，则回调，并返回 true；
- 如果代理实现了 `webViewWebContentProcessDidTerminate:`，则回调，并返回 true；
- 调用回调方法：`_webViewWebProcessDidCrash:`，并返回 true。

代理方法的设置方法如下：
```cpp
void NavigationState::setNavigationDelegate(id <WKNavigationDelegate> delegate)
{
    // ....
    m_navigationDelegateMethods.webViewWebContentProcessDidTerminate = [delegate respondsToSelector:@selector(webViewWebContentProcessDidTerminate:)];
    m_navigationDelegateMethods.webViewWebContentProcessDidTerminateWithReason = [delegate respondsToSelector:@selector(_webView:webContentProcessDidTerminateWithReason:)];
    // ....
}
```

在 `processDidTerminate()` 方法中，参数 `reason`说明了异常原因，类型为 `ProcessTerminationReason`，定义如下：

```cpp
enum class ProcessTerminationReason {
    ExceededMemoryLimit, // 超出内存限制
    ExceededCPULimit,    // 超出CPU限制
    RequestedByClient,   // 主动触发的terminate
    IdleExit,
    Unresponsive,        // 无法响应
    Crash,               // web进程自己发生了crash
    // Those below only relevant for the WebContent process.
    ExceededProcessCountLimit,
    NavigationSwap,
    RequestedByNetworkProcess,
    RequestedByGPUProcess
};
```

### 通过代理方法获取异常原因
可以看到回调方法有两个：`webViewWebContentProcessDidTerminate:` 和`_webView:webContentProcessDidTerminateWithReason:`，一个不带 reason 参数，一个带有 reason 参数，并且带有 reason 参数的回调方法优先级更高。

在 WKWebView 的 `WKNavigationDelegate` 代理中，我们只看到了不带 reason 的回调方法，那 `_webView:webContentProcessDidTerminateWithReason:` 是怎么回事呢？

通过检索发现，它定义在 `WKNavigationDelegatePrivate` 在代理中：
```
@protocol WKNavigationDelegatePrivate <WKNavigationDelegate>

@optional

// ...
- (void)_webView:(WKWebView *)webView webContentProcessDidTerminateWithReason:(_WKProcessTerminationReason)reason WK_API_AVAILABLE(macos(10.14), ios(12.0));
// ...
@end
```

**`WKNavigationDelegatePrivate` 并没有公开让 App 使用。不过，我们依然可以通过实现上面的代理方法，获取到 reason 信息。**

不过需要注意：WebKit 内部的异常类型为：`ProcessTerminationReason`，而此处 reason 参数的类型为：`_WKProcessTerminationReason`：

```c++
typedef NS_ENUM(NSInteger, _WKProcessTerminationReason) {
    _WKProcessTerminationReasonExceededMemoryLimit,
    _WKProcessTerminationReasonExceededCPULimit,
    _WKProcessTerminationReasonRequestedByClient,
    _WKProcessTerminationReasonCrash,
} WK_API_AVAILABLE(macos(10.14), ios(12.0));
```

`_WKProcessTerminationReason` 和 `ProcessTerminationReason` 的转换关系如下：

```c++
static _WKProcessTerminationReason wkProcessTerminationReason(ProcessTerminationReason reason)
{
    switch (reason) {
    case ProcessTerminationReason::ExceededMemoryLimit:
        return _WKProcessTerminationReasonExceededMemoryLimit;
    case ProcessTerminationReason::ExceededCPULimit:
        return _WKProcessTerminationReasonExceededCPULimit;
    case ProcessTerminationReason::NavigationSwap:
    case ProcessTerminationReason::IdleExit:
        // We probably shouldn't bother coming up with a new API type for process-swapping.
        // "Requested by client" seems like the best match for existing types.
        FALLTHROUGH;
    case ProcessTerminationReason::RequestedByClient:
        return _WKProcessTerminationReasonRequestedByClient;
    case ProcessTerminationReason::ExceededProcessCountLimit:
    case ProcessTerminationReason::Unresponsive:
    case ProcessTerminationReason::RequestedByNetworkProcess:
    case ProcessTerminationReason::RequestedByGPUProcess:
    case ProcessTerminationReason::Crash:
        return _WKProcessTerminationReasonCrash;
    }
    ASSERT_NOT_REACHED();
    return _WKProcessTerminationReasonCrash;
}
```
可以看出，在转换过程中，并不是一一对应的，会损失掉具体的 crash 类型。也就是，当我们实现`_webView:webContentProcessDidTerminateWithReason:`代理时，可以获取到一个相对笼统的 reason。

### 内存超限的逻辑（ExceededMemoryLimit)

下面先分析内存超限的逻辑。

初始化 web 线程的方法：`initializeWebProcess()`，实现如下：

```cpp
void WebProcess::initializeWebProcess(WebProcessCreationParameters&& parameters)
{    
    // ...
    if (!m_suppressMemoryPressureHandler) {
        // ...
        #if ENABLE(PERIODIC_MEMORY_MONITOR)
        memoryPressureHandler.setShouldUsePeriodicMemoryMonitor(true);
        memoryPressureHandler.setMemoryKillCallback([this] () {
            WebCore::logMemoryStatistics(LogMemoryStatisticsReason::OutOfMemoryDeath);
            if (MemoryPressureHandler::singleton().processState() == WebsamProcessState::Active)
                parentProcessConnection()->send(Messages::WebProcessProxy::DidExceedActiveMemoryLimit(), 0);
            else
                parentProcessConnection()->send(Messages::WebProcessProxy::DidExceedInactiveMemoryLimit(), 0);
        });

        // ...
        #endif
        // ...
    }
    // ...
}
```

其中：
- `setShouldUsePeriodicMemoryMonitor()` 设置是否需要定期检测内存；
- `setMemoryKillCallback()` 设置内存超限后，被终止后的回调。

### 定期内存检测

设置定期内存检测的方法`setShouldUsePeriodicMemoryMonitor`的实现如下：

```cpp
void MemoryPressureHandler::setShouldUsePeriodicMemoryMonitor(bool use)
{
    if (!isFastMallocEnabled()) {
        // If we're running with FastMalloc disabled, some kind of testing or debugging is probably happening.
        // Let's be nice and not enable the memory kill mechanism.
        return;
    }

    if (use) {
        m_measurementTimer = makeUnique<RunLoop::Timer<MemoryPressureHandler>>(RunLoop::main(), this, &MemoryPressureHandler::measurementTimerFired);
        m_measurementTimer->startRepeating(m_configuration.pollInterval);
    } else
        m_measurementTimer = nullptr;
}
```

其中，初始化了一个 Timer，时间间隔为 m_configuration.pollInterval（pollInterval 的值为 30s），执行方法为 `measurementTimerFired()`。也就是每隔 30s 调用一次 `measurementTimerFired()` 对内存使用量进行一次检查。

内存检查的方法 `measurementTimerFired()` 定义如下： 

```cpp
void MemoryPressureHandler::measurementTimerFired()
{
    size_t footprint = memoryFootprint();
#if PLATFORM(COCOA)
    RELEASE_LOG(MemoryPressure, "Current memory footprint: %zu MB", footprint / MB);
#endif
    auto killThreshold = thresholdForMemoryKill();
    if (killThreshold && footprint >= *killThreshold) {
        shrinkOrDie(*killThreshold);
        return;
    }

    setMemoryUsagePolicyBasedOnFootprint(footprint);

    switch (m_memoryUsagePolicy) {
    case MemoryUsagePolicy::Unrestricted:
        break;
    case MemoryUsagePolicy::Conservative:
        releaseMemory(Critical::No, Synchronous::No);
        break;
    case MemoryUsagePolicy::Strict:
        releaseMemory(Critical::Yes, Synchronous::No);
        break;
    }

    if (processState() == WebsamProcessState::Active && footprint > thresholdForMemoryKillOfInactiveProcess(m_pageCount))
        doesExceedInactiveLimitWhileActive();
    else
        doesNotExceedInactiveLimitWhileActive();
}

```

其中，`footprint`来为当前使用的内存量，`killThreshold`为内存的最大限制。如果 `killThreshold` 大于等于 `footprint`，则调用 `shrinkOrDie()`。

### 当前使用的内存量

当前使用的内存量是通过 `memoryFootprint()`来获取的。定义如下：

```cpp
namespace WTF {

size_t memoryFootprint()
{
    task_vm_info_data_t vmInfo;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t) &vmInfo, &count);
    if (result != KERN_SUCCESS)
        return 0;
    return static_cast<size_t>(vmInfo.phys_footprint);
}

}
```

其中，使用到了 `task_info`来获取线程的信息，传递的参数有：

- mach_task_self() ：获取当前进程
- TASK_VM_INFO：取虚拟内存信息
- vmInfo、count：两个参数传递的为引用地址，用于接收返回值。
    - vmInfo：task_vm_info_data_t 里的 phys_footprint 就是进程的内存占用，以 byte 为单位。

### 内存的最大限制

内存最大的限制由 thresholdForMemoryKill() 方法实现，定义如下：

```cpp
std::optional<size_t> MemoryPressureHandler::thresholdForMemoryKill()
{
    if (m_configuration.killThresholdFraction)
        return m_configuration.baseThreshold * (*m_configuration.killThresholdFraction);

    switch (m_processState) {
    case WebsamProcessState::Inactive:
        return thresholdForMemoryKillOfInactiveProcess(m_pageCount);
    case WebsamProcessState::Active:
        return thresholdForMemoryKillOfActiveProcess(m_pageCount);
    }
    return std::nullopt;
}

static size_t thresholdForMemoryKillOfActiveProcess(unsigned tabCount)
{
    size_t baseThreshold = ramSize() > 16 * GB ? 15 * GB : 7 * GB;
    return baseThreshold + tabCount * GB;
}

static size_t thresholdForMemoryKillOfInactiveProcess(unsigned tabCount)
{
#if CPU(X86_64) || CPU(ARM64)
    size_t baseThreshold = 3 * GB + tabCount * GB;
#else
    size_t baseThreshold = tabCount > 1 ? 3 * GB : 2 * GB;
#endif
    return std::min(baseThreshold, static_cast<size_t>(ramSize() * 0.9));
}
```
可以看出，最大的可用内存由：当前的 webview 的页数（m_pageCount），线程的状态（Inactive 和 Active）和 ramSize() 计算得来。

当前的页数和线程的状态比较易容理解，下面来看 ramSize() 的计算方法：
```cpp
namespace WTF {

size_t ramSize()
{
    static size_t ramSize;
    static std::once_flag onceFlag;
    std::call_once(onceFlag, [] {
        ramSize = computeRAMSize();
    });
    return ramSize;
}

} // namespace WTF
```

ramSize 只会计算一次，由 `computeRAMSize()` 计算得来，定义如下：

```cpp
#if OS(WINDOWS)
static constexpr size_t ramSizeGuess = 512 * MB;
#endif

static size_t computeRAMSize()
{
#if OS(WINDOWS)
    MEMORYSTATUSEX status;
    status.dwLength = sizeof(status);
    bool result = GlobalMemoryStatusEx(&status);
    if (!result)
        return ramSizeGuess;
    return status.ullTotalPhys;

#elif USE(SYSTEM_MALLOC)

#if OS(LINUX) || OS(FREEBSD)
    struct sysinfo si;
    sysinfo(&si);
    return si.totalram * si.mem_unit;
#elif OS(UNIX)
    long pages = sysconf(_SC_PHYS_PAGES);
    long pageSize = sysconf(_SC_PAGE_SIZE);
    return pages * pageSize;
#else
#error "Missing a platform specific way of determining the available RAM"
#endif // OS(LINUX) || OS(FREEBSD) || OS(UNIX)
#else
    return bmalloc::api::availableMemory();
#endif
}
```

`computeRAMSize()` 中，根据不同的操作系统（Windows，LINUX、Unix）和一个默认方式来计算。需要注意的是：虽然iOS是基于 Unix 的，但是这里的 Unix 不包括 iOS 系统。所以，在 iOS 系统中，会执行 `return bmalloc::api::availableMemory();`。定义如下：

```cpp
inline size_t availableMemory()
{
    return bmalloc::availableMemory();
}
```

它只是简单的调用了 `bmalloc::availableMemory()`。再来看 `bmalloc::availableMemory()` 的实现：

```cpp
size_t availableMemory()
{
    static size_t availableMemory;
    static std::once_flag onceFlag;
    std::call_once(onceFlag, [] {
        availableMemory = computeAvailableMemory();
    });
    return availableMemory;
}
```

`availableMemory()`方法中的 `availableMemory`只会计算一次，由  `computeAvailableMemory()`计算而来。


```cpp
static constexpr size_t availableMemoryGuess = 512 * bmalloc::MB;

static size_t computeAvailableMemory()
{
#if BOS(DARWIN)
    size_t sizeAccordingToKernel = memorySizeAccordingToKernel();
#if BPLATFORM(IOS_FAMILY)
    sizeAccordingToKernel = std::min(sizeAccordingToKernel, jetsamLimit());
#endif
    size_t multiple = 128 * bmalloc::MB;

    // Round up the memory size to a multiple of 128MB because max_mem may not be exactly 512MB
    // (for example) and we have code that depends on those boundaries.
    return ((sizeAccordingToKernel + multiple - 1) / multiple) * multiple;
#elif BOS(FREEBSD) || BOS(LINUX)
    //...
#elif BOS(UNIX)
    //...
#else
    return availableMemoryGuess;
#endif
}
```

在 `computeAvailableMemory()`方法中，

1. 先通过 `memorySizeAccordingToKernel()` 获取内核的内存大小；
1. 如果是 iOS 系统，再获取 jetsam 的限制：`jetsamLimit()`，在内存大小和 jetsamLimit() 中取较小的值；
1. 将结果向上取整为 128M 的倍数。

所以，此处的结果依赖于 `memorySizeAccordingToKernel()` 和 `jetsamLimit()`。

先看 `memorySizeAccordingToKernel()`的实现：

```cpp
#if BOS(DARWIN)
static size_t memorySizeAccordingToKernel()
{
#if BPLATFORM(IOS_FAMILY_SIMULATOR)
    BUNUSED_PARAM(availableMemoryGuess);
    // Pretend we have 1024MB of memory to make cache sizes behave like on device.
    return 1024 * bmalloc::MB;
#else
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
#endif
}

#endif
```
逻辑为：

1. 如果是模拟器，则内存设定为 1024M。
1. 如果是真实设备，则通过 `host_info`获取结构体为 `host_basic_info_data_t` 的信息，读取 `max_mem`的数值，然后与 `std::numeric_limits<size_t>::max()`进行比较，取其中较小的值。其中 `std::numeric_limits<size_t>::max()` 为当前设备可以表示的最大值。
1. 计算失败时，返回 availableMemoryGuess，即 512 M。


再来看`jetsamLimit()`的实现：

```cpp
#if BPLATFORM(IOS_FAMILY)
static size_t jetsamLimit()
{
    memorystatus_memlimit_properties_t properties;
    pid_t pid = getpid();
    if (memorystatus_control(MEMORYSTATUS_CMD_GET_MEMLIMIT_PROPERTIES, pid, 0, &properties, sizeof(properties)))
        return 840 * bmalloc::MB;
        
    if (properties.memlimit_active < 0)
        return std::numeric_limits<size_t>::max();

    return static_cast<size_t>(properties.memlimit_active) * bmalloc::MB;
}
#endif
```

在 `jetsamLimit()`中，

1. 通过 `memorystatus_control()` 获取结构体为 `memorystatus_memlimit_properties_t` 的信息，返回值不为 0，则返回 840M；
1. 如果获取的 memoryStatus 的限制属性 memlimit_active 小于 0 时，则返回当前设备可以表示的最大值；
1. 如果运行正常，则返回系统返回的数值。

至此，就看到了 `ramSize()` 的整个计算过程。

总结一下内存最大限制的计算方法：

1. 判断线程当前的状态：
    1. 激活状态
        1. 计算 ramSize()；
            1. 计算内核的内存大小和 jetsam 的限制，取较小值，
            1. 向上取整为 128M 的倍数。
        1. 计算 `baseThreshold = ramSize() > 16 * GB ? 15 * GB : 7 * GB；`
        1. 最终结果为：baseThreshold + tabCount * *GB;*
    1. 非激活状态：
        1. 在 `CPU(X86_64) || CPU(ARM64)` 下，`baseThreshold = 3 * GB + tabCount * GB;`，否则 `baseThreshold = tabCount > 1 ? 3 * GB : 2 * GB;`；
        1. 最终结果为：`smin(baseThreshold, (ramSize() * 0.9))`；

### 内存超限的处理

内存超限之后，就会调用 `shrinkOrDie()`，定义如下：

```cpp
void MemoryPressureHandler::shrinkOrDie(size_t killThreshold)
{
    RELEASE_LOG(MemoryPressure, "Process is above the memory kill threshold. Trying to shrink down.");
    releaseMemory(Critical::Yes, Synchronous::Yes);

    size_t footprint = memoryFootprint();
    RELEASE_LOG(MemoryPressure, "New memory footprint: %zu MB", footprint / MB);

    if (footprint < killThreshold) {
        RELEASE_LOG(MemoryPressure, "Shrank below memory kill threshold. Process gets to live.");
        setMemoryUsagePolicyBasedOnFootprint(footprint);
        return;
    }

    WTFLogAlways("Unable to shrink memory footprint of process (%zu MB) below the kill thresold (%zu MB). Killed\n", footprint / MB, killThreshold / MB);
    RELEASE_ASSERT(m_memoryKillCallback);
    m_memoryKillCallback();
}
```

其中，`m_memoryKillCallback` 就是在初始化 web 线程时设置的回调。

**由于 OOM 导致 reload/白屏，看起来并不是iOS的机制。从方法的调用关系进行全局检索，目前发现内存超出导致的白屏只有这么一条调用链。**


## OOM 之后的默认处理流程

苹果对 WebContentProcessDidTerminate 的处理逻辑如下：

```c++
void WebPageProxy::dispatchProcessDidTerminate(ProcessTerminationReason reason)
{
    bool handledByClient = false;
    if (m_loaderClient)
        handledByClient = reason != ProcessTerminationReason::RequestedByClient && m_loaderClient->processDidCrash(***this**);
    else
        handledByClient = m_navigationClient->processDidTerminate(*this, reason);

    if (!handledByClient && shouldReloadAfterProcessTermination(reason)) {
        // We delay the view reload until it becomes visible.
        if (isViewVisible())
            tryReloadAfterProcessTermination();
        else {
            WEBPAGEPROXY_RELEASE_LOG_ERROR(Loading, "dispatchProcessDidTerminate: Not eagerly reloading the view because it is not currently visible");
            m_shouldReloadDueToCrashWhenVisible = true;
        }
    }
}

```
其中 m_loaderClient 只在苹果的单元测试中有使用，所以，正式版本的 iOS 下应该会执行:
```
handledByClient = m_navigationClient->processDidTerminate(*this, reason);
```

如果开发者未实现 `webViewWebContentProcessDidTerminate(_)` 的代理方法，将返回 false，进入苹果的默认处理逻辑：通过 `shouldReloadAfterProcessTermination()` 判断是否需要进行重新加载，如果需要则在适当时候进行重新加载。

`shouldReloadAfterProcessTermination()` 根据终止原因来判断是否需要进行重新加载：
```
static bool shouldReloadAfterProcessTermination(ProcessTerminationReason reason)
{
    switch (reason) {
    case ProcessTerminationReason::ExceededMemoryLimit:
    case ProcessTerminationReason::ExceededCPULimit:
    case ProcessTerminationReason::RequestedByNetworkProcess:
    case ProcessTerminationReason::RequestedByGPUProcess:
    case ProcessTerminationReason::Crash:
    case ProcessTerminationReason::Unresponsive:
        return true;
    case ProcessTerminationReason::ExceededProcessCountLimit:
    case ProcessTerminationReason::NavigationSwap:
    case ProcessTerminationReason::IdleExit:
    case ProcessTerminationReason::RequestedByClient:
        break;
    }
    return false;
}
```
 
`tryReloadAfterProcessTermination()` 的刷新逻辑如下：
```
static unsigned maximumWebProcessRelaunchAttempts = 1;

void WebPageProxy::tryReloadAfterProcessTermination()
{
    m_resetRecentCrashCountTimer.stop();
    if (++m_recentCrashCount > maximumWebProcessRelaunchAttempts) {
        WEBPAGEPROXY_RELEASE_LOG_ERROR(Process, "tryReloadAfterProcessTermination: process crashed and the client did not handle it, not reloading the page because we reached the maximum number of attempts");
        m_recentCrashCount = 0;
        return;
    }
    WEBPAGEPROXY_RELEASE_LOG(Process, "tryReloadAfterProcessTermination: process crashed and the client did not handle it, reloading the page");
    reload(ReloadOption::ExpiredOnly);
}
```

每次 crash 后，苹果会给 crash 标识（m_recentCrashCount）进行 +1，在不超过最大限制（maximumWebProcessRelaunchAttempts = 1）时，系统会进行刷新，当最近 crash 的次数超过限制时，它便不会刷新，只是将标示归位为0，下次就可以刷新。

总结一下：如果开发者未实现 `webViewWebContentProcessDidTerminate(_)` 的代理方法：
1. 则根据 crash 的原因判断是否要重新刷新；
2. 重新刷新有最大次数限制（一次），超过则不会进行刷新。

> 后记：我们在iOS的Safari上测试了safari的白屏处理逻辑，当第一次发生白屏时Safari会默认重刷，第二次时safari会展示错误加载页，提示当前页面多次发生了错误。这个逻辑和上面webkit的默认处理逻辑时相似的。
> - 摘自：https://www.twblogs.net/a/5cfe4bdfbd9eee14644ebba1/?lang=zh-cn

至此，就总结了 WKWebView 检测内存的方法，计算最大内存限制的方法和默认的处理方法。

## 最大可用内存到底是多少

那 iOS 的最大可用内存到底是多少呢？我们可不可以将 [WebKit](https://github.com/WebKit/WebKit) 中的计算逻辑拿出来运行一下呢？

> 最终的实现过程可以查看 GitHub 上的 [WKWebViewMemory](https://github.com/fuyoufang/WKWebViewMemory)。

### 抽离 WebKit 的计算方法

我们可以尝试将[WKWebView 线程终止的原因——之 OOM 的控制逻辑](https://juejin.cn/post/7103463814246760485)中找的的对应方法，放到一个 app 程序当中，来获取对应的数值。

整体的方法整理在如下：

```c++
#include "MemoryPressure.hpp"
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

size_t MemoryPressure::jetsamLimit()
{
    memorystatus_memlimit_properties_t properties;
    pid_t pid = getpid();
    if (memorystatus_control(MEMORYSTATUS_CMD_GET_MEMLIMIT_PROPERTIES, pid, 0, &properties, sizeof(properties)))
        return 840 * MB;
    if (properties.memlimit_active < 0)
        return std::numeric_limits<size_t>::max();
    return static_cast<size_t>(properties.memlimit_active) * MB;
}

size_t MemoryPressure::memorySizeAccordingToKernel()
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

size_t MemoryPressure::computeAvailableMemory()
{
    size_t memorySize = memorySizeAccordingToKernel();
    size_t sizeJetsamLimit = jetsamLimit();
    cout << "jetsamLimit:" << sizeJetsamLimit / 1024 / 1024 << "MB\n";
    cout << "memorySize:" << memorySize / 1024 / 1024 << "MB\n";
    size_t sizeAccordingToKernel = std::min(memorySize, sizeJetsamLimit);
    size_t multiple = 128 * MB;

    // Round up the memory size to a multiple of 128MB because max_mem may not be exactly 512MB
    // (for example) and we have code that depends on those boundaries.
    sizeAccordingToKernel = ((sizeAccordingToKernel + multiple - 1) / multiple) * multiple;
    cout << "sizeAccordingToKernel:" << sizeAccordingToKernel / 1024 / 1024 << "MB\n";
    return sizeAccordingToKernel;
}

size_t MemoryPressure::availableMemory()
{
    static size_t availableMemory;
    static std::once_flag onceFlag;
    std::call_once(onceFlag, [this] {
        availableMemory = computeAvailableMemory();
    });
    return availableMemory;
}

size_t MemoryPressure::computeRAMSize()
{
    return availableMemory();
}

size_t MemoryPressure::ramSize()
{
    static size_t ramSize;
    static std::once_flag onceFlag;
    std::call_once(onceFlag, [this] {
        ramSize = computeRAMSize();
    });
    return ramSize;
}

size_t MemoryPressure::thresholdForMemoryKillOfActiveProcess(unsigned tabCount)
{
    size_t ramSizeV = ramSize();
    cout << "ramSize:" << ramSizeV / 1024 / 1024 << "MB\n";
    
    size_t baseThreshold = ramSizeV > 16 * GB ? 15 * GB : 7 * GB;
    return baseThreshold + tabCount * GB;
}

size_t MemoryPressure::thresholdForMemoryKillOfInactiveProcess(unsigned tabCount)
{
//#if CPU(X86_64) || CPU(ARM64)
    size_t baseThreshold = 3 * GB + tabCount * GB;
//#else
//    size_t baseThreshold = tabCount > 1 ? 3 * GB : 2 * GB;
//#endif
    return std::min(baseThreshold, static_cast<size_t>(ramSize() * 0.9));
}
```
上面方法中的具体作用，可以查看[WKWebView 线程终止的原因——之 OOM 的控制逻辑](https://juejin.cn/post/7103463814246760485)。

Swift 并不能直接调用 C++ 的方法，所以，我们需要使用 Object-C 进行封装：

```Object-C
#import "MemoryPressureWrapper.h"
#import "MemoryPressure.hpp"

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
```

> 另外：如果 Object-C 调用 C++ 代码时，要将创建的 `.m` 文件后缀改成 `.mm` ，告诉 XCode 编译该文件时要用到 C++ 代码。

### 直接引用 WebKit 的基础模块

在 WebKit 中，内存相关的方法在 `WTF` 和 `bmalloc` 模块中。我们可以下载下来源码，然后创建一个 APP 来引用。步骤如下：
1. 下载 [WebKit](https://github.com/WebKit/WebKit) 源码，找到 `Source/WTF` 和 `Source/bmalloc` 模块，和 `Tools/ccache` 文件。
1. 新建一个 WorkSpace：WKWebViewMemory，再新建、添加一个 iOS Project：WKWebViewMemoryApp。并将步骤 1 中的 `Source/WTF` 和 `Source/bmalloc` 模块添加到 WorkSpace 中，
2. 在 WKWebViewMemoryApp 的 TARGETS 的 Build Settings 中，找到 `Header Search Paths`，添加 `$(BUILT_PRODUCTS_DIR)/usr/local/include`、`$(DSTROOT)/usr/local/include` 和 `$(inherited)`。
1. 因为 `WTF`中的计算方法为 private 的，为了能在 app 中进行访问，需要修改为 public。

最终，就可以通过下面的方式进行获取了：
```
#import "WTFWrapper.h"
#import <wtf/MemoryPressureHandler.h>

// 这个文件必须名称为 .mm 类型，否自会编译错误
@implementation WTFWrapper

+ (size_t)thresholdForMemoryKillOfActiveProcess {
    return WTF::thresholdForMemoryKillOfActiveProcess(1);
}

+ (size_t)thresholdForMemoryKillOfInactiveProcess {    
    return WTF::thresholdForMemoryKillOfInactiveProcess(1);
}
@end
```

### 运行结果

在 iPhoneXS 上运行的结果为：
```
jetsamLimit 的值为：840MB
内存大小（memorySize）为：3778MB
ramSize为：896MB
激活状态下（ActiveProcess）的最大可用内存为：8G
非激活状态下（InactiveProcess）的最大可用内存为：806M
```

**奇怪的结果**：在最大内存为 3778MB（不到 4G）的手机上，最大可用内存居然为 8G。

为什么？难道计算错了？难道内存没有限制？

我们来重新看一下获取最大可用内存的方法：

```c++
std::optional<size_t> MemoryPressureHandler::thresholdForMemoryKill()
{
    if (m_configuration.killThresholdFraction)
        return m_configuration.baseThreshold * (*m_configuration.killThresholdFraction);

    switch (m_processState) {
    case WebsamProcessState::Inactive:
        return thresholdForMemoryKillOfInactiveProcess(m_pageCount);
    case WebsamProcessState::Active:
        return thresholdForMemoryKillOfActiveProcess(m_pageCount);
    }
    return std::nullopt;
}
```
如果配置当中设置了 killThresholdFraction，则会通过 `m_configuration.baseThreshold * (*m_configuration.killThresholdFraction);` 进行计算。

我怀疑是抽离出来的方法，没有设置 killThresholdFraction，而在 iOS 系统中，在初始化 WKWebView 时，会设置此值，来返回一个合理的数值。

那在 iOS 系统中，thresholdForMemoryKill() 究竟会返回多少呢？可能只能通过 WKWebView 的源码进行获取了。


> 如果想获取最终可以运行的项目，可以查看 GitHub 上的 [WKWebViewMemory](https://github.com/fuyoufang/WKWebViewMemory)。

## 参考
- [iOS开发 - 在 Swift 中去调用 C/C++ 代码](https://glumes.com/post/ios/swift-call-c-function/)
- [https://developer.apple.com/forums/thread/21956](https://developer.apple.com/forums/thread/21956)
- [https://www.twblogs.net/a/5cfe4bdfbd9eee14644ebba1/?lang=zh-cn](https://www.twblogs.net/a/5cfe4bdfbd9eee14644ebba1/?lang=zh-cn)
- [https://justinyan.me/post/3982](https://justinyan.me/post/3982)
- [https://www.jianshu.com/p/22a077fd51f1](https://www.jianshu.com/p/22a077fd51f1)
