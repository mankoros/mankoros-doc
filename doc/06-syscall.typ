= 系统调用
#label("系统调用")

== 内存相关系统调用
#label("内存相关系统调用")

MankorOS 实现了三个内存相关的系统调用，分别为 brk、mmap 和 munmap。

sys\_brk：该系统调用用于更改进程的堆顶地址，并返回当前进程的堆顶地址。当参数
brk 为 0 时表示查询当前堆顶地址。 MankorOS 实现中，通过使用 Process
的内存管理器，记录和更新堆顶地址。

sys\_mmap：该系统调用允许进程在其虚拟地址空间中映射内存区域。
支持选项包括指定起始地址、长度、权限（PROT\_READ、PROT\_WRITE 和
PROT\_EXEC）和标志（MAP\_SHARED、MAP\_PRIVATE、MAP\_FIXED、MAP\_ANONYMOUS
和 MAP\_NORESERVE）。 MankorOS 通过 Process
的内存管理器来分配和映射物理页框，并将这些页框映射到进程的虚拟地址空间中。

sys\_munmap：该系统调用用于解除映射的内存区域。MankorOS
会通过内存管理器来取消对映射内存的映射，并释放相应的物理页框。

== 文件系统相关系统调用
#label("文件系统相关系统调用")
== 进程相关系统调用
#label("进程相关系统调用")
== 其他系统调用
#label("其他系统调用")

除了上述的系统调用外，MankorOS 还实现了四个系统调用，
分别是三个时间相关的 `gettimeofday`、`times` 和 `nanosleep` 
以及一个系统信息相关的 `uname`。

`gettimeofday`: 该系统调用用于获取 `TimeVal` 格式的当前时间。当前时间由系统 `timer` 直接维护。
`TimeVal` 参考 Linux 实现如下:

```rs
pub struct TimeVal {
    // seconds
    pub tv_sec: usize,
    // microseconds
    pub tv_usec: usize,
}
```

`times`: 该系统调用用于获取当前进程的运行时间。包括在内核态的时间和用户态的时间，以及当前进程的全体子进程的内核态时间和用户态时间。
实现上每个进程都单独维护一个计时器，当进程在用户态和内核态之间切换时更新时间，当进程被剥夺或者被调度时相应地停止或启动计时。
该时间以 `Tms` 的格式返回，参考 Linux 实现如下：

```rs
pub struct Tms {
    // user time
    pub tms_utime: usize,
    // system time
    pub tms_stime: usize,
    // user time of children
    pub tms_cutime: usize,
    // system time of children
    pub tms_cstime: usize,
}
```

`nanosleep`: 该系统调用用于实现纳秒级别的高精度 sleep。用于描述纳秒级的时间间隔的结构体 `TimeSpec` 参考 Linux 实现如下：

```rs
pub struct TimeSpec {
    // seconds
    pub tv_sec: usize,
    // nanoseconds
    pub tv_nsec: usize,
}
```
