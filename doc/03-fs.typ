= 文件系统
#label("fs")

== VFS 设计与结构
#label("fs-vfs")

VFS（Virtual File System）是 OS 中具体文件系统之上，内核其他部分之下的一层抽象层。它的存在使内核其他部分能隔离不同底层文件的区别，为 Unix 的著名隐喻 "万物皆文件" 提供了实现上的可能。同时，在此层还能实现许多与具体文件系统无关的优化，比如页缓存与文件共享页管理，路径缓存等，增加了代码复用。MankorOS 自然也采用了 VFS 层的设计。

在 MankorOS 中，VFS 层主要包含如下内容：

- 一层面向内核其他部分的异步文件接口
- 页缓存与映射管理，路径缓存，文件属性管理与同步等通用优化
- 一层面向底层 FS 的抽象接口

通用优化部分使用泛型实现，为底层文件系统的实现者提供了可复用的通用优化代码。底层 FS 若想要使用对应的优化，只需要在返回 root 文件时插入具体优化结构的构造函数即可。对于 tmpfs 与 procfs 等特殊文件系统，它们则可以直接忽略这些优化，直接实现 VFS 顶层的文件接口，减少了不必要的性能开销。

== 非具体文件系统
#label("fs-non-concrete")

在 MankorOS 中，非具体文件系统用于指代所有不需要从磁盘上读取数据的文件系统，包括 procfs, devfs, tmpfs 等。这些文件系统的数据或是从不落盘，或是按需从内核中查询。由于其无需与磁盘交互，因此它们不需要经过常见的为了提高磁盘访问效率而使用的缓存机制，可以直接实现 VFS 顶层的文件接口，从而减少不必要的性能开销。

=== procfs
#label("fs-nc-procfs")

procfs 是一种特殊的文件系统，它不是从磁盘上的文件系统中读取数据，而是从内核中读取数据。MankorOS 实现了部分 linux 中 procfs 的功能，包括：

- `/proc/mounts`: 显示当前挂载的文件系统
- `/proc/<pid>`: 显示对应 pid 进程的信息
- `/proc/self`: 显示当前进程的信息

=== devfs
#label("fs-nc-devfs")

devfs 中的文件代表一些具体的设备，比如终端、硬盘等。MankorOS 的 /dev 内包含：

- `/dev/zero`: 一个无限长的全 0 文件
- `/dev/tty`: 终端设备，能支持 ioctl 中的特定命令

=== tmpfs
#label("fs-nc-tmpfs")

tmpfs 中的一切文件与文件夹都仅仅存活于内存中，在系统重启时被清空。MankorOS 的 `/tmp` 支持创建文件夹、文件、符号链接等普通文件系统的操作，从而支持了 libc 中各类创建临时文件的函数。

== 具体文件系统无关优化
#label("fs-concrete-opt")

在 MankorOS 中，具体文件系统是指那些真实存在于磁盘之上的文件系统。为了提高代码复用效率，减少单模块代码量，在 MankorOS 中，路径缓存与页缓存等通用优化被实现为泛型，其与底层的具体文件系统只通过定义明确的接口交互，从而使得具体文件系统的实现者可以在不需要关心通用优化的情况下，专注于实现具体文件系统的功能。

=== 路径缓存
#label("fs-opt-path-cache")

路径缓存模块在内存中维护真实文件路径树的常用部分，使得用户在路径之间跳转时，得以快速找到对应的文件节点。同时，路径缓存模块也确保了对相同的从文件系统根部开始的路径的重复访问不会导致重复的文件系统操作，也不会找到不同的文件节点，从而保证了文件读写操作的一致性与正确性。

在 Linux 中，"路径缓存" 实则是 "目录项" 的缓存。文件系统中从各个目录读出的 `dentry` 结构体被放置于一张全局哈希表中，使用该目录项名词与文件夹 INode 编号来作为哈希表的键。同一个目录的 DEntry 同时还被侵入式链表相链，以支持目录遍历操作。

在 MankorOS 中，得益于 rust 的高层次描述与丰富的 no-std 标准库，我们选择了直接针对每个目录维护独立的 BTreeMap 来实现路径缓存。这样的实现方式非常简单直观且易于维护，并且在性能上也不会有太大的损失。同时，由于路径缓存保证了每个具体文件系统中的目录最多同时只有一个 VFS 中的文件对象与其对应，我们可以确保所有对该目录的修改操作都会经过同一个对象，从而确保我们的缓存系统能检测到每一次更改。我们在每一个目录中维护了一个当前缓存是否完全的 flag, 借此便可以 (在缓存完全的情况下) 高效地判定一个文件是否存在，而无需在缓存查找失败时再次向底层文件系统发出查询。

=== 页缓存与文件共享页管理
#label("fs-opt-page-cache")

页缓存指的是将整个文件按页大小 (`PAGE_SIZE`) 切分维护，从而为上层的文件映射 (mmap private/shared) 提供高效支持的机制。页缓存可以确保每一张共享映射的页在内存中都是同一张，从而保证共享页的唯一性。同时，将文件按页维护切分维护也能方便地进行整页的 IO 读写操作，从而提高 IO 效率。页缓存对于异步内核而言，在实现文件异步读写时也具有重要意义：它可以将 "读取文件" 的操作分离为 "向底层文件系统发出请求，等待其将数据写到页中" 与 "从缓存页中复制数据到外界缓冲区" 两次操作，前者为异步操作，后者则可实现为同步操作，这极大地便利了 poll/select 等多路转发机制的实现，在 poll 具体文件时提升 IO 吞吐量 (只有数据立即在内存之中的文件才会返回 poll ready, 需要进行耗时的磁盘访问的文件则不会 ready), 并且可以在等待磁盘 IO 时切换当前 hart 到其他任务上。

== 异步 FAT32 文件系统
#label("fs-fat32")

为了更好地与 MankorOS 的异步系统集成，在决赛第一阶段我们抛弃了初赛中使用的第三方同步 fat32 文件系统，代之以自己实现的异步 fat32 系统。它依赖于我们底层的异步块设备接口，能直接与我们的异步 SD 卡驱动对接，从而实现真正的异步文件 IO.

由于 `fat(32)` 这个名称的多义性，我们规定下文提到的小写带数字的 `fat32` 一词用于指代文件系统本身，而全大写的 `FAT` 用于指代 fat32 中的文件关联表 (File Association Table).

=== 异步块设备接口
#label("fs-fat32-block-device")

```rust 
pub trait AsyncBlockDevice: Device + Debug {
    fn num_blocks(&self) -> u64;
    fn block_size(&self) -> usize;

    fn read_block(&self, block_id: u64, buf: &mut [u8]) -> ADevResult;
    fn write_block(&self, block_id: u64, buf: &[u8]) -> ADevResult;
    fn flush(&self) -> ADevResult;
}
```

=== 块缓存系统

对 fat32 而言，块缓存的存在除了用于提高文件读写性能之外，更重要的是能优化文件元信息的读取与写入。由于 fat32 文件系统将文件的元信息存储在其上层文件夹的 DEntry 中，而不是存储于独立或者于文件绑定的独立的块中。这就导致可能有多个文件的元信息位于同一个底层块中。倘若不加缓存，在对同目录下不同的文件分别更新元信息时，便会造成同一个块的多次读取与写入，这无疑是非常浪费的。

要解决上述问题，要么通过某种方式关联起同目录下的所有文件，规定文件的元信息属于目录且只能通过目录文件对象读写；要么就引入块缓存，使得对同一个块的多次访问可以被累积，随后一同写入。为了更好地支持 unix 风格的系统调用，我们选择在 fat32 层次便模拟出元信息跟随文件的“假象”，在 VFS 层使用此假定。于是便不再方便使得每一个 fat32 文件关联起一个文件夹，最终我们选择了块缓存的方式来统一地维护文件元信息的读写。

由于在 VFS 层中，MankorOS 已经有了页缓存机制，所以对于文件的读写，块缓存系统将被绕过以防止缓存同样的内容两次。在当前版本中，只有 FAT 和包含非 LFN Entry 的文件夹的块才会进入块缓存系统。同时，块缓存系统还具有 rust 风格的脏检测机制，通过合理的 API 设计，用户每次获得块的可变引用都将标记块的 dirty flag，从而确保了数据安全。

=== 文件系统信息与 FAT
#label("fs-fat32-info")

从文件系统装载、读取超级块开始，MankorOS 的 fat32 就是异步的。由于 FAT 的大小相对可控（1bit 便能对应一整个 cluster，即使磁盘很大，FAT 的大小也相对较小），我们将整个 FAT 表维护于内存之中。

为了减少单模块代码量，我们并没有在 FAT 模块中维护太多优化相关的信息，而仅仅将其作为 FAT 的一个简单包装。这并不意味着我们没有针对 FAT 做优化 —— 每个文件的 cluster 链实际上会被缓存在文件中，而非统一缓存在 FAT 中。

FAT 模块主要提供对下一个 cluster 的搜寻、对空闲块的查找等功能。

=== 文件与文件元信息的维护
#label("fs-fat32-file-meta")

由于上层 VFS 提供的页缓存机制，文件内容的读写并不需要经过块缓存系统。但是文件元信息要如何维护呢？我们选择了跟随文件记录其代表的 Standard 8.3 dentry 的块号与块内偏移量，同时为了加快查询速度，在文件对象创建时我们会直接将一个完整的 8.3 dentry 加入到文件中，只有在文件对象被释放，并且该 8.3 dentry 脏，才会修改块缓存中对应的数据。这种做法使得块缓存得以免于存放整个 8.3 dentry 所在的块（它之中可能包含许多“无用”的 LFN），同时又保证了对文件元信息操作的速度。

由于 VFS 中已经包含了对并行文件读写串行化的锁实现，因此在 fat32 中，我们并没有在文件与块缓存的块中加入任何的锁机制（当然，对各个模块本身的信息的读写都还是要上锁以考虑并行安全性的），而是选择相信上层的串行化机制会确保不会重入不该重入的函数。

=== 文件夹
#label("fs-fat32-dir")

Fat32 的文件夹逻辑上可以视为一个巨大的，每个元素 32 byte 长的 entry 数组，其中每个 entry 可以是：

- Empty entry
- Unused entry
- Standard 8.3 entry (STD / 8.3)
- Long file name entry (LFN)

其中 empty entry 的首字节为 0，只会出现在文件夹的末尾，指示文件夹的结束。Unused entry 可能随机出现在文件夹的中间，是被删除了的文件在文件夹中留下的 "洞".后二种 entry 则是正常文件的 entry, 依赖 attr 区分（偏移量为 `11` 的一个字节）。STD entry 中存放的是文件的修改时间、首个 cluster 号之类的元信息，而 LFN 则是用于存放文件名。若干个 LFN（可以为零）与一个紧随其后的 STD 组成了一个完整的“目录项”，描述了一个名字 - 元信息 - 文件的映射。

由于此处使用 `DEntry`有歧义，在我们的代码中使用 `AtomDEntry` 来指代单个 STD/LFN entry，而使用 `GroupDEntry` 来指代完整的一个“N*LFN + STD”的组合。

由于 fat32 设计上的缺陷，我们在遇到一个 STD 之前，并不能知道它前面会存在多少个 LFN；并且，一个 GroupDEntry 的组合也有可能跨 Sector 甚至 Cluster。为此，我们在逻辑上将文件夹抽象为 entry 数组，使用一个类似于“滑动窗口”的辅助数据结构来支持任意变长文件名的读写：

```rust
struct AtomDEntryWindows { /* ... */ }
// 向上层用户提供 "文件夹是 AtomDEntry 数组" 的假象，
// 维护该逻辑数组上的一个窗口，根据当前的窗口自动维护需要保持的块缓存 
impl AtomDEntryWindows {
    // 将窗口的左边移动 n 个 entry, 如果移动后有旧块滑出了窗口，则将其从块缓存中移除
    pub async fn move_left(&mut self, n: usize) -> SysResult<()> { /* ... */ }
    // 将窗口的右边移动 1 个 entry, 如果移动后有新块滑入了窗口，则将其加入块缓存
    pub async fn move_right_one(&mut self) -> SysResult<()> { /* ... */ }
}

// 向上层用户提供 "文件夹是 GroupDEntry 数组" 的假象，
// 自动识别当前 GroupDEntry 的边界，利用 AtomDEntryWindows 维护缓存
struct GroupDEntryIter { /* ... */ }
impl GroupDEntryIter {
    // 向前标记新的 GroupDEntry 的结束 (STD)
    pub async fn mark_next(&mut self) -> SysResult<Option<()>> { /* ... */ }
    // 离开当前标记的 GroupDEntry
    pub async fn leave_next(&mut self) -> SysResult<()> { /* ... */ }

    // 当 self 成功标记了一个新的 GroupDEntry 时，可以对其对应的属性进行相应的读写操作
    // 由于此时 GroupDEntry 已经被标记，与其相关的块都已被缓存在内存中，因此它们都是同步操作
    pub fn collect_name(&self) -> String { /* ... */ }
    pub fn get_attr(&self) -> Fat32DEntryAttr { /* ... */ }
    pub fn get_begin_cluster(&self) -> ClusterID { /* ... */ }
    pub fn get_size(&self) -> u32 { /* ... */ }
    pub fn change_size(&self, new_size: u32) { /* ... */ }

    // 同时，我们还可以删除当前标记或在当前为洞的位置插入一个新的 GroupDEntry
    pub fn can_create(&self, dentry: &FatDEntryData) -> bool { /* ... */ }
    pub async create_entry(&mut self, dentry: &FatDEntryData) -> SysResult<()> { /* ... */ }
    pub fn delete_entry(&mut self) { /* ... */ }
}
```

// TODO：这里应该补充一张类似状态机的窗口滑动图。

由此，我们便实现了一个以 sector 为调度单位的异步任意长 dentry 解析方法。

=== 分区支持
#label("fs-fat32-partition")

MankorOS 支持 MBR 格式的分区表，如果块设备上存在有 MBR 分区表，MankorOS 可以解析并挂载上面的多个文件系统。在区域赛中，MankorOS 自动从 virtio blk 设备上识别 FAT32 文件系统，并能够自动执行上面的测试程序。

// TODO：在决赛中怎么样

== 特殊文件
#label("fs-special-file")

在整个 VFS + FS 系统中，还存在一些特殊的文件，比如标准 IO、管道、挂载点。

=== Pipe
#label("fs-spc-pipe")

MankorOS 作为一个异步系统，管道实现自然也是异步的。异步管道的实现相对直接：当从管道读取端读时，若存在数据则立即返回，若不存在数据，便将自己的 waker 存放于管道的公共数据区中，等待有其他进程调用 write 时便唤醒 read_waker；当从管道写入端写时，若缓冲区未满则直接写入；若缓冲区已满，则将自己的 waker 存放于管道的公共数据区中，等待有其他进程调用 read 时便唤醒 write_waker.

当然，在实现的过程中，陷入睡眠的进程除了可能被新的读取/写入唤醒之外，还可能被信号唤醒。这就要求我们利用之前提到的 JoinFuture 与在进程模块中实现的事件总线机制结合，从而使得进程不会因为无限等待 pipe 而错过信号。

// TODO：在写完 async 和 process 之后给这里加上链接。

=== Stdio
#label("fs-spc-stdio")

Stdio 文件直接与 UART 设备交互，同步地写入所有传入的字符串。各个进程的标准输入输出的重定向功能通过修改进程中的文件描述符表实现，而与 FS 无关。

=== MountPoint
#label("fs-spc-mount-point")

一个挂载点保存了一个文件系统的引用与其根目录的引用，但同时实现了 VFS 的顶层接口，可以被当成一个普通文件夹使用，内容与该文件系统的根目录一致。

为了确保全局文件系统管理器中数据的正确性，MountPoint 只能通过向全局文件系统管理器注册才能获得实例，无法直接通过构造函数构造。