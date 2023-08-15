#import "../template.typ": img

= 物理内存管理

== 内核动态内存分配器

为了使用 Rust 中的各种动态内存结构，需要在内核中实现一个动态内存的分配器。MankorOS 的内核动态内存分配器使用了 Buddy allocator，它来自 crate `buddy_system_allocator`。

Buddy allocator 是操作系统中一种常用的物理页分配算法，它的主要原理是将可用的物理内存按照 2 的幂次方进行划分，每个划分成为一个“伙伴块”，并根据伙伴块的大小将它们组织成一棵二叉树。当需要分配一个指定大小的物理内存时，buddy allocator 首先找到最小的二的幂次方大小的伙伴块，然后检查该伙伴块是否已经被分配出去。如果该伙伴块已经被分配出去，则继续寻找下一个伙伴块，直到找到空闲的伙伴块。如果找到了一个空闲的伙伴块，那么就将该伙伴块标记为已分配，并把它从可用伙伴列表中移除。接着，将该伙伴块逐级向上合并，直到合并到大于等于分配请求大小的伙伴块为止。这样，最终的合并后的伙伴块就可以满足分配请求。如果在合并过程中发现其中某个伙伴块已经被分配出去，那么就停止合并，将剩余的子伙伴块重新加入可用伙伴列表中。

当需要释放已经分配出去的物理内存时，buddy allocator 会将该内存块标记为未分配并加入可用伙伴列表中。接着，它会检查该内存块所处的伙伴块是否也是未分配状态。如果该伙伴块的另一个子伙伴块也是未分配状态，那么就将这两个伙伴块合并成一个更大的伙伴块，并继续向上检查合并后的伙伴块是否可以再次和其它空闲伙伴块合并。

这样，通过不断地进行伙伴块的合并和分裂，buddy allocator 可以高效地管理可用的物理内存，避免了内存碎片化和空间浪费，提高了内存空间利用率和系统性能。

MankorOS 内核的初始化动态内存区位于一个 `.bss` 段的数据区，在物理内存页分配器未初始化好之前，能够提供有限的动态内存，满足初始化时内核的需求。

== 物理页分配器

内核还需要管理全部的空闲物理内存，MankorOS 为此使用了 #link("https://github.com/rcore-os/bitmap-allocator", "来自 rCore 的仓库的 bitmap allocator").

Bitmap allocator 的主要原理是通过一个位图来管理一段连续的内存空间。这个位图中的每一位代表一块内存，如果该位为 0，说明对应的内存块空闲；如果该位为 1，说明对应的内存块已经被分配出去。当需要分配一个指定大小的内存时，bitmap allocator 首先检查位图中是否有足够的连续空闲内存块可以满足分配请求。如果有，就将对应的位图标记为已分配，并返回该内存块的起始地址；如果没有，就返回空指针，表示分配失败。当需要释放已经分配出去的内存时，bitmap allocator 将对应位图标记为未分配。这样，已经释放的内存块就可以被下一次分配请求使用了。

MankorOS 内核初始化时，会将所有内核未占用的物理内存加入物理页分配器。

== 页表管理

=== 启动阶段

简单起见，MankorOS 并没有实现内核搬运等功能，而是直接在编译时将内核直接链接到高地址空间。这带来了一个问题，在未配置好地址翻译的时候，不能进入 Rust 执行，也就是需要在汇编语言尽快打开地址翻译。

MankorOS 设计了一个 boot 页表，嵌入在内核映像的 `.data` 段，具体如下：

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

boot 页表使用了 huge page，直接将内核映像映射到正确的高位地址。

=== 打开分页

使用汇编直接设置页表并打开修改地址翻译模式：

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

内核初始化结束后，低地址空间中的映射将被删除，留给用户程序使用。

```rs
pub fn unmap_boot_seg() {
    let boot_pagetable = boot::boot_pagetable();
    boot_pagetable[0] = 0;
    boot_pagetable[2] = 0;
}
```

=== 页表的创建与回收

新建进程的页表时，我们一般希望内核区域的映射能够共享。因此，MankorOS 在新建用户进程的页表时，会直接复制 boot 页表的内核段。由于 boot 页表没有用户段的映射，因此直接复制是安全的。

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

页表回收时，MankorOS 利用 Rust 的 RAII 机制实现了进程结束的内存自动回收。该页表使用一个 `Vec` 保存所有它映射的物理内存页，当页表离开生命周期时，对应的物理页将会被自动释放 (返还给物理页分配器)。

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

// TODO：内核地址转换
// TODO：内核页表共享

== 地址类型系统设计

在内核开发过程中，我们需要处理各种各样的地址，比如虚拟内存中的地址、物理地址、4K 对齐的地址，页号等等等等。对于不同类型的地址，我们期望它们应该支持不同类型的操作，并且不会被混用。为此，我们在开发前期，便参考了往届诸多队伍的设计，利用 rust 提供的便利的抽象机制，打造了一套方便的地址类型系统。

// TODO：需要一张图

从实现上讲，每一种地址都有相同的底层二进制表示 (`usize`). 借助 rust 的 struct，我们能简单地为这些相同的底层表示构建不同的类型，从而在编译期便能捕捉到许多 bug，充分地利用了 rustc 带来的强大的编译期检查能力，也提升了 API 的可读性，加快了开发速度。   

== 物理内存引用计数

在决赛阶段，MankorOS 换掉了初赛时使用的简单粗暴的全局 BTreeMap 物理页引用计数系统，转而使用类似于 Linux 的机制，分配一个巨大的 u32 数组，将物理内存页按页号一一对应到数组中的元素，随后使用原子访问/修改去更新对应的计数。该新系统极大地减少了多核中物理页共享计数更新的锁竞争，同时也加快了更新物理页引用计数的速度。显然，对于物理页引用计数这种被高强度使用的操作而言，任何一点点优化带来的提升都是巨大的。同时，借助物理页引用计数系统，我们还能检测内核中无意引入的各种奇特的 bug。

不过，在我们开发该系统的过程中，也遇到了一些令人哭笑不得的 bug：当时我们采用的 rustc nightly 版本是 2023-01-xx，我们的内核在该版本下使用 debug 模式编译一切正常，但是使用 release 模式编译后，我们的内核就会开始胡乱修改用户内存。经过若干日的调试之后，终于，我们发现，当我们切换到 rustc nightly 2023-02-yy 版本后，问题就消失了。经过这次调试，我们深刻地认识到了现代计算机工具链的复杂性，对复杂软件的开发过程有了新的认识。