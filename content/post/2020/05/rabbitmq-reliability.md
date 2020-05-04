---
title: "RabbitMQ 的可靠性"
date: 2020-05-04T11:54:46+08:00
draft: true
description: ""
tags: []
categories: []
---

<!--more-->

分析可靠性之前，不妨先回顾一下 RabbitMQ。

## 高级消息队列协议

[RabbitMQ](https://www.rabbitmq.com/) 实现了 [AMQP（Advanced Message Queuing Protocol）](https://en.wikipedia.org/wiki/Advanced_Message_Queuing_Protocol)，AMQP 是一种使符合要求的客户端可以与符合要求的消息代理（broker）进行通信的一种消息传递协议，AMQP 的概念如下图所示：

![amqp.png](/img/mq/amqp.png)

生产者（producer）发布消息，消费者（consumer）消费消息，生产者通常无需关心以下几点：

- 消息将发送到哪些队列（queue）。

- 消息（message）被哪些消费者消费。

Exchange 接收生产者发布的消息并路由到队列，exchange 根据什么转发消息到队列？人类可以使用绑定（binding）来定义 queue 和 exchange 的关系以及提供消息路由规则。生产者只面向 exchange 发布消息，而消费者只面向 queue 消费消息，因此常说 RabbitMQ 解耦了生产者和消费者。

当成功安装了 RabbitMQ 并正常启动后，可以通过后台管理界面去直观认识橙色兔子，不难发现 RabbitMQ 提供了 4 种 exchange 类型：

![15672exchanges.png](/img/mq/15672exchanges.png)

Exchange 使用的路由算法取决于 exchange 类型和 binding 规则。

- Direct exchange。如果一个 exchange 的类型是 direct，将一个 queue 绑定到该 exchange 时，要求附加一个名为 routing key 的参数，当一个携带 routing key 的消息到达该 exchange 时，该 exchange 将转发消息到相应的 queue（精确匹配 routing key）。

![exchange-direct.webp](/img/mq/exchange-direct.webp)

- Fonout exchange。类型为 fonout 的一个 exchange 忽略 routing key，将消息广播到所有与该 exhange 绑定的 queue。

![exchange-fanout.png](/img/mq/exchange-fanout.webp)

- Topic exchange。它与 dirct exchange 类似，绑定时要求设置 routing key，不同在于路由时 topic exchange 支持模糊匹配或正则表达式匹配 routing key。

- Headers exchange。它忽略 routing key，路由是根据消息中的 header 和绑定时设置的 argument。

## 可靠的消息传递

所谓可靠的消息传递，类比 TCP 可靠传输的基本思想，即确认、重传、超时等概念。

### 确认机制

### 补偿机制

## 集群

## 参考资料

- [AMQP 0-9-1 Model Explained](https://www.rabbitmq.com/tutorials/amqp-concepts.html)

- [Messageing using AMQP](https://www.slideshare.net/rahula24/amqp-basic)

- [RabbitMQ # Consumer Acknowledgements and Publisher Confirms](https://www.rabbitmq.com/confirms.html)
