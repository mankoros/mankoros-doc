#import "../template.typ": img

= 进程设计

MankorOS 支持进程和线程，
进程和线程都是用轻量级线程 (`LightProcess`) 结构统一表示。
在本章中，将先后介绍：

-  `LightProcess` 结构体
-  用户地址空间管理
-  进程调度

== 进程和线程

与 Linux 内核相似，在 MankorOS 内核中，
进程和线程两者并没有区别，可以统一地称之为轻量级进程，以`LightProcess` 结构体表示和管理。
线程可以理解为在 `sys_clone` 系统调用时指定了共享资源的进程 (包括地址空间、文件描述符表、待处理信号等)。
线程模型的具体定义可以由用户库负责。

=== `LightProcess` 结构体

目前 `LightProcess` 结构体主要包含以下数据结构 
(其中 #strong[粗体] 的是可以在任务之间共享的)

-  进程基本信息
  -  进程号 `id`
  -  进程状态 `state`
  -  退出码 `exit_code`
-  进程关系信息
  -  父进程 `parent`
  -  #strong[子进程数组 `children`]
  -  #strong[进程组信息 `group`] (用于实现线程组)
-  进程资源信息
  -  #strong[地址空间 `memory`]
  -  #strong[文件系统信息 `fsinfo`]
  -  #strong[文件描述符表 `fdtable`]
-  其他
  -  #strong[信号处理函数 `signal`]

`LightProcess` 代码如下所示：

```rust
type Shared<T> = Arc<SpinNoIrqLock<T>>;

pub struct LightProcess {
    id: PidHandler,
    parent: Shared<Option<Weak<LightProcess>>>,
    context: SyncUnsafeCell<Box<UKContext, Global>>,

    children: Arc<SpinNoIrqLock<Vec<Arc<LightProcess>>>>,
    status: SpinNoIrqLock<SyncUnsafeCell<ProcessStatus>>,
    exit_code: AtomicI32,

    group: Shared<ThreadGroup>,
    memory: Shared<UserSpace>,
    fsinfo: Shared<FsInfo>,
    fdtable: Shared<FdTable>,
    signal: SpinNoIrqLock<signal::SignalSet>,
}
```

在内核代码中，其他部分一般持有 `Arc<LightProcess>` (`LightProcess`的引用计数智能指针). 
这样既可以保证对应进程的信息不会过早被释放，
也可以保证当无人持有此进程信息时，此结构体占用的资源可以被回收。
`LightProcess` 中可以共享的数据结构都用 `Arc` 包装，
在 `sys_clone`系统调用的实现中，
如果需要共享特定资源，
则可以直接利用 `Arc::clone`方法使得两个进程的数据结构指向同一个实例; 
如果无需共享，则使用具体资源的`clone` 的方法进行复制：

```rust
// src/process/lproc.rs:265 
if flags.contains(CloneFlags::THREAD) {
    parent = self.parent.clone();
    children = self.children.clone();
    // remember to add the new lproc to group please!
    group = self.group.clone();
} else {
    parent = new_shared(Some(Arc::downgrade(&self)));
    children = new_shared(Vec::new());
    group = new_shared(ThreadGroup::new_empty());
}
```

=== 进程的状态

在 MankorOS 中，进程有 3 种状态：

-  `UNINIT`: 该进程还未针对第一次运行做好准备 (没有为 `main`
  函数准备好栈上的内容)
-  `READY`: 该进程可以被执行
-  `ZOMBIE`: 已经退出的进程

在异步内核中，
不需要维护进程是否被阻塞之类或是否已经被加入准备执行的队列的状态：

-  若进程执行某个耗时久的系统调用 (比如 `sleep`), 
  代表它的 `Future` 会直接返回 Pending, 从而使它离开调度队列;
  直到阻塞的条件被满足后，它会被 waker 自动重新加入回调度队列。
  因此不需要代表 "进程因为缺少某条件不能被调度" 的状态。
-  异步编程模型中的 `Task` 抽象会保证一个 `Future` 不会被 wake 多次，
  从而使得已经在调度队列中的进程不会被重复加入。
  因此不需要代表 "进程已经被调度" 的状态

== 地址空间

出于性能考虑，MankorOS 的内核与用户程序共用页表，
且内核空间占用的二级页表在不同用户程序之间是共享的。

=== 地址空间布局

用户地址空间布局如下图所示：

#img(
    image("../figure/Address_Layout.jpg"),
    caption: "地址空间"
)<img:address_layout>

=== 地址空间管理

MankorOS 中的地址空间的各类信息由 `UserSpace` 结构体表示：

```rust
pub struct UserSpace {
    // 根页表
    pub page_table: PageTable,
    // 分段管理
    areas: UserAreaManager,
}
```

其中 `UserAreaManager` 结构体用于管理用户程序的各个段，其组成非常简单：

```rust
pub struct UserAreaManager {
    map: RangeMap<VirtAddr, UserArea>,    
}

pub struct RangeMap<U: Ord + Copy, V>(BTreeMap<U, Node<U, V>>);
```

`RangeMap` 的实现直接借用了 #link("https://gitee.com/ftl-os/ftl-os/blob/master/code/kernel/src/tools/container/range_map.rs")[FTL-OS] 的实现。
但额外增加了原地修改区间长度的 `extend_back` 和 `reduce_back` 方法，
以针对堆内存的动态增长和缩减进行优化。
对于其他类型的区间长度增减，
仍然采用 "创建新区间 - 合并" 和 "分裂旧区间 - 删除" 的方式。

`UserArea` 中保存了各个内存段的信息，包括：

```rust
bitflags! {
    pub struct UserAreaPerm: u8 {
        const READ = 1 << 0;
        const WRITE = 1 << 1;
        const EXECUTE = 1 << 2;
    }
}

enum UserAreaType {
    /// 匿名映射区域
    MmapAnonymous,
    /// 私有映射区域
    MmapPrivate {
        file: Arc<dyn VfsNode>,
        offset: usize,
    },
    // TODO: 共享映射区域
    // MmapShared {
    //     file: Arc<dyn VfsNode>,
    //     offset: usize,
    // },
}

pub struct UserArea {
    kind: UserAreaType,
    perm: UserAreaPerm,
}
```

考虑到地址空间段的类型是基本确定的，
此处并没有像 Linux 一样使用函数指针 ("虚表") 来抽象各类段的行为，
也没有使用本质上相同的 Rust 的 `dyn trait`方式，
而是直接使用枚举类型实现。
这样既可以保证处理时的完整地好各类情况，也有一定的性能优势。

MankorOS 中所有段都是懒映射且懒加载的，
所有内存数据都会且只会在处理缺页异常时被请求 (譬如换入页或读取文件信息).
这同时也带来了 `exec` 系统调用中对 ELF 文件的懒加载能力。

该实现还意味着各种不同类型的段只需要在构造或处理缺页异常时进行不同的处理即可。
所有 `UserArea` 方法中只有缺页异常处理需要针对不同的段类型进行不同的处理，
使得使用枚举区分不同段的方法带来了几乎为零的代码清晰程度开销。
正因如此，我们放弃了虚表方法可能带来的代码清晰度的提升与灵活性，
而选择了性能更好的枚举实现。

=== 缺页异常处理与 CoW

当 `userloop` 中检测到用户程序因为缺页异常而返回内核时，
会从 `stval` 寄存器中读出发生缺页异常的地址，
在经过一些包装函数后，会来到 `UserArea::page_fault` 函数中：

```rust
// src/process/user_space/user_space.rs:193
pub fn page_fault(
    &self,
    page_table: &mut PageTable,
    range_begin: VirtAddr, // Allow unaligned mmap ?
    access_vpn: VirtPageNum,
    access_type: PageFaultAccessType,
) -> Result<(), PageFaultErr> {
    if !access_type.can_access(self.perm()) {
        // 权限检查，如果访问权限不符合要求，则直接返回错误
        // 此处"权限" 检查匹配的是 UserArea 中保存的，该区域应有的权限
        // 而非页表中的权限 (页表中的权限会因为 CoW/懒加载 等改变)
        return Err(PageFaultErr::PermUnmatch);
    }

    // 分配新物理页
    let frame = alloc_frame()
        .ok_or(PageFaultErr::KernelOOM)?;
    // 遍历页表找到发生缺页异常的页的页表项
    let pte = page_table.get_pte_copied_from_vpn(access_vpn);
    if let Some(pte) = pte && pte.is_valid() {
        // 如果权限正确，且页表有效，那么是因为 CoW 引起的缺页异常
        // 因为 CoW 会将原来的页表项可写的页的权限设置为只读，而此处发生了真实的写入
        let pte_flags = pte.flags();
        // 减少旧物理页的引用计数
        let old_frame = pte.paddr();
        with_shared_frame_mgr(|mgr| mgr.remove_ref(old_frame.into()));
        // 复制旧物理页的内容到新物理页
        unsafe {
            frame.as_mut_page_slice()
                .copy_from_slice(old_frame.as_page_slice());
        }
    } else {
        // 如果页表项无效，说明是懒加载
        match &self.kind {
            // 对匿名映射的段，懒加载并不需要向其写入任何数据
            UserAreaType::MmapAnonymous => {}
            // 对私有文件映射的段，懒加载需要去文件中读取对应范围内的数据
            UserAreaType::MmapPrivate { file, offset } => {
                let access_vaddr: VirtAddr = access_vpn.into();
                let real_offset = offset + (access_vaddr - range_begin);
                let slice = unsafe { frame.as_mut_page_slice() };
                let _read_length = 
                    file.sync_read_at(real_offset as u64, slice)
                    .expect("read file failed");
            }
        }
    }

    // 修改页表项
    page_table.map_page(access_vpn.into(), frame, self.perm().into());
    Ok(())
}
```

当地址空间发生 CoW 复制时，我们一项项遍历原来的页表项，
将其修改为只读且将其映射的物理页的使用计数加一：

```rust
// src/process/user_space/mod.rs:260
pub fn clone_cow(&mut self) -> Self {
    Self {
        page_table: self.page_table.copy_table_and_mark_self_cow(|frame_paddr|{
            with_shared_frame_mgr(|mgr| mgr.add_ref(frame_paddr.into()));
        }),
        areas: self.areas.clone(),
    }
}
```

== 进程调度 <process_sch>
#let process_sch = <process_sch>

MankorOS 是异步内核，其进程调度与同步内核有所不同。
显著的一个特点是在内核中并不需要维护一个保存了所有进程信息的数组，
而是使 `Arc<LightProcess>` 分散在内核内存中的各个 `Future` 中，
直到 waker 将其 "唤醒", 调度器才能知晓该进程的存在。

目前 MankorOS 中的进程调度器是一个简单的 FIFO 调度器，
其内部维护了一个双端队列，
依次从队列头部取出包含待调度进程的 `Future` 并执行。
当用户程序因为时间片用完而返回内核时，
放弃该轮执行并被重新加入调度队列的尾部。
当用户程序因为系统调用而返回内核，并且该系统调用会 "阻塞" 时，
它会返回一个 `Pending` 状态，直到等待到阻塞条件满足后被 waker 唤醒。
换而言之，异步内核中没有 "阻塞" 的概念，
一切操作要么马上结束，要么放弃执行等待回调。

MankorOS 下一步预计引入更加复杂的调度算法，
比如为每个 CPU 核心维护一个优先级队列以更好地利用缓存。
这可以通过在生成代表进程的 `Future` 时，向其传入不同的函数来实现。
具体而言便是修改此处的实现，将 `|runnable| TASK_QUEUE.push(runnable)` 
改为更复杂的 "使不同的调度器知晓自身存在" 的操作即可。

```rust
// src/executor/mod.rs:25
pub fn spawn<F>(future: F) -> (Runnable, Task<F::Output>)
where
    F: Future + Send + 'static,
    F::Output: Send + 'static,
{
    async_task::spawn(future, |runnable| TASK_QUEUE.push(runnable))
}
```