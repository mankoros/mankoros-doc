= 同步

== 内存模型和缓存一致性

首先回顾一下内存模型和缓存一致性的发展历史。

最早期的多核处理器使用 Sequential Consistency 内存模型。Sequential Consistency 是一种严格的内存模型，它要求所有处理器核心之间的内存访问操作按照程序中编写的顺序执行。这意味着每个处理器核心看到的共享内存状态都是相同的，从而保证了数据的正确性。然而，这种模型的缺点是性能较低，因为它限制了处理器核心之间的并行度，所以在现代处理器中已经看不到使用了。

现代 x86 的处理器使用的是另一种内存模型 Total Store Ordering，它允许处理器核心之间的内存访问操作可以乱序执行，但要求写入操作必须全局可见，即写入操作必须以与程序中编写的顺序相同的顺序出现在其他处理器核心的读取中。这可以通过在写入操作前插入一个屏障指令来实现。这种模型允许更高的并行度，但需要编译器和程序员使用屏障指令来保证正确性。

与上述两种模型不同，RISC-V 中常使用的 `RVWMO` (RISC-V Weak Memory Model) 内存模型是一种弱同步模型，它允许处理器核心之间的内存访问操作可以乱序执行，并且没有全局的内存访问顺序要求。但是，RVWMO 内存模型规定了一些具体的内存序要求，以确保正确性：

+  内存屏障（memory barrier）指令必须按照程序中编写的顺序执行，并且必须在读取操作和写入操作之间使用。
+  写入相同地址的操作必须保持程序顺序。
+  读取相同地址的操作必须保持程序顺序。
+  原子操作可以保证多个处理器核心之间的互斥和同步，并且必须按照内存屏障指令的顺序执行。

Rust 中提供了多种不同的内存序用于控制多线程并发访问时的行为，以下是其中几种被抽象出来的内存序：

+  `SeqCst`：全称为 Sequentially Consistent，表示所有的操作都会按照程序中给定的顺序执行，即保持原子性、有序性和一致性。
+  `Acquire`：表示该操作之前的所有读取操作必须先于该操作执行，并且该操作与后续写入操作无序。
+  `Release`：表示该操作与之后的所有写入操作无序，并且该操作之后的所有读取操作必须在该操作执行之后执行。
+  `Relaxed`：表示不需要任何同步或顺序约束。

这些内存序可以通过 Rust 原子类型（如 `AtomicBool`、`AtomicI32` 等）中的方法进行设置和使用。通过适当地选择内存序，我们可以在不同的情况下实现合适的内存同步，以确保多线程代码的正确性和性能。

== 锁

=== 自旋锁

在 Rust 的 `no_std` 环境下，一些操作系统提供的同步原语（如互斥锁和条件变量）不可用。此时我们可以使用自旋锁来实现同步。

自旋锁是一种简单的同步机制，它通过忙等待的方式来阻塞线程，直到共享资源可用为止。当一个线程获取到自旋锁时，其他试图获取该锁的线程会进入自旋状态，反复尝试获取锁，直到当前持有锁的线程释放锁为止。

在 Rust 中，自旋锁可以通过原子类型 `AtomicBool` 和 `spin_loop_hint()` 函数来实现。以下是一个简单的自旋锁实现：

```rust
use core::sync::atomic::{AtomicBool, Ordering};

pub struct SpinLock {
    locked: AtomicBool,
}

impl SpinLock {
    pub const fn new() -> Self {
        SpinLock { locked: AtomicBool::new(false) }
    }

    pub fn lock(&self) {
        while self.locked.swap(true, Ordering::Acquire) {
            // 自旋等待锁
            core::hint::spin_loop();
        }
    }

    pub fn unlock(&self) {
        self.locked.store(false, Ordering::Release);
    }
}
```

上述代码中，使用 `AtomicBool` 类型的 `locked` 字段表示锁的状态。`lock()` 方法使用 `swap()` 方法来尝试获取锁并将 `locked` 设为 `true`，同时使用 `Acquire` 内存序来保证前面的读操作和当前的写操作不被重排序。如果 `swap()` 返回的是 `true`，则表示锁已经被其他线程持有，此时进入自旋状态直到获取到锁为止。在自旋状态中使用 `spin_loop()` 函数来提示 CPU 循环等待，以减少 CPU 的消耗。`unlock()` 方法通过调用 `store()` 方法将 `locked` 设为 `false`，同时使用 `Release` 内存序来保证当前的写操作和后续的读操作不被重排序。

MankorOS 利用 Rust 的 RAII（资源获取即初始化）来确保在作用域结束时自旋锁会被正确地释放。具体来说，MankorOS 定义了一个包含自旋锁的新类型，并实现 `Drop` trait 来在该类型的实例离开作用域时释放锁。

代码实现举例如下：

```rust
use core::sync::atomic::{AtomicBool, Ordering};

pub struct SpinLock {
    locked: AtomicBool,
}

impl SpinLock {
    pub const fn new() -> Self {
        SpinLock { locked: AtomicBool::new(false) }
    }

    pub fn lock(&self) -> SpinLockGuard {
        while self.locked.swap(true, Ordering::Acquire) {
            // 自旋等待锁
            core::hint::spin_loop();
        }
        SpinLockGuard { spin_lock: self }
    }

    pub fn unlock(&self) {
        self.locked.store(false, Ordering::Release);
    }
}

pub struct SpinLockGuard<'a> {
    spin_lock: &'a SpinLock,
}

impl<'a> Drop for SpinLockGuard<'a> {
    fn drop(&mut self) {
        self.spin_lock.unlock();
    }
}
```

上述代码中，定义了一个 `SpinLockGuard` 结构体来保存 `SpinLock` 的引用，并在其 `Drop` 实现中调用自旋锁的 `unlock()` 方法来释放锁。在 `lock()` 方法中，通过返回一个 `SpinLockGuard` 结构体来获取自旋锁。由于 `SpinLockGuard` 结构体实现了 `Drop` trait，因此当该结构体离开作用域时，会自动调用 `unlock()` 方法来释放锁。

使用 RAII 来管理自旋锁的获取和释放，可以有效避免忘记释放锁导致死锁等问题，在 Rust 中也是一种常见的编程模式。

=== 睡眠锁

异步睡眠锁的实现相对直接，只需要在锁中维护一个 waker 队列，当尝试获取锁时，如果锁已被占用，就将当前 waker 加入到队列中并返回 pending 即可。当锁被释放时，若当前 waker 队列非空，则唤醒队列中的第一个 waker, 并将其从队列中移除。

```rust
/// 睡眠锁本体，保存数据和等待队列
/// 使用方法：`let guard = A.lock().await;`
pub struct SleepLock<T: ?Sized> {
    inner: SpinNoIrqLock<SleepLockInner>,
    data: UnsafeCell<T>,
}
/// 睡眠锁内部数据
/// 反正修改队列都要获取锁，干脆把 flag 也放在里边
struct SleepLockInner {
    // holding 假 & 队列空：无人持有锁
    // holding 真 & 队列空：有人持有锁，但是没有人在等待锁
    // holding 真 & 队列非空：有人持有锁，也有人在等待锁
    holding: bool,
    waiting: VecDeque<Waker>,
}
impl<T: Sized> SleepLock<T> {
    pub fn new(data: T) -> Self { /* ... */ }
    pub fn lock(&self) -> SleepLockFuture<'_, T> {
        SleepLockFuture { mutex: self }
    }
}

pub struct SleepLockFuture<'a, T: ?Sized + 'a> {
    mutex: &'a SleepLock<T>,
}
impl<'a, T> Future for SleepLockFuture<'a, T> {
    type Output = SleepLockGuard<'a, T>;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        let this = unsafe { self.get_unchecked_mut() };
        let mut inner = this.mutex.inner.lock(here!());
        if inner.holding {
            // 如果锁已经被持有，则将当前线程加入等待队列
            inner.waiting.push_back(cx.waker().clone());
            Poll::Pending
        } else {
            // 如果锁没有被持有，则将锁标记为被持有，并返回锁的 guard
            inner.holding = true;
            Poll::Ready(SleepLockGuard { mutex: this.mutex })
        }
    }
}

// 睡眠锁的 guard，实现了 Deref 和 DerefMut
pub struct SleepLockGuard<'a, T: ?Sized + 'a> {
    mutex: &'a SleepLock<T>,
}
impl<'a, T: ?Sized> Drop for SleepLockGuard<'a, T> {
    fn drop(&mut self) {
        let mut inner = self.mutex.inner.lock(here!());
        // 因为新等待的人再次被唤醒时会获得新的 Guard, 而新的 guard.await 中会检查锁是否被持有
        // 所以即时下一个人马上会将这个 flag 设为 true, 也不能不修改它为 false
        // 否则下一个人会认为锁仍在被某人持有，从而进入等待; 而再也不会有人来唤醒这个锁了
        inner.holding = false;
        // 当睡眠锁的 Guard 被 drop 时，尝试唤醒等待队列中的第一个线程
        if let Some(waker) = inner.waiting.pop_front() {
            waker.wake();
        }
    }
}
```

== 异步进程间通信

很多时候一个进程正在进行的操作会被另一个进程打断，比如说一个正在等待管道数据的进程可能会被其父进程发来的 SIGKILL 打断。由于 MankorOS 中的信号只在进入用户态之前处理，因此为了实现这种 "打断" 操作，必须要有一种方法使得不在调度器中的进程在收到信号时能被重新加入到调度器中。MankorOS 参考了 FTL-OS 的事件总线机制，实现了一个相对简单的异步进程间通信机制。

```rs
type EventNodeId = usize;
struct EventNode {
    id: EventNodeId,
    listen_for: EventKind,
    waker: Ptr<Waker>,
}
pub struct EventBus {
    events: Vec<EventNode>,
    pool: UsizePool,
}
```

对于需要被打断的异步等待，它会在本进程的事件总线中放入自己的 waker 再进入等待。然后若有其他进程向本进程发送信号，便会去查找事件总线中等待对应事件的节点，对其中的 waker 进行唤醒。值得注意的是，该实现方式的事件总线必须支持删除，因为当一个进程停止等待时 (比如从管道中读到数据了), 它的 waker 就有可能被析构，此时留在事件总线中的 waker 指针就有可能指向无效内存，因此必须在事件总线中删除这个节点。

我们可以搭配下面的 future 与辅助函数实现这点：

```rs
pub struct EventBusWaitForFuture<'a> {
    lproc: &'a LightProcess,
    waker: &'a Waker,
    event_id: Option<EventNodeId>,
    listen_for: EventKind,
}
impl Future for EventBusWaitForFuture<'_> {
    type Output = ();
    fn poll(self: Pin<&mut Self>, _cx: Context<'_>) -> Poll<Self::Output> {
        let this = unsafe { self.get_unchecked_mut() };
        if this.event_id.is_none() {
            // 如果还没有向事件总线注册，就注册一下并且放弃 CPU
            let ptr = this.waker as *const _ as *mut _;
            let id = this
                .lproc
                .with_mut_event_bus(|bus| bus.register(this.listen_for, Ptr::new(ptr)));
            this.event_id = Some(id);
            Poll::Pending
        } else {
            // 如果它被 poll 第二次，那么只有可能是被唤醒了
            // 此时我们直接返回 Ready 让上层 future 继续执行
            Poll::Ready(())
        }
    }
}
impl Drop for EventBusWaitForFuture<'_> {
    fn drop(&mut self) {
        // 如果直到它被 drop, 它都没有被唤醒第二次，就将自己从事件总线中删除
        if let Some(id) = self.event_id {
            self.lproc.with_mut_event_bus(|bus| bus.remove(id));
        }
    }
}
```
