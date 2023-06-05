= 基于无栈协程的异步

== 基础概念

=== `Future` 之间的组合

无栈协程的核心是 `Future`:

```rust
pub trait Future {
    type Output;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output>;
}
```

`Future` 是异步函数的抽象。调用 `poll` 方法代表 "检查任务结果",
如果任务已经完成，则返回 `Poll::Ready` (其中包含结果数据), 否则返回
`Poll::Pending` 表示任务尚未结束。

```rust
struct IdFuture {
    result: i32
}
impl Future for IdFuture {
    type Output = i32;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        if /* some condition */ {
            Poll::Ready(self.result)
        } else {
            Poll::Pending
        }
    }
}
impl IdFuture {
    pub fn new(result: i32) -> Self {
        Self { result }
    }
}
```

`Future` 之间可以组合。下面的 `Future` 实现了将一个 `Future` 的结果乘以
2 的功能：

```rust
struct DoubleFuture {
    a: IdFuture,
}
impl Future for DoubleFuture {
    type Output = i32;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        let this = unsafe { self.get_unchecked_mut() };

        // 调用 a 的 poll 方法，如果 a 返回 Poll::Pending, 则返回 Poll::Pending
        let a = unsafe { Pin::new_unchecked(&mut this.a) };
        let ar = match a.poll(cx) {
            Poll::Ready(x) => x,
            Poll::Pending => return Poll::Pending,
        };

        // 如果 a 返回了 Poll::Ready, 就返回最终结果 Poll::Ready(ar * 2)
        Poll::Ready(ar * 2)
    }
}
impl DoubleFuture {
    pub fn new(x: i32) -> Self {
        Self { a: IdFuture::new(x) }
    }
}
```

可以看到，`Future` 的组合是通过对子 `Future` 的 `poll`
方法结果进行简单的组合得到的：只要子 `Future` 返回 `Poll::Pending`, 则父
`Future` 也返回 `Poll::Pending`. 于是我们可以让编译器代我们生成上述代码：

```rust
async fn double(x: i32) -> i32 {
    let ar = IdFuture::new(x).await;
    ar * 2
}
```

一个异步函数的上下文可以被保存在具体的 `Future` 结构体中，
从而使得函数可保存其上下文状态并恢复之。比如下面的 `Future` 实现了将两个
`Future` 的结果相加的功能：

```rust
struct AddFuture {
    status: usize,
    x: i32,
    y: i32,
    a1: IdFuture,
    a2: IdFuture,
}
impl Future for AddFuture {
    type Output = i32;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        let this = unsafe { self.get_unchecked_mut() };
        loop {
            // 使用状态机的方式实现
            match this.status {
                AddFuture::STATUS_BEGIN => {
                    let a1 = unsafe { Pin::new_unchecked(&mut this.a1) };
                    let ar = match a1.poll(cx) {
                        Poll::Ready(x) => x,
                        Poll::Pending => return Poll::Pending,
                    };
                    // 保存局部变量
                    this.x = ar;
                    // 修改状态
                    this.status = AddFuture::STATUS_A1;
                }
                AddFuture::STATUS_A1 => {
                    let a2 = unsafe { Pin::new_unchecked(&mut this.a2) };
                    let ar = match a2.poll(cx) {
                        Poll::Ready(x) => x,
                        Poll::Pending => return Poll::Pending,
                    };
                    // 保存局部变量
                    this.y = ar;
                    // 修改状态
                    this.status = AddFuture::STATUS_A2;
                }
                AddFuture::STATUS_A2 => {
                    // 返回最终结果
                    return Poll::Ready(this.x + this.y);
                }
                _ => unreachable!()
            }
        }
    }
}
const UNINIT: i32 = 0;
impl AddFuture {
    const STATUS_BEGIN: usize = 0;
    const STATUS_A1: usize = 1;
    const STATUS_A2: usize = 2;

    pub fn new(x: i32, y: i32) -> Self {
        Self { 
            status: AddFuture::STATUS_BEGIN, 
            x: UNINIT,
            y: UNINIT,
            a1: IdFuture::new(x), 
            a2: IdFuture::new(y) 
        }
    }
}
```

注意我们不能直接顺序地调用两个 `Future` 的 `poll` 方法并检查，因为一个
`Future` 的 `poll` 方法可能会被执行多次。比如第一次 `poll` 时，`a1`
返回了 `Ready` 但 `a2` 返回了 `Pending`, 此时整个 `poll` 也应该返回
`Pending`. 但是当第二次调用 `poll` 时，我们显然不能再重复去调用 `a1` 的
`poll` 方法，所以我们需要保存 "我们已经执行过 `a1.poll` 了" 这个状态，
同时还要保存 `a1.poll` 方法的返回值。

于是我们可以总结出，每次对子 `Future` 的 `poll` 方法调用，都需要产生一个
"保存点", 并且还需要在这里存下 `poll` 方法的返回值。
这种规则也是非常机械的，我们还是可以交给编译器，
让它在编译时为我们自动生成相似的代码：

```rust
async fn add(x: i32, y: i32) -> i32 {
    let a1 = IdFuture::new(x).await;
    let a2 = IdFuture::new(y).await;
    a1 + a2
}
```

=== `Future` 的边界

上面的论述了 `Future` 的组合方式,
但要想写出真实可用的异步程序,
我们还缺少两个部分:
最初和最后的 `Future`.
而这两部分都与 `Future::poll` 方法的第二个参数 `Context` 息息相关.

我们先来考虑如何在一个普通的 `main` 函数中调用我们刚刚写的 `Future`.
假设我们通过了某种魔法操作获得了一个平凡的, 不起作用的 `Context` 对象,
我们应该会这样使用 `AddFuture`:

```rust
pub fn main() {
    let mut ctx: Context = /* some magic here */;
    let result = AddFuture::new(1, 2).poll(&mut ctx);
    match result {
        Poll::Ready(x) => println!("result: {}", x),
        Poll::Pending => todo!(),
    }
}
```

那么, 当我们调用一个 `Future` 的 `poll` 方法时,
如果它返回了 `Pending`, 应该怎么办呢?
一种直接的解法是直接写一个 `loop` 循环, 
持续调用 `poll` 方法直到其返回 `Ready` 为止.
但这样做有一个问题: 
我们的 `main` 函数会被阻塞在 **一个** `Future` 上.

初看这似乎不是什么问题, 
但如果我们需要等待多种资源去完成多个任务时, 
阻塞在一个 `Future` 上就会变得非常低效.
尤其是当我们可以让资源在就绪时调用某个回调函数来通知我们, 
而不需要我们去轮询它们的就绪状态时,
我们会很自然地想到: 
能不能做一个队列, 当一个 `Future` 执行到最后, 卡在需要获取某个资源时, 
我们让它设置好该资源的回调函数, 在资源就绪时重新将最开始的 `Future` 放回队列中等待执行, 
自己则直接返回 `Pending` 放弃本次执行?

而这, 就是 `Context` 的作用了.
我们深入 `Context` 的实现, 会发现它大概长这样 (删去了一些无关紧要的成员):

```rust
pub struct Context<'a> {
    waker: &'a Waker,
}
pub struct Waker {
    raw: RawWaker,
}
pub struct RawWaker {
    data: *const (),
    vtable: *const RawWakerVTable,
}
pub struct RawWakerVTable {
    clone: unsafe fn(*const ()) -> RawWaker,
    wake: unsafe fn(*const ()),
    wake_by_ref: unsafe fn(*const ()),
    drop: unsafe fn(*const ()),
}
```

那么, 只要我们将这个队列的指针和最外层的 `Future` 的指针保存到 `RawWaker::data` 中,
并将 `RawWakerVTable` 的 `wake` 方法设置为将保存的最外层 `Future` 放回队列中,
我们就能实现上面的想法了.

当然, 上面的都是非常简化的讨论, 
实际要在 Rust 中实现上述操作需要考虑很多细节,
比如各类数据结构的生命周期和内存位置等问题.
好在大部分时候我们不需要手动去实现自己的 `Context`,
而是可以使用 `async_task` 库来帮助我们完成这些工作,
我们只需要指定当 wake 方法被调用时,
我们想要干什么就可以了.

#import "04-process.typ": process_sch

在目前版本的 MankorOS 中,
我们基本上使用了上述实现.
这相当于一个简单的 Round-Robin 调度器,
具体细节可以参见 #link(process_sch, "进程调度") 一节.

```rs
// src/executor/task_queue.rs:6
pub struct TaskQueue {
    queue: SpinNoIrqLock<VecDeque<Runnable>>,
}
impl TaskQueue {
    pub const fn new() -> Self {
        Self { queue: SpinNoIrqLock::new(VecDeque::new()) }
    }
    pub fn push(&self, task: Runnable) {
        self.queue.lock(here!()).push_back(task);
    }
    pub fn fetch(&self) -> Option<Runnable> {
        self.queue.lock(here!()).pop_front()
    }
}

// src/executor/mod.rs:15
lazy_static! {
    static ref TASK_QUEUE: TaskQueue = TaskQueue::new();
}
pub fn spawn<F>(future: F) -> (Runnable, Task<F::Output>)
where
    F: Future + Send + 'static,
    F::Output: Send + 'static,
{
    // 在此处指定当 cx.wake_by_ref() 被调用时, 我们需要它干什么
    async_task::spawn(future, |runnable| TASK_QUEUE.push(runnable))
}
```

而在 `Future` 栈的另一头, 
当我们需要等待某个资源时,
我们就可以直接将对应的 `waker` 传给资源方, 
等待回调, 同时返回 `Pending` 了.
具体细节可参见 #link(<wrap_future>, "包装型 Future").

== 内核实现要点

倘若是编写普通的异步程序，
只需使用使用 `async`/`await` 关键字即可。
但一个异步内核显然不能仅仅依赖组合已有的 `Future`,
还必须实现一些底层或顶层的 `Future`,
这些 `Future` 大致可以分为三类：

- 为其他 `Future` "装饰" 的 `Future`
- 为底层回调提供包装的 `Future`
- 一些辅助性的工具 `Future`

=== 装饰型 `Future`

当我们使用 `async`/`await` 时，
编译器会自动为我们生成一个 `Future` 的实现，
这个实现会在子 `Future` 返回 `Pending` 时直接返回 `Pending`.

如果我们需要在子 `Future` 返回 `Pending` 时执行一些额外的操作，
我们就必须手动编写该 `Future` 的实现。
异步内核中用于切换到用户态线程的 `Future` 就是典型的此类 `Future`,
无论子 `Future` 返回 `Pending` 还是 `Ready`,
它都需要在执行前后完成一些额外的操作：

```rust
pub struct OutermostFuture<F: Future> {
    lproc: Arc<LightProcess>,
    future: F,
}
impl<F: Future> Future for OutermostFuture<F> {
    type Output = F::Output;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        // ... (关闭中断，切换页表，维护当前 hart 状态)
        let ret = unsafe { Pin::new_unchecked(&mut this.future).poll(cx) };
        // ... (开启中断，恢复页表，恢复之前的 hart 状态)
        ret
    }
}
```

随后我们便可以在 `userloop` 外边包裹这个 `Future`,
从而其无需再担心进程切换相关的杂事：

```rust
pub fn spawn_proc(lproc: Arc<LightProcess>) {
    // userloop 为切换到用户态执行的 Future
    let future = OutermostFuture::new(
        lproc.clone(), userloop::userloop(lproc));
    let (r, t) = executor::spawn(future);
    r.schedule();
    t.detach();
}
```

=== 包装型 `Future` <wrap_future>

这种 `Future` 通常位于 `Future` 栈的最底层 (最后被调用的那个),
用于将底层的回调接口包装成 `Future`.
其一般表现为将 `Waker` 传出或将 `|| cx.waker().wake_by_ref()` 设置为回调函数。
异步内核中用于实现异步管道读写操作的 `Future` 就是典型的此类 `Future`:

```rust
pub struct PipeReadFuture {
    pipe: Arc<Pipe>,
    buf: Arc<[u8]>,
    offset: usize,
}
impl Future for PipeReadFuture {
    type Output = usize;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        // ... 各种检查和杂项代码
        if pipe.is_empty() {
            // 如果管道为空，就将当前 waker 存起来。在管道写入数据之后，
            // 会调用 pipe.read_waker.wake_by_ref() 以重新将顶层 Future 唤醒
            pipe.read_waker = Some(cx.waker().clone());
            Poll::Pending
        } else if pipe.is_done() {
            pipe.read_waker = None;
            Poll::Ready(0)
        } else {
            let len = pipe.read(this.buf.as_mut(), this.offset);
            // 如果写入时写满了管道的缓冲区，那么就将写入者的 waker 存起来。
            // 现在再调用。如果写入者已经写完了，则它不会再设置 pipe 的该成员。
            if let Some(write_waker) = pipe.write_waker {
                // 如果管道写入数据之前，已经有一个 waker 等待管道读取数据，
                // 那么就将这个 waker 唤醒
                write_waker.wake_by_ref();
            }
            Poll::Ready(len)
        }
    }
}
```

=== 辅助型 `Future`

除了上面两大类 `Future` 之外，
还有一些工具性质的 `Future`,
在开发异步内核时也是非常有用的，现列举一二。

==== `YieldFuture`

有时候，我们需要当前 `Future` 主动返回一次 `Pending` 以让出控制权，
但是并不想让它等待什么，而是直接回到调度器中等待下一次调度。
这时候就可以使用 `YieldFuture`:

```rust
pub struct YieldFuture(bool);
impl Future for YieldFuture {
    type Output = ();
    fn poll(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        if self.0 {
            // 之后再次被 poll 时，它直接返回 Ready, 什么事都不干
            return Poll::Ready(());
        } else {
            // 第一次调用时，self.0 为 false, 此时它直接调用 wake_by_ref
            // 将自己重新加回调度器中，并返回 Pending 使得所有上层 Future
            // 返回，让出这一轮的调度权
            self.0 = true;
            cx.waker().wake_by_ref();
            Poll::Pending
        }
    }
}
pub fn yield_now() -> YieldFuture {
    YieldFuture(false)
}
```

它可以用于实现 `yield` 系统调用，
也可以在异步内核实现过程中用来实现某种 "spin" 式操作：

```rust
loop {
    let resource_opt = try_get_resouce();
    if let Some(resource) = resource_opt {
        break resource;
    } else {
        // 如果资源不可用，就让出控制权，并期望下次被调用时等待资源可用
        yield_now().await;
    }
}
```

但是，这种写法是不推荐的，
它放弃了异步内核的很大一部分优越性。
在使用这种写法之前，应该首先尝试将该资源的获取改写为回调式的，
使用 "包装型 `Future`" 的写法实现。

`YieldFuture` 也可用于某些系统的最底层实现中，
比如搭配定时器中断，使用自旋检查的方法实现内核内的定时任务。

==== `WakerFuture`

`WakerFuture` 用于在 `async fn` 中获取当前 `Waker`:

```rust
struct WakerFuture;
impl Future for WakerFuture {
    type Output = Waker;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        Poll::Ready(cx.waker().clone())
    }
}
```

如下使用便可以在 `async fn` 中获取当前 `Waker`:

```rust
async fn foo() {
    let waker = WakerFuture.await;
    resource.setReadyCallback(|| waker.wake_by_ref());
}
```

使用该 `Future` 时，
可以使很大一部分包装型 `Future` 得以直接使用 `async fn` 来实现，
而不用再手动实现 `Future` trait.

== 上下文切换
