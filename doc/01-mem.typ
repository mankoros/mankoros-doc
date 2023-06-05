#import "../template.typ": img

= 内存管理

MankorOS 使用内核态与用户态共享的页表以避免在系统调用或时钟中断时冲刷
TLB，以提高性能。

== 内存空间布局

MankorOS 的虚拟内存空间主要分为两段：用户段和内核段。
用户段位于虚拟地址空间的低地址，内核段位于虚拟地址空间的高地址。根据
SV39 的规范，用户段 39 位以上均为 0，内核段 39 位以上均为 1。
其中，内核的链接基地址为 0xFFFFFFFF80200000，在链接脚本 linker.ld 中设置

具体的内存空间布局如下表：

TODO

== 内核动态内存分配器

为了使用 Rust
中的各种动态内存结构，需要在内核中实现一个动态内存的分配器。

MankorOS 的内核动态内存分配器使用了 Buddy allocator，来自 crate
`buddy_system_allocator`。

Buddy allocator 是操作系统中一种常用的物理页分配算法，它的主要原理是将可用的物理内存按照 2 的幂次方进行划分，每个划分成为一个“伙伴块”，并根据伙伴块的大小将它们组织成一棵二叉树。当需要分配一个指定大小的物理内存时，buddy
allocator 首先找到最小的 2
的幂次方大小的伙伴块，然后检查该伙伴块是否已经被分配出去。如果该伙伴块已经被分配出去，则继续寻找下一个伙伴块，直到找到空闲的伙伴块。

如果找到了一个空闲的伙伴块，那么就将该伙伴块标记为已分配，并把它从可用伙伴列表中移除。接着，将该伙伴块逐级向上合并，直到合并到大于等于分配请求大小的伙伴块为止。这样，最终的合并后的伙伴块就可以满足分配请求。如果在合并过程中发现其中某个伙伴块已经被分配出去，那么就停止合并，将剩余的子伙伴块重新加入可用伙伴列表中。

当需要释放已经分配出去的物理内存时，buddy allocator
会将该内存块标记为未分配并加入可用伙伴列表中。接着，它会检查该内存块所处的伙伴块是否也是未分配状态。如果该伙伴块的另一个子伙伴块也是未分配状态，那么就将这两个伙伴块合并成一个更大的伙伴块，并继续向上检查合并后的伙伴块是否可以再次和其它空闲伙伴块合并。

这样，通过不断地进行伙伴块的合并和分裂，buddy allocator
可以高效地管理可用的物理内存，避免了内存碎片化和空间浪费，提高了内存空间利用率和系统性能。

MankorOS 内核的初始化动态内存区位于一个`.bss`段的数据区，在物理内存页分配器未初始化好之前，能够提供有限的动态内存，满足初始化时内核的需求。

== 物理页分配器

内核还需要管理全部的空闲物理内存，MankorOS 为此使用了 bitmap
allocator，来自 rCore 的仓库
`https://github.com/rcore-os/bitmap-allocator`

Bitmap allocator
的主要原理是通过一个位图来管理一段连续的内存空间。这个位图中的每一位代表一块内存，如果该位为
0，说明对应的内存块空闲；如果该位为 1，说明对应的内存块已经被分配出去。

当需要分配一个指定大小的内存时，bitmap allocator
首先检查位图中是否有足够的连续空闲内存块可以满足分配请求。如果有，就将对应的位图标记为已分配，并返回该内存块的起始地址；如果没有，就返回空指针，表示分配失败。

当需要释放已经分配出去的内存时，bitmap allocator
将对应位图标记为未分配。这样，已经释放的内存块就可以被下一次分配请求使用了。

MankorOS 内核初始化时，会将所有内核未占用的物理内存加入物理页分配器。

== 页表管理

=== 启动阶段

简单起见，MankorOS
并没有实现内核搬运等功能，而是直接在编译时将内核直接链接到高地址空间。
这带来了一个问题，在未配置好地址翻译的时候，不能进入 Rust
执行，也就是需要在汇编语言尽快打开地址翻译。

MankorOS 设计了一个 boot 页表，嵌入在内核映像的.data 段

具体如下：

```
"   .section .data
    .align 12
_boot_page_table_sv39:
    # 0x00000000_00000000 -> 0x00000000 (1G, VRWXAD) for early console
    .quad (0x00000 << 10) | 0xcf
    .quad 0
    # 0x00000000_80000000 -> 0x80000000 (1G, VRWXAD)
    .quad (0x80000 << 10) | 0xcf
    .zero 8 * 507
    # 0xffffffff_80000000 -> 0x80000000 (1G, VRWXAD)
    .quad (0x80000 << 10) | 0xcf
    .quad 0
"
```

boot 页表使用了 huge page，直接将内核映像映射到正确的高位地址

=== 打开分页

使用汇编直接设置页表并打开修改地址翻译模式

```rs
unsafe extern "C" fn set_boot_pt(hartid: usize) {
    core::arch::asm!(
        "   la   t0, _boot_page_table_sv39
            srli t0, t0, 12
            li   t1, 8 << 60
            or   t0, t0, t1
            csrw satp, t0
            ret
        ",
        options(noreturn),
    )
}
```

内核初始化结束后，低地址空间中的映射将被删除，留给用户空间。

```rs
pub fn unmap_boot_seg() {
    let boot_pagetable = boot::boot_pagetable();
    boot_pagetable[0] = 0;
    boot_pagetable[2] = 0;
}
```

=== 页表的创建与回收

新建进程的页表时，我们一般希望内核区域的映射能够共享，因此，MankorOS 在新建用户进程的页表时，会直接复制 boot 页表的内核段。
由于 boot 页表没有用户段的映射，因此直接复制是安全的。

```rs
    pub fn new_with_kernel_seg() -> Self {
        // Allocate 1 page for the root page table
        let root_paddr: PhysAddr = Self::alloc_table();
        let boot_root_paddr: PhysAddr = boot::boot_pagetable_paddr().into();

        // Copy kernel segment
        unsafe { 
            root_paddr.as_mut_page_slice().
                copy_from_slice(boot_root_paddr.as_page_slice())
        }

        PageTable {
            root_paddr,
            intrm_tables: vec![root_paddr],
        }
    }
```

页表回收时，MankorOS 利用 Rust 的 RAII 机制实现了进程结束的内存自动回收，该页表管理所有它映射的物理内存，使用一个`Vec`保存。
当页表离开生命周期时，管理的物理内存将会被自动释放。

```rs
impl Drop for PageTable {
    fn drop(&mut self) {
        // shared kernel segment pagetable is not in intrm_tables
        // so no extra things should be done
        for frame in &self.intrm_tables {
            frame::dealloc_frame((*frame).into());
        }
    }
}
```

== 共享物理页管理

在操作系统中，共享页面管理是一个很重要的问题。
MankorOS 使用 Rust 的 Arc 类型来实现共享页面的关系

Arc 是一个智能指针类型，它允许多个所有权持有者拥有相同的数据。当最后一个所有权持有者离开作用域时，数据才会被释放。
这个特性可以帮助我们轻松地实现共享页面的管理。

MankorOS 中，进程结构体中的 `UserArea` 包含一个 Arc 类型，Arc 类型中的计数器表示当前有多少个进程正在使用该页面。当新的进程需要访问这个页面时，我们创建一个新的指向该结构体的智能指针，并将计数器加 1。当进程不再需要访问该页面时，我们只需将指向该结构体的智能指针的计数器减 1 即可。
当所有的持有者都离开了作用域后，这个页会被 `Drop` Trait 释放回给物理页面管理器。

== 缺页异常的处理

当发生缺页异常时，内核会在当前进程结构体中的 `UserSpace` 中查找对应的 `UserArea`，如果没有查找到合法的 `UserArea`，将会直接杀死进程。
如果通过了检查，就会调用物理页分配器进行分配，并将新分配的物理页与当前虚拟地址建立映射关系。

在建立映射关系时，MankorOS 同时支持写时复制 (Copy-on-Write,
COW) 策略，以避免不必要的物理页复制和浪费。
具体来说，当多个进程共享同一个物理页时，它们都使用相同的虚拟地址访问该物理页。如果其中任何一个进程试图对该物理页进行写操作，就会触发 COW 机制，将该物理页复制一份并重新映射到该进程的虚拟地址空间中，从而保证该进程可以独立地修改自己的副本而不影响其他进程。