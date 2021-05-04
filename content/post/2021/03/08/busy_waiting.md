---
title: "忙等"
date: 2021-03-08T23:05:33+08:00
draft: false
description: ""
tags: [go, concurrent, event-driven]
categories: []
---

不如唤醒。

<!--more-->

## 反面

上课期间看到一段模拟投票的程序，其中主协程（main goroutine）产生的若干子协程并发请求票与计票，主协程重复检查票数是否已达到预期。

```go
package main

import (
    "fmt"
    "math/rand"
    "os"
    "strconv"
    "sync"
    "time"
)

func main() {
    rand.Seed(time.Now().UnixNano())

    total, err := strconv.Atoi(os.Args[1])
    if err != nil {
        panic(err)
    }
    overHalf := total/2 + 1
    count := 0
    finished := 0
    var mu sync.Mutex

    for i := 0; i < total; i++ {
        go func() {
            vote := requestVote()
            mu.Lock()
            defer mu.Unlock()
            if vote {
                count++
            }
            finished++
        }()
    }

    for count < overHalf && finished < total {
        // ...
    }
    fmt.Printf("count: %d\n", count)
    fmt.Printf("finished: %d\n", finished)
    fmt.Printf("count >= overHalf: %t\n", count >= overHalf)
}

func requestVote() bool {
    time.Sleep(time.Duration(rand.Intn(100)) * time.Millisecond)
    return rand.Int()%2 == 0
}
```

由于若干子协程并发访问一些共享变量（count 和 finished），使用互斥锁（Mutex）可直截了当防止内存一致性错误。另一方面，主协程反复检查票数时对于 count 和 finished 只读，因此并不需要锁定与解锁？

```go
for count < overHalf && finished < total {
    // ...
}
```

Visual Studio Code 推荐的 Go 代码静态分析器—— [go-staticcheck](https://staticcheck.io/) 对以上循环语句给出了以下提示：

> loop condition never changes or has a race condition (SA5002) go-staticcheck

[竞态条件（race condition）](https://en.wikipedia.org/wiki/Race_condition)是指事件的时序或次序的不确定性影响到程序的正确性时产生的缺陷。此处不确定性的典型事例是上下文切换、操作系统信号、多处理器上的内存操作、硬件中断等，一般来说，产生竞态条件的场景是并发。在模拟投票程序，主协程读共享变量与若干子协程写共享变量这两件事的次序具有不确定性（参见[多线程·并发编程](https://h2cone.github.io/post/2020/02/thread_concurrent/)），但是该程序结果仍然符合预期，因为这些共享变量从主协程的角度来看只是只读的变量（仅判断条件为真后不做任何事情而是继续判断条件）；尽管主协程某时刻可能读到脏数据（脏读），但是在这之后总能读到最终值，因为 count/finished 的值只递增，而且 overHalf/total 的值不变。如果主协程对共享变量不仅读取而且写入，出于安全考虑应当使用同步（Synchronization），例如也使用互斥锁：

```go
for {
    mu.Lock()
    if count >= overHalf || finished >= total {
        break
    }
    mu.Unlock()
}
fmt.Printf("count: %d\n", count)
fmt.Printf("finished: %d\n", finished)
fmt.Printf("count >= overHalf: %t\n", count >= overHalf)
mu.Unlock()
```

不仅消灭了潜在的竞态条件，而且消灭了潜在的[数据竞争（data race）](https://en.wikipedia.org/wiki/Race_condition#Data_race)。数据竞争发生在两个线程/协程并发访问相同变量并且至少一个访问是写入时。下面老套的程序（主协程将等待所有子协程完成计数任务后才汇报）比较容易捕获协程之间的数据竞争产生的 BUG。

```go
package main

import (
    "fmt"
    "os"
    "strconv"
    "sync"
)

func main() {
    total, err := strconv.Atoi(os.Args[1])
    if err != nil {
        panic(err)
    }
    count := 0
    var wg sync.WaitGroup

    for i := 0; i < total; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            count++
        }()
    }

    wg.Wait()
    fmt.Printf("count: %d\n", count)
    fmt.Printf("count == total: %t\n", count == total)
}
```

Go 官方提供了 [Data Race Detector](https://golang.org/doc/articles/race_detector) 用于探测协程之间的数据竞争，有利于人们排除并发引起的故障。

```shell
% go run -race count.go 1000000
==================
WARNING: DATA RACE
Read at 0x00c0001ba008 by goroutine 8:
  main.main.func1()
      /Users/cosimo/vscws/go-examples/condvar/count.go:22 +0x6c

Previous write at 0x00c0001ba008 by goroutine 7:
  main.main.func1()
      /Users/cosimo/vscws/go-examples/condvar/count.go:22 +0x84

Goroutine 8 (running) created at:
  main.main()
      /Users/cosimo/vscws/go-examples/condvar/count.go:20 +0x184

Goroutine 7 (finished) created at:
  main.main()
      /Users/cosimo/vscws/go-examples/condvar/count.go:20 +0x184
==================
count: 999990
count == total: false
Found 1 data race(s)
exit status 66
```

以上只是借题发挥，与[忙等（busy waiting）](https://en.wikipedia.org/wiki/Busy_waiting)并无关系，忙等有时被称为自旋（spinning）。模拟投票程序中的主协程反复判断条件是在浪费 CPU 时间，静态分析器得出了类似的警告：

> this loop will spin, using 100%% CPU (SA5002) go-staticcheck

在大多数情况下，忙等被认为是[反模式](https://en.wikipedia.org/wiki/Anti-pattern)而应该避免，与其将 CPU 时间浪费在无用的活动上，不如用于执行其它任务。

```java
while (<condition>) {
    Thread.sleep(millis);
}
```

即使是在循环体内睡眠，IntelliJ IDEA 也可能提醒道：

> Call to 'Thread.sleep()' in a loop, probably busy-waiting

不过是五十步笑百步罢了。虽然调整睡眠时长能减少条件判断次数，但是反复唤醒的成本不容忽视，无法排除浪费 CPU 时间的嫌疑。

## 条件变量

最少化线程/协程的 CPU 时间成本，干吗不用**事件驱动**范式指导编程呢？具体来说，模拟投票程序中的主协程只在票数可能已到预期的情况下判断条件（若干子协程对共享变量的写入完成后**通知**主协程）。

```go
package main

import (
    "fmt"
    "math/rand"
    "os"
    "strconv"
    "sync"
    "time"
)

func main() {
    rand.Seed(time.Now().UnixNano())

    total, err := strconv.Atoi(os.Args[1])
    if err != nil {
        panic(err)
    }
    overHalf := total/2 + 1
    count := 0
    finished := 0
    var mu sync.Mutex
    cond := sync.NewCond(&mu)

    for i := 0; i < total; i++ {
        go func() {
            vote := requestVote()
            mu.Lock()
            defer mu.Unlock()
            if vote {
                count++
            }
            finished++
            cond.Signal()
        }()
    }

    mu.Lock()
    for count < overHalf && finished < total {
        cond.Wait()
    }
    fmt.Printf("count: %d\n", count)
    fmt.Printf("finished: %d\n", finished)
    fmt.Printf("count >= overHalf: %t\n", count >= overHalf)
    mu.Unlock()
}

func requestVote() bool {
    time.Sleep(time.Duration(rand.Intn(100)) * time.Millisecond)
    return rand.Int()%2 == 0
}
```

[条件变量（condition variable）](https://en.wikipedia.org/wiki/Monitor_(synchronization)#Condition_variables)是一种使线程/协程等待另一个线程/协程执行特定操作的机制，与互斥锁同属于**同步原语（synchronization primitives）**。

不难发现条件变量是通过互斥锁来创建，而且在等待（`Wait()`）之前需要先锁定（`Lock()`）（[Java 的 wait/notify](http://localhost:1313/post/2020/02/thread_concurrent/#waitnotify) 和 [Condition](http://localhost:1313/post/2020/02/thread_concurrent/#blockingqueue) 也有类似要求），为什么条件变量需要或者依赖互斥锁？

- 条件变量可能被并发访问，考虑将访问条件变量的代码移动到临界区（锁定的代码块）。

- 协程在临界区调用 `cond.Wait()` 时释放互斥锁（否则准备发送通知的协程一直锁定失败）并“暂停”。

- 协程在临界区调用 `cond.Signal()` 或 `cond.Broadcast()` 通知“暂停”的协程有事发生，被通知的协程从 `cond.Wait()` 返回（”恢复“），并继续执行其余代码。

## 烂尾

你准备好了吗？

你准备好了吗？

你准备好了吗？

......

别再问了，准备好了就通知你。

> 本文首发于 https://h2cone.github.io

## 参考资料

- [Are “data races” and “race condition” actually the same thing in context of concurrent programming](https://stackoverflow.com/questions/11276259/are-data-races-and-race-condition-actually-the-same-thing-in-context-of-conc)

- [Race Condition vs. Data Race](https://blog.regehr.org/archives/490)

- [Why do pthreads’ condition variable functions require a mutex?](https://stackoverflow.com/questions/2763714/why-do-pthreads-condition-variable-functions-require-a-mutex)

- [How To Avoid Busy Waiting](https://josephmate.wordpress.com/2016/02/04/how-to-avoid-busy-waiting/)
