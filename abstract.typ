#import "template.typ": img, tbl

MankorOS 是 Rust 编写的基于 RISC-V 的多核异步宏内核操作系统。

于 2023-08-01 结束决赛第一阶段时，完成大部分功能测试，小部分性能测试的适配。
所属 VisionFive 2 赛道的排行榜如 @leaderboard 所示：

#img(
    image("figure/leaderboard-final1.png"),
    caption: "决赛第一阶段测试排行榜"
)<leaderboard>

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
        [进程管理], [统一的进程线程抽象，可以细粒度划分进程共享的资源],
        [信号机制], [支持用户自定义信号处理例程，有较为完善的信号系统，与内核其他异步设施无缝衔接],
        [用户程序], [能通过 `iozone` 与 `lua` 的全部测试，`busybox`/`libcbench`/`libctest` 的绝大部分测试，支持完善的用户指针检查]
    ),
    caption: "模块完成情况"
)
