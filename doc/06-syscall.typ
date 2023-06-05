= 系统调用
#label("系统调用")

== 内存相关系统调用
#label("内存相关系统调用")

MankorOS 实现了三个内存相关的系统调用，分别为 brk、mmap 和 munmap。

sys\_brk：该系统调用用于更改进程的堆顶地址，并返回当前进程的堆顶地址。当参数
brk 为 0 时表示查询当前堆顶地址。 MankorOS 实现中，通过使用 Process
的内存管理器，记录和更新堆顶地址。

sys\_mmap：该系统调用允许进程在其虚拟地址空间中映射内存区域。
支持选项包括指定起始地址、长度、权限（PROT\_READ、PROT\_WRITE 和
PROT\_EXEC）和标志（MAP\_SHARED、MAP\_PRIVATE、MAP\_FIXED、MAP\_ANONYMOUS
和 MAP\_NORESERVE）。 MankorOS 通过 Process
的内存管理器来分配和映射物理页框，并将这些页框映射到进程的虚拟地址空间中。

sys\_munmap：该系统调用用于解除映射的内存区域。MankorOS
会通过内存管理器来取消对映射内存的映射，并释放相应的物理页框。

== 文件系统相关系统调用
#label("文件系统相关系统调用")
== 进程相关系统调用
#label("进程相关系统调用")
== 其他系统调用
#label("其他系统调用")
