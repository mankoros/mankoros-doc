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

当前各模块完成情况如 @table8-complete 所示：

#tbl(
    table(
        columns: (100pt, 350pt),
        inset: 10pt,
        stroke: 0.7pt,
        align: horizon,
        [模块], [完成情况],
        [无栈协程基建], [基于全局队列实现的调度器，可供异步程序执行],
        [内存管理], [实现 `mmap`/`munmap` 系统调用，可对所有内存段进行懒分配或懒加载，具备写时复制 (CoW) 功能],
        [文件系统], [完成虚拟文件系统，支持 `devfs` 和管道],
        [进程管理], [支持 `clone` 系统调用，可以细粒度划分进程共享的资源],
        [信号机制], [完成基础的信号机制],
        [用户程序], [能通过所有初赛测试样例]
    ),
    caption: "模块完成情况"
)<table8-complete>

== 未来工作

- 使内核更加异步化，支持异步内存复制和文件 IO, 实现异步文件系统
- 完善进程信号传递机制，实现基于事件总线的进程通讯机制
- 支持动态链接
- 支持 `proc` 文件系统
- 支持 musl libc 和 busybox, 移植更多用户程序

