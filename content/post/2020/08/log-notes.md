---
title: "日志游记"
date: 2020-08-30T15:21:41+08:00
draft: true
description: ""
tags: [log, database, distributed]
categories: []
---

简单且普适的关键抽象。

<!--more-->

## 什么是日志

日志是**追加式**的，**按时间排序**的记录序列。

![log(file).png](/img/log/log(file).png)

无关记录的格式，日志文件记录操作系统或其它软件运行时发生的[事件](https://en.wikipedia.org/wiki/Event_(computing))及其时间。

```text
 <34>1 2003-10-11T22:14:15.003Z mymachine.example.com su - ID47 - BOM'su root' failed for lonvick on /dev/pts/8
```

“应用程序日志”是人类可读的文本，比如 [Syslog](https://en.wikipedia.org/wiki/Syslog) 和 [SLF4J](http://www.slf4j.org/) 等；如上所示，这是一个来自 [RFC5424](https://tools.ietf.org/html/rfc5424) 的 syslog 日志消息例子，从中不难看出主机（mymachine.example.com）上的一个应用程序（su）在 2003-10-11T22:14:15.003Z 发生了 “'su root' failed for lonvick...”。

日志并非全都是人类可读的，它可能是二进制格式而只能被程序读取，作为关键抽象普遍存在于数据库系统和分布式系统之中。

## 数据库日志

关系数据库系统中的日志通常用于[崩溃恢复](http://mlwiki.org/index.php/Crash_Recovery)、提供一定程度的[原子性](https://en.wikipedia.org/wiki/Atomicity_(database_systems))与[持久性](https://en.wikipedia.org/wiki/Durability_(database_systems))、[数据复制](https://en.wikipedia.org/wiki/Replication_(computing))。

### 预写日志

老伙计 MySQL server 维护着持久化数据库对象，包括库、表、索引、视图等。根据经验，我们确信入库数据终将会被 MySQL server 写入磁盘，磁盘是一种 I/O 设备（参考 [网络·NIO # I/O](https://h2cone.github.io/post/2020/03/network_nio/#i-o)），从主存复制数据到 I/O 设备并不是一个原子操作，如果客户端发送请求后，MySQL server 处理请求中，系统[崩溃](https://en.wikipedia.org/wiki/Crash_(computing))或宕机抑或重启，MySQL 如何保证不丢失变更或者恢复到正确的数据？

很久以前，存在着无原子性的非分布式数据库事务。张三账户有 1000 元，李四账户有 2000 元，张三向李四转账 200 元，数据库系统先将张三账户减少 200 元，然后将 800 元写回张三账户，接着将李四账户增加 200 元并且将 2200 元写回李四账户时，服务器突然发生故障；系统重启后，只有一个账户是对的，张三账户是 800 元，但是李四账户还是 2000 元，200 元不翼而飞。

计算机界明显的坑早已被前人填满。[Write-ahead logging](https://en.wikipedia.org/wiki/Write-ahead_logging) 是数据库系统中提供原子性与持久性的技术（日志先行技术），简称 **WAL**，一言蔽之，数据库系统首先将数据变更记录到日志中，然后将日志写入稳定存储（如磁盘），之后才将变更写入数据库。

InnoDB（MySQL 默认存储引擎）的 [redo log](https://dev.mysql.com/doc/refman/5.7/en/innodb-redo-log.html) 和 [undo log](https://dev.mysql.com/doc/refman/5.7/en/innodb-undo-logs.html) 皆为磁盘数据结构：

- undo log 在崩溃恢复期间用于撤消或回滚未提交的事务。

- redo log 在崩溃恢复期间用于重做已提交但未将数据库对象从缓冲区（**buffer**）刷新到磁盘的事务。

撤消和重做的前提是记录了数据库对象变更前的值和变更后的值。

假设事务 T[i] 所操作的数据库对象是 X，X 的值从 V[old] 更改为 V[new]，将数据从缓冲区刷新到磁盘的操作被称为 **flush**，那么 undo/redo log 日志记录形式如下：

```text
begin T[i]        //（1）
(T[i], X, V)      //（2）
commit T[i]       //（3）
```

（1）记录事务开始。

（2）记录数据库对象的值。undo log 记录 (T[i], X, V[old]) ，而 redo log 记录 (T[i], X, V[new])，两者都要求 flush X 之前 flush (T[i], X, V)。

（3）记录事务提交。undo log 要求 flush X 之后 flush "commit T[i]"，而 redo log 要求 flush X 之前 flush "commit T[i]"。

在崩溃恢复期间，从数据库系统角度来看：

- 若发现缺少（3），则将 X 的值设为 V[old]，因为 X 变更前的值是 V[old]，即使恢复过程中又发生崩溃，重复将 X 的值设为 V[old] 仍然**幂等**；直到恢复完成后，可以在（3）位置追加一条记录：rollback T[i]，下次恢复期间忽略。

- 若发现缺少（2），则 X 未 flush，无影响。

- 没有（1）也就无此事务。

### 逻辑日志

## 分布式系统日志

## 容器日志

## 参考资料

- [The Log: What every software engineer should know about real-time data's unifying abstraction](https://engineering.linkedin.com/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying)

- [Wikipedia # Log file](https://en.wikipedia.org/wiki/Log_file)

- [Wikipedia # Write-ahead logging](https://en.wikipedia.org/wiki/Write-ahead_logging)

- [ML Wiki # Undo/Redo Logging](http://mlwiki.org/index.php/Undo/Redo_Logging)

- [Intro to undo/redo logging](http://www.mathcs.emory.edu/~cheung/Courses/554/Syllabus/6-logging/overview.html)

- [Recovering from a system crash using undo/redo-log](http://www.mathcs.emory.edu/~cheung/Courses/554/Syllabus/6-logging/undo-redo2.html)

- [undo log 与 redo log 原理分析](https://zhuanlan.zhihu.com/p/35574452)
