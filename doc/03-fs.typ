= 文件系统
#label("文件系统")

== VFS 设计与结构
#label("vfs-设计与结构")

VFS（Virtual File
System）是指一种抽象层，用于在操作系统中将不同类型的文件系统统一起来。在
VFS 的设计中，所有的 I/O 请求都被发送到 VFS 层，并由 VFS
层进行相应的处理后再传递给具体的文件系统。

VFS 的结构通常由以下几个部分组成：

-  虚拟文件系统：代表了整个文件系统树，包含了各种文件系统节点（文件、目录、符号链接等）。
-  文件系统接口：由各个具体文件系统提供的接口，用于实现文件系统的基本操作，例如读写文件、创建删除文件等。
-  虚拟文件系统操作接口：由 VFS
  层提供的接口，用于对外提供文件系统操作的统一接口，例如打开文件、关闭文件、读取文件等。

为了支持异步内核 Cooperative Scheduling 的设计，MankorOS 的 VFS
设计中同时包含有异步的接口和同步的接口。
同步的接口主要供内核使用，一般是较快的操作，而且保证不会受到其他进程的阻塞。
异步的接口主要供系统调用使用，进程对文件的读写可能依赖于其他进程，例如管道的读写，因此对于这些请求，实现异步的读写是有必要的。

== 设备文件系统 (devfs)
#label("设备文件系统-devfs")

设备文件系统（devfs）是一种特殊的文件系统，用于管理系统中的设备文件。在
Unix-like
操作系统中，所有的硬件设备都被表示为一个文件或文件夹，并挂载在设备文件系统中。通过这种方式，用户可以像访问普通文件一样访问和操作硬件设备。

在 MankorOS
中，设备管理模块通过注册和卸载设备的方式来实现对设备文件系统的管理。当一个设备被注册后，其对应的设备文件会被创建并挂载到/dev
目录下，用户可以通过这个设备文件进行设备的读写等操作。

=== 块设备的挂载
#label("块设备的挂载")

块设备是指按照固定大小划分为若干个扇区的存储介质，例如硬盘、U 盘等。在
MankorOS 中，支持将块设备挂载到文件系统上，并通过 VFS
层提供的标准接口进行操作。

为了实现块设备的挂载，MankorOS 在 Disk 结构体中实现了 VFS Trait（包括
open、read、write、seek 等函数），并在设备管理模块中注册了 VirtIO
发现的块设备。

== Fat32
#label("fat32")

Fat32 是一种常见的文件系统格式，广泛应用于 Windows
系统及其他各种设备中，例如移动硬盘、SD 卡等。在 MankorOS
中，文件系统模块实现了对 Fat32 文件系统的支持，用户可以对 Fat32
格式的设备进行挂载和操作。

== Pipe 与 Stdio
#label("pipe-与-stdio")

管道（pipe）是一种特殊的文件，主要用于实现进程间通信。在 Unix-like
系统中，管道被视为一种特殊的文件类型，可以像普通文件一样进行读写操作。在
MankorOS 中，支持通过 VFS
层提供的接口创建、打开、关闭、读写管道文件，从而实现进程间通信的功能。

MankorOS
实现了一个管道数据结构，其中包含两个实例，一个是读端，一个是写端。管道的数据保存在一个环形缓冲区中，而这个缓冲区是使用一个
RingBuffer 库来实现的。这个环形缓冲区是在内核堆上分配的，并通过 Arc 和
SpinNoIrqLock 进行并发访问控制。

当写入数据时，管道首先检查是否可写，然后检查是否挂起。如果管道没有挂起，则获取锁以访问管道的数据，并将数据写入环形缓冲区中。如果缓冲区已满，释放锁，并调用
yield\_now() 函数，将 CPU
切换到其他任务。当有足够的空间时，释放锁并返回写入的字节数。

同样地，当读取数据时，管道首先检查是否可读，然后检查是否挂起。如果管道没有挂起，则获取锁以访问管道的数据，并从环形缓冲区中读取数据。如果缓冲区为空，释放锁，并调用
yield\_now() 函数，将 CPU
切换到其他任务。当有足够的数据时，释放锁并返回读取的字节数。

对于管道的其他操作，如 fsync 和 truncate，MankorOS 会返回不支持的错误。

stdio（standard input/output）是指标准输入输出，在 C
语言中主要通过三个标准流 stdin、stdout 和 stderr 来实现。在 MankorOS
中，用户可以通过标准输入输出流来读取或输出数据，并可以将标准输入输出流与文件系统中的文件或管道进行关联，实现灵活的输入输出方式。