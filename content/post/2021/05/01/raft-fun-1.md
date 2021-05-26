---
title: "Raft 的乐趣（一）"
date: 2021-05-22T11:00:07+08:00
draft: true
description: ""
tags: [raft, consensus, algorithm]
categories: []
---

也许是最通俗易懂的共识算法。

<!--more-->

## 问题导向

- 共识是什么？共识算法的应用场景？

- 传统的数据分区与数据复制如何保证可靠性？换言之，如何容错（可用性与一致性）？

- 为什么需要 Leader、Primary、Master 等角色及其选举？

- Follower 何时转为 Candidate？

- 允许 Candidates 并发请求投票？结点如何响应？

- Candidate 何时转为 Leader？

- 如何防止脑裂？

- 写请求仅由 Leader 处理？为什么 Leader 执行来自客户端的命令前先写日志？Leader/Follwer 何时提交日志条目？又何时应用数据变更（执行命令）？

- 为什么需要复制日志？

- 结点之间如何通信？

- 基于 Raft 的系统如何保证可靠性？换言之，如何容错（可用性与一致性）？

> 本文首发于 https://h2cone.github.io

## 参考资料

- [Raft - Understandable Distributed Consensus](http://thesecretlivesofdata.com/raft/)

- [Consensus (computer science)](https://en.wikipedia.org/wiki/Consensus_(computer_science))
