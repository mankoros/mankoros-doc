#import "../template.typ": img
= 概述

== MankorOS 介绍

MankorOS 是 Rust 编写的基于 RISC-V 的多核异步宏内核操作系统，使用了以 `Future` 抽象为代表的无栈协程异步模型，提供统一的线程和进程表示，细粒度的资源共享以及段式地址空间管理，拥有虚拟文件系统和设备文件系统。

在开发过程中，MankorOS 注重代码质量和规范性，确保每次 commit 都有意义的 commit message，并能够通过编译。
这种严格的开发流程使 MankorOS 有高质量的代码，还可以减少 bug 的产生，从而提高项目的稳定性。

为了优化编译的效率，MankorOS 采用了 monorepo 的组织方式。
这种方式将所有相关的代码和库都放在同一个仓库中，避免了不同组件之间的版本冲突和依赖问题。
这种方式还可以提高代码的可读性和可维护性，可供教学或交流学习。

未来，MankorOS 将会在不牺牲性能的前提下，继续维持高质量的代码，目标成为一个高性能、易学习的操作系统。

== MankorOS 整体架构

```
.
├── src
│  ├── arch         # 汇编与平台相关的包装函数
│  ├── axerrno      # 错误处理
│  ├── consts       # 常量
│  │  └── platform
│  ├── driver       # 驱动，包括块设备和 uart 驱动
│  ├── executor     # 管理 future 执行
│  ├── fs           # 文件系统
│  │  ├── devfs     # 设备文件系统
│  │  └── vfs       # 虚拟文件系统
│  ├── memory       # 内存
│  │  ├── address   # 地址类型
│  │  └── pagetable # 页表
│  ├── process      # 进程
│  │  └── user_space
│  ├── signal       # 信号
│  ├── sync         # 同步，一致性、锁和进程通讯
│  ├── syscall      # POSIX 系统调用
│  ├── timer        # 时钟，时钟中断管理和计时器
│  ├── tools        # 工具类型和函数
│  ├── trap         # 中断
│  ├── xdebug       # debug 工具
│  ├── boot.rs      # 启动
│  ├── lazy_init.rs # 懒加载
│  ├── logging.rs   # 日志
│  ├── main.rs      
│  └── utils.rs
├── vendor
├── Cargo.toml
├── LICENSE
├── linker.ld
├── Makefile
├── README.md
└── rust-toolchain.toml
```

== MankorOS 项目结构

#img(
    image("../figure/Arch.jpg", width: 80%),
    caption: "MankorOS 系统结构图"
)