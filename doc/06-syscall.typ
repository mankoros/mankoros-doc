= 系统调用
#label("系统调用")

== 内存相关系统调用
#label("内存相关系统调用")

MankorOS 实现了三个内存相关的系统调用，分别为 brk、mmap 和 munmap。

`sys_brk`：该系统调用用于更改进程的堆顶地址，并返回当前进程的堆顶地址。
当参数 `brk` 为 `0` 时表示查询当前堆顶地址。
MankorOS 实现中，通过使用 `LightProcess` 的内存管理器，记录和更新堆顶地址。

`sys_mmap`：该系统调用允许进程在其虚拟地址空间中映射内存区域。
支持选项包括指定起始地址、长度、权限
（`PROT_READ`、`PROT_WRITE` 和 `PROT_EXEC`）
和标志
（`MAP_SHARED`、`MAP_PRIVATE`、`MAP_FIXED`、`MAP_ANONYMOUS` 和 `MAP_NORESERVE`）。
MankorOS 通过 `LightProcess` 的内存管理器来分配和映射物理页框，并将这些页框映射到进程的虚拟地址空间中。

`sys_munmap`：该系统调用用于解除映射的内存区域。
MankorOS 会通过内存管理器来取消对映射内存的映射，并释放相应的物理页。

== 文件系统相关系统调用
#label("文件系统相关系统调用")

MankorOS 实现了十四个文件系统相关的系统调用，
其中与文件读写相关的有七个 `openat`、`close`、`read`、`write`, `dup`, `dup3`, `pipe`,
与文件系统相关的有七个 `getcwd`, `fstat`, `mkdir`, `getdents`, `unlinkat`, `mount`, `umount`。

`sys_openat`: 该系统调用用于打开文件。
支持选项包括指定文件路径 (包括基于 `dir_fd` 的相对路径和绝对路径) 和文件创建标志 (`O_CREAT`)。

`sys_close`: 该系统调用用于关闭文件。

`sys_read`: 该系统调用用于读取文件。

`sys_write`: 该系统调用用于写入文件。

`sys_dup`: 该系统调用用于复制文件描述符。

`sys_dup3`: 该系统调用用于复制文件描述符，并指定新的文件描述符的值。

`sys_pipe`: 该系统调用用于创建管道。

`sys_getcwd`: 该系统调用用于获取进程当前工作目录。

`sys_fstat`: 该系统调用用于获取文件的状态。

`sys_mkdir`: 该系统调用用于创建目录。
支持基于 `dir_fd` 的相对路径和绝对路径。

`sys_getdents`: 该系统调用用于获取目录下的文件信息。

`sys_unlinkat`: 该系统调用用于删除文件。
支持指定文件路径 (包括基于 `dir_fd` 的相对路径和绝对路径) 和文件删除标志 (`AT_REMOVEDIR`)。


== 进程相关系统调用
#label("进程相关系统调用")

MankorOS 实现了五个进程相关的系统调用，分别为 `wait`、`clone`、`execve`、`getpid` 和 `getppid`。

`sys_wait`：该系统调用用于等待子进程结束。
支持非空的 `wstatus` 参数，可告知调用者子进程的退出状态。

`sys_clone`: 该系统调用用于创建一个新的进程，并能详细指定资源共享的情况。
支持选项包括指定内存，文件系统信息，已打开文件，信号处理句柄，父进程与线程组的共享选项
(`CLONE_VM`, `CLONE_FS`, `CLONE_FILES`, `CLONE_SIGHAND`, `CLONE_PARENT` 和 `CLONE_THREAD`),
以及设置新进程的局部储存的选项，在父进程中获取子进程 PID, 在子进程中返回 0 的选项和在子进程中获取自身 PID 的选项。
(分别为 `CLONE_SETTLS`, `CLONE_PARENT_SETTID`, `CLONE_CHILD_CLEARTID` 和 `CLONE_CHILD_SETTID`)

`sys_execve`: 该系统调用用于加载新的程序。
支持指定程序的路径，参数和环境变量。

`sys_getpid`: 该系统调用用于获取当前进程的 PID。

`sys_getppid`: 该系统调用用于获取当前进程的父进程的 PID。

== 其他系统调用
#label("其他系统调用")

除了上述的系统调用外，MankorOS 还实现了四个系统调用，
分别是三个时间相关的 `gettimeofday`、`times` 和 `nanosleep` 
以及一个系统信息相关的 `uname`。

`sys_gettimeofday`: 该系统调用用于获取 `TimeVal` 格式的当前时间。
当前时间由系统 `timer` 直接维护。
`TimeVal` 参考 Linux 实现如下：

```rs
pub struct TimeVal {
    // seconds
    pub tv_sec: usize,
    // microseconds
    pub tv_usec: usize,
}
```

`sys_times`: 该系统调用用于获取当前进程的运行时间。
包括在内核态的时间和用户态的时间，以及当前进程的全体子进程的内核态时间和用户态时间。
实现上每个进程都单独维护一个计时器，
当进程在用户态和内核态之间切换时更新时间，
当进程被剥夺或者被调度时相应地停止或启动计时。
该时间以 `Tms` 的格式返回，
参考 Linux 实现如下：

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

`sys_nanosleep`: 该系统调用用于实现纳秒级别的高精度 sleep。
用于描述纳秒级的时间间隔的结构体 `TimeSpec` 参考 Linux 实现如下：

```rs
pub struct TimeSpec {
    // seconds
    pub tv_sec: usize,
    // nanoseconds
    pub tv_nsec: usize,
}
```

`sys_uname`: 该系统调用用于获取系统描述信息。
默认的系统描述信息如下：

#import "../template.typ": tbl
#tbl(
    table(
        columns: (100pt, 200pt),
        inset: 10pt,
        stroke: 0.7pt,
        align: horizon,
        [描述], [值],
        [`sysname`], ["MankorOS"],
        [`nodename`], ["MankorOS-VF2"],
        [`release`], ["rolling"],
        [`version`], ["unknown"],
        [`machine`], ["unknown"],
        [`domainname`], ["localhost"],
    ),
    caption: "uname 的返回值"
)