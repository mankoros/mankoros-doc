= 系统调用
#label("syscall")

== 支持的系统调用列表与详细信息
#label("syscall-list")

=== IO 与文件描述符相关系统调用

创建与关闭文件描述符：

- `openat`
- `close`
- `pipe2`
- `dup` / `dup3`
- `fcntl`

读取与写入：

- `read` / `readv` / `pread` / `preadv`
- `write` / `writev` / `pwrite` / `pwritev`
- `lseek`
- `ppoll`
- `pselect`
- `ioctl`

=== 文件系统相关系统调用

读取文件元信息/文件夹/文件系统元信息：

- `fstat(at)`
- `getdents`
- `statfs`
- `faccessat`
- `readlinkat`

创建与删除文件：

- `unlinkat`
- `mkdir`
- `mount` / `umount`

修改文件元信息：

- `fturncate`
- `utimensat`
- `renameat2`

=== 进程相关的系统调用

读取与修改进程信息：

- `getpid` / `gettid` / `getppid` 
- `getpgid` / `setpgid`
- `set_tid_address`
- `getcwd` / `chdir`
- `getrlimit` / `prlimit`

进程的创建、退出与多进程管理：

- `clone`
- `execve`
- `exit` / `exit_group`
- `wait`

=== 内存相关的系统调用

堆管理与内存映射：

- `brk`
- `mmap` 
- `mprotect`
- `munmap`

共享内存管理：

- `shmget`
- `shmat`
- `shmdt` 
- `shmctl`

=== 信号相关的系统调用

- `sigwait`
- `sigaction`
- `sigreturn`
- `kill`

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
