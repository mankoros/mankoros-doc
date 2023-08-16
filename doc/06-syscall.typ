= 系统调用
#label("syscall")

== 支持的系统调用列表与详细信息
#label("syscall-list")

=== IO 与文件描述符相关系统调用

\
*创建与关闭文件描述符：*

- `openat`
- `readlinkat`
- `close`
- `pipe2`
- `dup` / `dup3`
- `fcntl`

其中 `openat` 支持任意深的递归链接路径和 `CREATE` 与 `NOFOLLOW` 标志。`fcntl` 支持 `F_DUPFD_CLOEXEC` 标志，并对其他标志采用空实现。

\
*读取与写入：*

- `read` / `readv` / `pread` / `preadv`
- `write` / `writev` / `pwrite` / `pwritev`
- `lseek`
- `ppoll`
- `pselect`
- `ioctl`

其中 `lseek` 支持 `SEEK_SET`、`SEEK_CUR`、`SEEK_END` 三种 `whence`. 实现上文件读写偏移量存放于文件描述符中，与 VFS 层的文件无关。

`ppoll` 与 `pselect` 均采用了异步方式实现，充分利用了 MankorOS 中的异步设施。其中 `ppoll` 支持监听 `POLLCLR`(`event` == 0, 只清空 revent), `POLLIN` 和 `POLLOUT` 三种事件，并且能够使用 `timeout_ts` 指定超时。而 `pselect` 支持 `readfds` 和 `writefds` 两个参数，暂不支持 `exceptfds` 参数。其可以使用 `tsptr` 指定超时，以支持特定用户程序使用 `pselect` 作为高精度的 `sleep` 使用的需求。在目前实现中，两个函数均只标记单个事件的发生，会在单个事件发生时直接返回，后续可能会将其优化为返回前同时检查其他事件是否发生。

`ioctl` 目前仅支持对 `/dev/tty` 设备的 `TIOCGPGRP` 与 `TIOCSPGRP` 命令。

=== 文件系统相关系统调用

\
*读取文件元信息/文件夹/文件系统元信息：*

- `fstat(at)`
- `getdents`
- `statfs`
- `faccessat`

若用户传入的缓冲区不够长，`getdents` 能智能地保存当前文件描述符对目录的读取位置，并在下次调用时从上次读取的位置继续读取。

由于 MankorOS 中没有实现多用户，因此 `faccessat` 只检查文件是否存在，若存在一律返回成功。

\
*创建与删除文件：*

- `unlinkat`
- `mkdir`
- `mount` / `umount`

\
*修改文件元信息：*

- `fturncate`
- `utimensat`
- `renameat2`

=== 进程相关的系统调用

\
*读取与修改进程信息：*

- `getpid` / `gettid` / `getppid` 
- `getpgid` / `setpgid`
- `set_tid_address`
- `getcwd` / `chdir`
- `getrlimit` / `prlimit`

其中 `prlimit` 仅支持设置 `RLIMIT_NOFILE` 一种资源限制，并且该限制会体现与 `openat` 等系统调用之中。

\
*进程的创建、退出与多进程管理：*

- `clone`
- `execve`
- `exit` / `exit_group`
- `wait`

其中 `clone` 支持下列 flag:

- `CLONE_VM`: 共享用户地址空间 (内存)
- `CLONE_FS`: 共享文件系统信息
- `CLONE_FILES`: 共享已打开的文件
- `CLONE_SIGHAND`: 共享信号处理句柄
- `CLONE_PARENT`: 保持新线程 parent 不变 
- `CLONE_THREAD`: 新旧 task 置于相同线程组
- `CLONE_PARENT_SETTID`: 向父进程指定的位置写入子进程的 TID
- `CLONE_CHILD_SETTID`: 向子进程指定的位置写入子进程的 TID
- `CLONE_CHILD_CLEAR_SIGHAND`: 在子进程退出时清空信号处理句柄

而 `wait` 支持全部四种 pid 的等待方式以及 `WNOHANG` 标志。四种 pid 的等待方式如下：

- `pid > 0` 时等待指定 pid 的进程
- `pid == 0` 时等待与当前进程的进程组 (process group) 的任意子进程
- `pid == -1` 时等待任意子进程
- `pid < -1` 时等待指定进程组的任意子进程。

目前 `wait` 的实现方式还是简单的 `yield_now` 实现，后续可能会改为使用异步方式实现。

=== 内存相关的系统调用

- `brk`
- `mmap` / `mprotect` / `munmap`
- `shmget` / `shmat` / `shmdt` / `shmctl`

其中 `mmap` 目前仅支持匿名映射 (`MMAP_ANONYMOUS`) 与文件映射 (`MMAP_PRIVATE`) 两种映射方式，但代码中已为支持共享映射 (`MMAP_SHARED`) 留下了合适的接口。`mprotect` 在修改映射区域权限时能够拆分已映射的段。

共享内存方面，`shmget` 支持 `IPC_CREAT`, `IPC_EXCL`, `IPC_PRIVATE` 三个 flag; `shmat` 支持只读映射; `shmctl` 则支持 `IPC_STAT`, `IPC_SET` 和 `IPC_RMID` 三个命令。

=== 信号相关的系统调用

- `sigwait`
- `sigaction`
- `sigreturn`
- `kill`

其中 `kill` 暂未支持 pid 小于 -1 的情况。

=== 时间相关的系统调用

- `times`
- `clock_gettime`
- `getimeofday`
- `nanosleep`
- `setitimer`

=== 杂项系统调用

- `uname`
- `sched_yield`

=== 空实现的系统调用

- `sync` / `fsync`
- `getuid` / `geteuid` / `getgid` / `getegid`
- `umask`
- `syslog`
- `madvise`
- `sigprocmask`

== 用户指针检查
#label("syscall-user-ptr")

在系统调用过程中，内核不可避免地会需要与用户进行数据交互，需要使用用户提供的指针进行数据读取或写入。出于性能考虑，MankorOS 直接使用用户指针作为数据缓冲区使用，避免进行多次数据复制，此时确保用户指针是 "安全" 的便尤为重要。

在初赛中，我们通过检查内核中维护的用户进程地址空间数据实现对用户指针的检查。这种做法虽然完全安全，但是由于需要频繁地进行地址空间数据的查找，导致系统调用的性能大幅下降。有没有办法加速该检查过程呢？我们参考了往届 FTL-OS 队伍的做法，借助硬件 TLB 的帮助实现了高效的用户指针检查。

该做法的基本思路是，先将内核的异常捕捉函数替换为 "用户检查模式" 下的函数，然后直接尝试向目标地址读取或写入一个字节。若是目标地址发生了缺页异常，则内核将表现得如同用户程序发生了一次异常一般，进入用户缺页异常处理程序进行处理。若处理成功或目标地址访问成功，便可假定当前整个页范围内都是合法的用户地址空间，否则用户指针便不合法。该处理方法相当于直接利用了硬件 TLB 来检查用户指针是否可读/可写, 在用户指针正常时速度极快，同时还能完全复用用户缺页异常处理的代码来处理用户指针懒加载/CoW 的情况，相比我们初赛的方法性能有了极大的提升。

在实现上，我们首先根据用户要求读取或写入的范围进行一次逐页扫描，确保每个页都是可读/可写状态，随后将其转换为 rust 的 slice 返回给内核其他部分 (对 C 风格字符串而言，可以通过 `String::from_raw_parts` 来免复制地转换为 `String` 对象). 为了更高效地在系统调用模块使用这些功能，我们结合 hart local 的 SUM 模式计数器，为 `UserPtr` 包装结构实现了 RAII 风格的自动 SUM 模式开启，充分地利用了 rust 提供的高等级抽象机制。
