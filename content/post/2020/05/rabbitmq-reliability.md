---
title: "RabbitMQ 的可靠性"
date: 2020-05-04T11:54:46+08:00
draft: false
description: ""
tags: [rabbitmq, message broker, cluster, distributed]
categories: []
---

消息传递和集群。

<!--more-->

## 高级消息队列协议

众所周知，[RabbitMQ](https://www.rabbitmq.com/) 实现了 [AMQP（Advanced Message Queuing Protocol）](https://en.wikipedia.org/wiki/Advanced_Message_Queuing_Protocol)，准确来说是 AMQP 0-9-1，AMQP 是一种使符合要求的客户端可以与符合要求的消息代理（message broker）进行通信的一种消息传递协议，AMQP 的概念如下图所示：

![amqp.png](/img/rabbitmq/amqp.png)

生产者（producer）发布消息，消费者（consumer）消耗消息，生产者或发布者（publisher）通常无需关心以下几点：

- 消息将发送到哪些队列（queue）。

- 消息（message）被哪些消费者消费。

Exchange 接收生产者发布的消息并路由到队列，exchange 根据什么转发消息到队列？人类可以使用绑定（binding）来定义 queue 和 exchange 的关系以及提供消息路由规则。生产者只面向 exchange 发布消息，而消费者只面向 queue 消耗消息，因此常说 RabbitMQ **解耦生产者和消费者**。

值得一提的是，单独的 MySQL server 可以创建多个数据库，与此类似，单独的 RabbitMQ server 可以创建多个虚拟主机（virtual host），虚拟主机包含 queues 和 exchanges 以及 bindings，虚拟主机之间可相互隔离。

### Exchange

当成功安装了 RabbitMQ 并正常启动后，可以通过后台管理界面去直观认识这种消息代理，不难发现 RabbitMQ 提供了 4 种 exchange 类型：

![15672exchanges.png](/img/rabbitmq/15672exchanges.png)

Exchange 使用的路由算法取决于 exchange 类型和 binding 规则。

#### Direct exchange

如果一个 exchange 的类型是 direct，将一个 queue 绑定到该 exchange 时，要求附加一个名为 routing key 的参数，当一个携带 routing key 的消息到达该 exchange 时，该 exchange 将转发消息到相应的 queue（精确匹配 routing key）。

![exchange-direct.webp](/img/rabbitmq/exchange-direct.webp)

#### Fonout exchange

类型为 fonout 的一个 exchange 忽略 routing key，将消息广播到所有与该 exhange 绑定的 queue。

![exchange-fanout.png](/img/rabbitmq/exchange-fanout.webp)

#### Topic exchange

它与 dirct exchange 类似，绑定时要求设置 routing key，不同在于路由时 topic exchange 支持模糊匹配或正则表达式匹配 routing key。

#### Headers exchange

它忽略 routing key，路由是根据消息中的 header 和绑定时设置的 argument。

## 可靠的消息传递

基于消息的系统可能发生参差多态的故障，人类并不希望消息丢失。所谓可靠的消息传递，参考底层 TCP 可靠传输的基本思想，应用层的 RabbitMQ 是否也有确认、重传、超时等概念？

### 确认与回执

Publisher confirms 允许消息代理向发布者表明消息已收到或已处理，Consumer acknowledgements 允许消费者向消息代理表明消息已收到或已处理。**Acknowledgement 即是回执，简称 ack，消息代理的 ack 就是 publisher confirms，消费者的 ack 就是 consumer acknowledgements。**使用发布者确认或消费者回执至少可以保证一次消息传递不丢失消息，建议关闭自动 ack 或开启手动模式。

#### Publisher confirms

```java
Channel channel = connection.createChannel();
channel.confirmSelect();

channel.addConfirmListener((deliveryTag, multiple) -> {
    // code when message is confirmed
}, (deliveryTag, multiple) -> {
    // code when message is nack-ed
});
```

对于 Java 客户端而言，可以异步处理 publisher confirms，一是消息代理已收到消息或已处理消息的客户端回调方法，二是消息代理未收到消息或已丢失消息的客户端回调方法，丢失的消息仍可能传递到消费者，但是消息代理没法保证这一点。`long` deliveryTag 是在一个 `Channel` 中一次消息传递的标示符，它是单调递增的正整数。`boolean` multiple 为 true 则表示当前和 deliveryTag 之前的消息已收到或已处理。对于无法路由的消息，消息代理虽然也会回复（返回空队列列表），但是默认情况下无法路由的消息会被丢弃，除非发布消息时将 `boolean` mandatory 设为 true 或使用 [alternate exchange](https://www.rabbitmq.com/ae.html) 来备份。

```java
channel.addReturnListener(returnMessage -> {
    // to be notified of failed deliveries
    // when basicPublish is called with "mandatory" or "immediate" flags set
});
```

#### Consumer acknowledgements

```java
// this example assumes an existing channel instance

// 确认，ack > 0
channel.basicAck(deliveryTag, multiple);
// 否认，ack < 0
channel.basicNack(deliveryTag, multiple, requeue);
// 拒绝，ack < 0
channel.basicReject(deliveryTag, requeue)
```

消费者的回执可以是确认、否认、拒绝。不管是否认还是拒绝，如果 `boolean` requeue 为 false 则相应的消息将被消息代理丢弃，设为 true 则相应的消息将重新加入消息代理的队列，从而允许其它消费者消费。`boolean` multiple 为 true 表示否认或拒绝当前和 deliveryTag 之前的消息。确认则表示相应的消息已收到或已处理，消息代理将记录已推送的消息，也可以将其丢弃。如果消费者投递给消息代理的 ack 丢失了会发生什么？消息代理将重发。

### AMQP 事务

RabbitMQ 事务将可能大幅降低吞吐量，故一般不推荐使用。

> Using standard AMQP 0-9-1, the only way to guarantee that a message isn't lost is by using transactions -- make the channel transactional then for each message or set of messages publish, commit. In this case, transactions are unnecessarily heavyweight and decrease throughput by a factor of 250. To remedy this, a confirmation mechanism was introduced. It mimics the consumer acknowledgements mechanism already present in the protocol.

## 集群

旧文提到过[软件系统三大问题](https://h2cone.github.io/post/2020/03/distributed-cache/#%E8%BD%AF%E4%BB%B6%E7%B3%BB%E7%BB%9F%E4%B8%89%E5%A4%A7%E9%97%AE%E9%A2%98)，首先，RabbitMQ 集群如何保证可靠性？

捣鼓中......

## 参考资料

- [AMQP 0-9-1 Model Explained](https://www.rabbitmq.com/tutorials/amqp-concepts.html)

- [Messageing using AMQP](https://www.slideshare.net/rahula24/amqp-basic)

- [RabbitMQ # Consumer Acknowledgements and Publisher Confirms](https://www.rabbitmq.com/confirms.html)

- [RabbitMQ # Tutorials # Publisher Confirms](https://www.rabbitmq.com/tutorials/tutorial-seven-java.html)

- [rabbitmq 重复确认导致消息丢失](https://www.cnblogs.com/littleatp/p/6087856.html)

- [RabbitMQ # Reliability Guide](https://www.rabbitmq.com/reliability.html)

- [RabbitMQ # Clustering Guide](https://www.rabbitmq.com/clustering.html)

- [RabbitMQ # Cluster Formation and Peer Discovery](https://www.rabbitmq.com/cluster-formation.html)

- [harbur/docker-rabbitmq-cluster](https://github.com/harbur/docker-rabbitmq-cluster)
