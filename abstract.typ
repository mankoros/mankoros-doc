#import "template.typ": img, tbl

MankorOS 是 Rust 编写的基于 RISC-V 的多核异步宏内核操作系统。

于 2023-08-01 结束决赛第一阶段时，完成大部分功能测试，小部分性能测试的适配。
所属 VisionFive 2 赛道的排行榜如 @leaderboard-final1 所示：

#img(
    image("figure/leaderboard-final1.png"),
    caption: "决赛第一阶段测试排行榜"
)

下表为 MankorOS 各模块的完成情况：

#tbl(
    table(
        columns: (100pt, 350pt),
        inset: 10pt,
        stroke: 0.7pt,
        align: horizon,
        [模块], [完成情况],
        [无栈协程基建], [基于全局队列实现的调度器, 可供异步程序执行],
        [内存管理], [实现 `mmap`/`munmap` 系统调用, 可对所有内存段进行懒分配或懒加载, 具备写时复制 (CoW) 功能],
        [文件系统], [完成全异步虚拟文件系统, 支持 `devfs` 和管道],
        [进程管理], [支持 `clone` 系统调用, 可以细粒度划分进程共享的资源],
        [信号机制], [完成基础的信号机制],
        [用户程序], [完成对 POSIX 系统调用的支持，支持 Busybox、Lua 等用户程序],
        [性能测试], [完成部分性能测试的适配]
    ),
    caption: "模块完成情况"
)
