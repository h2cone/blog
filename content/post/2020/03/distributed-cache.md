---
title: "分布式缓存"
date: 2020-03-24T17:40:48+08:00
draft: true
description: ""
tags: [redis, distributed, cache]
categories: []
---

圈养 Redis 集群。

<!--more-->

## 铺垫

### 存储层次结构

![存储层次结构](/img/csapp/存储层次结构.png)

- 自下而上，更小更快。

- 自顶向下，更大更慢。

- **上层是下层的（高速）缓存**。

### 软件系统三大问题

问题 | 解释 | 期望
:---: | :---: | :---:
可靠性 | 容错能力 | 硬件故障、软件错误、人为失误发生时继续正常运作
可扩展性 | 应对负载增加的能力 | 负载增加时保持良好性能或高性能
可维护性 | 运维和开发的难易程度| 既简单又好拓展

## Redis cluster

单一独立的 [Redis](https://redis.io/) 结点，虽然它真的[很快](https://redis.io/topics/benchmarks)（未来将开新篇章解释），但是也有上限，性能提升总将遇到天花板，而且单点故障将导致一段时间服务不可用。

Redis 集群如何解决可靠性问题和扩展性问题？

- 数据在多个 Redis 结点之间自动**分片（shard）**。

- Redis 集群可以在分区期间提供一定程度的**可用性（availability）**。

- 水平扩展 Redis。

### 数据分片

Redis 集群不使用[一致性哈希](https://en.wikipedia.org/wiki/Consistent_hashing)，而是使用**哈希槽（hash slot）**。

![hash-slot](/img/distributed-cache/hash-slot.png)

如上图所示，Redis 集群中的结点（node）负责哈希槽的子集，向集群插入一个键（key）时，只是计算给定键的 [CRC16](https://en.wikipedia.org/wiki/Cyclic_redundancy_check) 并取 16384 的模来将给定键映射到哈希槽的一个子集。

使用哈希槽可以“轻松”在集群中添加结点到删除结点。若增加一个结点 D，则从 A、B、C 移动一些哈希槽到 D，同理，若删除一个结点 A，则从 A 移动哈希槽到结点 B、C、D，当 A 为空可被完全从集群移除。而且，添加结点、删除结点、更改结点的哈希槽的百分比都不要求集群暂停运作，不需要任何停机时间。当然，我们可以使用称为 hash tags 的概念来强制多个 key 映射到同一个哈希槽的子集。

### 可用性与一致性

Redis 集群使用**主从模型（master-slave model）** 实现故障转移。

![failover_copy](/img/distributed-cache/failover_copy.png)

如上图所示，在集群创建时或稍后，我们给每个主结点添加从结点，例如 B 是主结点，B1 是它的从结点，B1 的哈希槽是 B 的哈希槽的副本。当 B 发生故障，集群将提升 B1 为新主结点，继续提供服务。以此类推，当有若干主结点发生故障时，它们的从结点将替代它们成为新主结点，以此提供一定程度的可用性。

为什说是一定程度的可用性，考虑以下的场景，集群极可能不能正常运作。

- 一对主从结点同时故障。

- 超过半数的结点发生了故障。

Redis 集群不保证**强一致性（strong consistency）**。[Kafka](https://kafka.apache.org/) 的作者 Jay Kreps 曾经说过：

> Is it better to be alive and wrong or right and dead?

在可用性与一致性天平之间，Redis 集群侧重于可用性，当一个客户端连接集群并写入键，丢失写（lose writes）可能发生，因为 Redis 使用异步复制（asynchronous replication）。

1. 客户端将给定键写入主结点 B

2. 主结点 B 发送 OK 给客户端

3. 从 B 复制数据到从结点 B1、B2、B3......

注意，上面操作 2 和操作 3 非阻塞，即客户端写的同时，主结点 B 执行数据复制任务（通常只需复制命令），而不是阻塞直到所有数据复制完成再回复客户端，还因为数据复制必定存在延迟，当 B 发生故障停止复制且 B 的从结点提升为新主结点，新主结点将可能不存在客户端已写入的键。

这也是一种在性能与一致性之间的权衡（trade-off）。

即使 Redis 支持同步复制，也有其它更复杂的故障导致主结点与从结点数据不一致，从结点提升为主结点时，客户端将可能找不到目标键或读取了脏数据。比如，当客户端发送一次足够大的键或足够多的键到一个主结点，以至于该主结点的从结点有充分时间提升为新主结点，旧主结点将拒绝接受键，且新主结点不存在客户端写入的键。

这里所说的不一致与[非线程安全](https://h2cone.github.io/post/2020/02/thread_concurrent/#%E9%9D%9E%E7%BA%BF%E7%A8%8B%E5%AE%89%E5%85%A8)中所说的内存一致性错误为同一本质，未来将开新篇章谈谈分布系统的一致性和可用性。

### 圈养

敬请期待。

## 参考资料

- [Redis cluster tutorial](https://redis.io/topics/cluster-tutorial)

- [Redis Cluster Specification](https://redis.io/topics/cluster-spec)

- [A Few Notes on Kafka and Jepsen](https://blog.empathybox.com/post/62279088548/a-few-notes-on-kafka-and-jepsen)
