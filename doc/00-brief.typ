#import "../template.typ": img
= 概述

== MankorOS 介绍

MankorOS 是 Rust 编写的基于 RISC-V 的多核异步宏内核操作系统，使用了以 `Future` 抽象为代表的无栈协程异步模型，提供统一的线程和进程表示，细粒度的资源共享以及段式地址空间管理，拥有虚拟文件系统和设备文件系统。

我们不但注重代码质量，更注重开发过程的规范，尽力确保每一次 commit 都有有意义的 commit message 且可编译。项目采用 monorepo 的组织方式，有利于编译优化。

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