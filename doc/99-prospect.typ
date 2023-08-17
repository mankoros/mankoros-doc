#import "../template.typ": img, tbl
= 总结与展望

== 初赛测评

于 2023-05-27 满分通过初赛所有测试用例，排行榜如 @leaderboard-pre 所示：

#img(
    image("../figure/leaderboard-pre.png"),
    caption: "初赛排行榜"
)<leaderboard-pre>


== 决赛第一阶段测试

于 2023-08-01 结束决赛第一阶段时，完成大部分功能测试，小部分性能测试的适配。
所属 VisionFive 2 赛道的排行榜如 @leaderboard-final1 所示：

#img(
    image("../figure/leaderboard-final1.png"),
    caption: "决赛第一阶段测试排行榜"
)<leaderboard-final1>

== 实现情况

初赛阶段各模块完成情况如 @table8-complete 所示：

#tbl(
    table(
        columns: (100pt, 350pt),
        inset: 10pt,
        stroke: 0.7pt,
        align: horizon,
        [模块], [完成情况],
        [无栈协程基建], [基于全局队列实现的调度器，可供异步程序执行],
        [内存管理], [实现 `mmap`/`munmap` 系统调用，可对所有内存段进行懒分配或懒加载，具备写时复制 (CoW) 功能],
        [文件系统], [完成全异步虚拟文件系统，支持 `devfs` 和管道],
        [进程管理], [支持 `clone` 系统调用，可以细粒度划分进程共享的资源],
        [信号机制], [完成基础的信号机制],
        [用户程序], [完成对 POSIX 系统调用的支持，支持 Busybox、Lua 等用户程序],
        [性能测试], [完成部分性能测试的适配]
    ),
    caption: "模块完成情况"
)<table8-complete>

决赛阶段各模块完成情况如 @table9-complete 所示：

#tbl(
    table(
        columns: (100pt, 350pt),
        inset: 10pt,
        stroke: 0.7pt,
        align: horizon,
        [模块], [完成情况],
        [无栈协程], [基于全局队列实现的调度器，完善的辅助 Future 支持，异步睡眠队列与事件总线],
        [内存管理], [支持 `mmap` 与 `shmget`，可对所有内存段进行懒分配或懒加载，具备写时复制 (CoW) 功能],
        [文件系统], [从块设备驱动到 FAT32 再到 VFS 的全链条异步文件系统，支持 tmpfs 与 procfs，支持异步管道],
        [进程管理], [统一的进程线程抽象，支持 `clone`，可以细粒度划分进程共享的资源],
        [信号机制], [支持用户自定义信号处理例程，有较为完善的信号系统，与内核其他异步设施无缝衔接],
        [用户程序], [能通过 `iozone` 与 `lua` 的全部测试，`busybox`/`libcbench`/`libctest` 的绝大部分测试，支持完善的用户指针检查]
    ),
    caption: "模块完成情况"
)<table9-complete>

== 未来工作

- 移植更多用户程序

