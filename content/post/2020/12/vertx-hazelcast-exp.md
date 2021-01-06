---
title: "Vert.x 与 Hazelcast"
date: 2020-12-14T14:50:54+08:00
draft: false
description: ""
tags: [vertx, reactive, hazelcast, cluster, distributed, cache, java, network, i/o, netty, thread, async, event-driven]
categories: []
---

体验使用 Hazelcast 实现的 Vert.x 集群。

<!--more-->

## 前面的话

有一个项目使用了 Vert.x 3，没想到 v4.0.0 已经发布。

## 什么是 Vert.x

[Vert.x](https://vertx.io) 是用于在 JVM 上构建 **Reactive** 应用程序的工具包。

早在 2014 年[反应式宣言](https://www.reactivemanifesto.org)就提出反应式（Reactive）应用程序/软件系统应具有反应灵敏（Responsive）、回弹性（Resilient）、弹性（Elastic）、消息驱动（Message Driven）等特征，这些莫名其妙的要求可以归属于前文常常提到的[软件系统三大目标](https://h2cone.github.io/post/2020/03/distributed-cache/#%E8%BD%AF%E4%BB%B6%E7%B3%BB%E7%BB%9F%E4%B8%89%E5%A4%A7%E7%9B%AE%E6%A0%87)。

Vert.x 受到了 [Node.js](https://nodejs.org) 启发，推荐的编程范式是[事件驱动](https://en.wikipedia.org/wiki/Event-driven_programming)，[事件](https://en.wikipedia.org/wiki/Event_(computing))可以由软件、用户、系统产生或触发，处理事件的函数通常被称为 [Event Handler](https://en.wikipedia.org/wiki/Event_(computing)#Event_handler)。

```java
import io.vertx.core.AbstractVerticle;

public class Server extends AbstractVerticle {
  public void start() {
    vertx.createHttpServer().requestHandler(req -> {
      req.response()
        .putHeader("content-type", "text/plain")
        .end("Hello from Vert.x!");
    }).listen(8080);
  }
}
```

如上所示，使用 Vert.x 编写一个简单的 HTTP Server，其中 requestHandler 方法传入了用于处理请求事件的 Handler，Handler 表现为回调函数，即 [Call­back](https://en.wikipedia.org/wiki/Callback_(computer_programming))；其中 listen 方法是非阻塞方法，线程调用非阻塞方法不会被阻塞在该方法，而是继续执行其它代码；非阻塞函数有时被称为[异步](https://en.wikipedia.org/wiki/Asynchrony_(computer_programming))函数，返回值可以被称为异步结果，仅使用 Callback 处理异步结果可能导致嵌套和凌乱的代码，被称为[回调地狱](callback-hell)。Vert.x 支持 [Fu­tures/Promises](https://en.wikipedia.org/wiki/Futures_and_promises) 和 [RxJava](https://vertx.io/docs/vertx-rx/java2/)，前者用于优雅地链式异步操作，后者用于高级反应式编程。

Vert.x 的非阻塞 I/O 基于 [Netty](https://h2cone.github.io/post/2020/03/network_nio/#netty)，在此之上构建 [Vert.x Core](https://vertx.io/docs/vertx-core/java/) 和 Web 后端技术栈：反应式数据库驱动、消息传递、事件流、集群、指标度量、分布式追踪等，详情请见 [Vert.x Documentation](https://vertx.io/docs/)。

![Overview_of_the_structure_of_a_Vert.x_application](/img/vertx/Overview_of_the_structure_of_a_Vert.x_application.png)

Vert.x 的事件模型延用 Netty 的 [Event Loop](https://h2cone.github.io/post/2020/03/network_nio/#eventloop)，欲了解来龙去脉可从 [网络·NIO](https://h2cone.github.io/post/2020/03/network_nio/) 开始。

![Processing_events_using_an_event_loop](/img/vertx/Processing_events_using_an_event_loop.png)

[Verticle](https://vertx.io/docs/vertx-core/java/#_verticles) 是 Vert.x 中的基本处理单元，Verticle 实例之间通过 [Event Bus](https://vertx.io/docs/vertx-core/java/#event_bus) 通信。Java 传统的并发模型是共享内存多线程（shared memory multithreading），如同前文 [多线程·并发编程](https://h2cone.github.io/post/2020/02/thread_concurrent/) 所说，但是计算机世界还存在着其它并发模型，例如 [CSP](https://en.wikipedia.org/wiki/Communicating_sequential_processes) 和 [Actor model](https://en.wikipedia.org/wiki/Actor_model)，**Verticles 就是宽松的 Actors**。

![event-bus](/img/vertx/event-bus.png)

构建反应式应用程序/软件系统并非 Vert.x 不可，只不过 Netty 的 APIs 更底层；云原生（cloud native）时代的 [Quarkus](https://quarkus.io) 技术栈[支持反应式](https://quarkus.io/guides/getting-started-reactive)，Java 用户使用最多的 [Spring](https://spring.io) 技术栈也[支持反应式](https://spring.io/reactive)，非一般场景可以考虑 [Akka](https://akka.io)。

## 什么是 Hazelcast IMDG

[Hazelcast](https://hazelcast.org/) 有一个开源分布式内存对象存储（in-memory object store），名为 [Hazelcast IMDG](https://hazelcast.org/imdg/)，IMDG 是 In-Memory Data Grid 的缩写，IMDG 与[内存数据库](https://en.wikipedia.org/wiki/In-memory_database) 有所不同，后者通常需要用户处理对象到关系的映射（ORM），前者支持各种各样的内存数据结构，比如 Map、Set、List、MultiMap、RingBuffer、HyperLogLog 等。

Hazelcast IMDG 的架构与分布式协调服务——[Zookeeper](https://zookeeper.apache.org/)、分布式 Key-Value 存储——[etcd](https://etcd.io/)、端到端服务发现解决方案——[Consul](https://github.com/hashicorp/consul) 截然不同，它的定位更接近[分布式缓存](https://h2cone.github.io/post/2020/03/distributed-cache/)，并且无需 Server 端，只需 Client 端的点到点通信（P2P）。

![hazelcast-imdg-overview](/img/hazelcast/hazelcast-imdg-overview.png)

Hazelcast 集群（Hazelcast Cluster）成员（Hazelcast Member）之间为什么需要通信？

Hazelcast 成员之间**共享数据**的机制是[数据分区](https://docs.hazelcast.org/docs/latest/manual/html-single/index.html#data-partitioning)与[数据复制](https://docs.hazelcast.org/docs/latest/manual/html-single/index.html#consistency-and-replication-model)，两者结合在一起的图像可以先参考[为什么分区](https://h2cone.github.io/post/2020/07/from-mysql-to-tidb/#%E4%B8%BA%E4%BB%80%E4%B9%88%E5%88%86%E5%8C%BA)。默认情况下，Hazelcast 提供 271 个分区，为每个分区创建单一拷贝/副本，可配置为多副本。

![4NodeCluster](/img/hazelcast/4NodeCluster.jpg)

上图是 4 成员/结点的 Hazelcast 集群的示意图，假设分区编号从 P_1 到 P_136，黑色编号分区代表主副本（primary replicas），蓝色编号分区代表备副本（backup replicas），数据复制方向为主到备。

数据分区与数据复制对用户透明是现代分布式存储的基本特性。添加成员到 Hazelcast 集群时[与 Redis 不同](https://h2cone.github.io/post/2020/03/distributed-cache/#%E6%95%B0%E6%8D%AE%E5%88%86%E7%89%87)，Hazelcast 使用[一致性哈希算法](https://en.wikipedia.org/wiki/Consistent_hashing)，仅移动最小数量的分区即可横向扩展。

Hazelcast 如何保证一致性与可用性？

Hazelcast 提供了具有不同数据结构实现的 AP 和 CP 功能。根据 CAP (**C**onsistency, **A**vailability and **P**artition Tolerance) 经验法则，Hazelcast 的 [AP 数据结构](https://docs.hazelcast.org/docs/latest/manual/html-single/index.html#hazelcasts-replication-algorithm)侧重可用性，而 Hazelcast 的 [CP 子系统](https://docs.hazelcast.org/docs/latest/manual/html-single/index.html#cp-subsystem)则侧重一致性。

## 使用 Hazelcast 实现 Vert.x 集群

Vert.x 集群无需注册中心（Service Registry）即可建立，因为 Vert.x 实例之间可以通过 Hazelcast Client Library 相互[发现（Discovery）](https://en.wikipedia.org/wiki/Service_discovery)。

![Vert.x_Architecture_(Component)_Diagram](/img/vertx/Vert.x_Architecture_(Component)_Diagram.png)

使用 [Hazelcast Cluster Manager](https://vertx.io/docs/vertx-hazelcast/java/) 可以降低 Vert.x 集成/整合 Hazelcast 的成本。默认情况下，如果不指定外部配置文件，那么集群管理器由打包在 vertx-hazelcast-4.0.0.jar 内的 [default-cluster.xml](https://github.com/vert-x3/vertx-hazelcast/blob/master/src/main/resources/default-cluster.xml) 配置，其中默认的发现机制是 [Multicast](https://en.wikipedia.org/wiki/Multicast)。

![1920px-Multicast.svg](/img/network/1920px-Multicast.svg.png)

如上图所示，红色成员发送特定报文到监听特定端口的一组绿色成员，以此类推，发现彼此。

```yml
hazelcast:
  network:
    join:
      multicast:
        enabled: true
        multicast-group: 224.2.2.3
        multicast-port: 54327       # UDP port
        multicast-time-to-live: 32
        multicast-timeout-seconds: 2
        trusted-interfaces:
          - 192.168.1.102
```

使用 Multicast 最常见的传输层协议是 [UDP](https://en.wikipedia.org/wiki/User_Datagram_Protocol)；然而，**不建议在生产环境使用 Multicast 发现**，因为 UDP 在生产环境可能被阻止（出于安全考虑）并且其它发现机制更加精确，例如 [TCP/IP 发现](https://docs.hazelcast.org/docs/latest/manual/html-single/#discovering-members-by-tcp)，其它可参考 [Discovery Mechanisms](https://docs.hazelcast.org/docs/latest/manual/html-single/#discovery-mechanisms)。

```yml
hazelcast:
  network:
    join:
      tcp-ip:
        enabled: true
        member-list:
          - machine1
          - machine2
          - machine3:5799
          - 192.168.1.0-7
          - 192.168.1.21
```

形成了集群之后，集群成员之间的通信始终通过 [TCP/IP](https://en.wikipedia.org/wiki/Internet_protocol_suite) 进行；方便展示起见，下文的程序采用简化的服务生产者（Provider）与服务消费者（Consumer）模式：

![ccp](/img/pattern/ccp.png)

首先是服务生产者，该 Verticle 的启动方法（start）内仅仅是订阅/消费（consumer）EventBus 中的特定事件。

```java
public class DefaultProvider extends AbstractVerticle {
  private static final Logger log = LoggerFactory.getLogger(DefaultProvider.class);

  @Override
  public void start(Promise<Void> startPromise) throws Exception {
    vertx.eventBus().<JsonObject>consumer(BusAddress.TEST_REQUEST, msg -> {
      JsonObject body = msg.body();
      log.debug("consume from {}, message body: {}", BusAddress.TEST_REQUEST, body);
      if (Objects.nonNull(body)) {
        body.put("consumed", true);
      }
      msg.reply(body);
    });
    vertx.eventBus().<JsonObject>consumer(BusAddress.TEST_SEND, msg -> {
      JsonObject body = msg.body();
      log.debug("consume from {}, message body: {}", BusAddress.TEST_SEND, body);
    });
    vertx.eventBus().<JsonObject>consumer(BusAddress.TEST_PUBLISH, msg -> {
      JsonObject body = msg.body();
      log.debug("consume from {}, message body: {}", BusAddress.TEST_PUBLISH, body);
    });
  }
}
```

之所以说特定事件是由于服务消费者将事件发送到 EventBus 中的特定地址。

```java
public interface BusAddress {
  String TEST_REQUEST = "test.request";

  String TEST_SEND = "test.send";

  String TEST_PUBLISH = "test.publish";
}
```

然后是服务消费者，该 Verticle 作为 HTTP Server，同时演示了 request、send、publish 三种发送事件到 EventBus 方法。

```java
public class HttpServer extends AbstractVerticle {
  private static final Logger log = LoggerFactory.getLogger(HttpServer.class);

  @Override
  public void start(Promise<Void> startPromise) throws Exception {
    ConfigRetriever retriever = ConfigRetriever.create(vertx);
    retriever.getConfig(json -> {
      JsonObject config = json.result();
      Integer port = config.getInteger("http.port", 8080);

      Router router = Router.router(vertx);
      router.get("/hello").handler(this::hello);
      router.post().handler(BodyHandler.create());
      router.post("/test/request").handler(this::testRequest);
      router.post("/test/send").handler(this::testSend);
      router.post("/test/publish").handler(this::testPublish);

      vertx.createHttpServer()
        .requestHandler(router)
        .listen(port)
        .onSuccess(server -> {
            log.info("HTTP server started on port " + server.actualPort());
            startPromise.complete();
          }
        ).onFailure(startPromise::fail);
    });
  }

  private void testPublish(RoutingContext context) {
    JsonObject reqBody = context.getBodyAsJson();
    log.debug("request body: {}", reqBody);
    vertx.eventBus().publish(BusAddress.TEST_PUBLISH, reqBody);
    context.json(reqBody);
  }

  private void testSend(RoutingContext context) {
    JsonObject reqBody = context.getBodyAsJson();
    log.debug("request body: {}", reqBody);
    vertx.eventBus().send(BusAddress.TEST_SEND, reqBody);
    context.json(reqBody);
  }

  private void testRequest(RoutingContext context) {
    JsonObject reqBody = context.getBodyAsJson();
    log.debug("request body: {}", reqBody);
    vertx.eventBus().<JsonObject>request(BusAddress.TEST_REQUEST, reqBody, response -> {
      if (response.succeeded()) {
        Message<JsonObject> msg = response.result();
        JsonObject msgBody = msg.body();
        log.debug("reply from {}, message body: {}", BusAddress.TEST_REQUEST, msgBody);
        context.json(msgBody);
      } else {
        log.error("failed to test request", response.cause());
      }
    });
  }

  private void hello(RoutingContext context) {
    String address = context.request().connection().remoteAddress().toString();
    MultiMap queryParams = context.queryParams();
    String name = queryParams.contains("name") ? queryParams.get("name") : "unknown";
    context.json(
      new JsonObject()
        .put("name", name)
        .put("address", address)
        .put("message", "Hello " + name + " connected from " + address)
    );
  }
}
```

最后，仍然是为了方便展示起见，提供一个简化的程序启动脚本。

```bash
#!/bin/bash

bin_dir=$(dirname "$0")

start() {
  case $1 in
  consumer)
    java -jar "$bin_dir"/../consumer/target/consumer-1.0.0-SNAPSHOT-fat.jar -cluster
    ;;
  provider)
    java -jar "$bin_dir"/../provider/target/provider-1.0.0-SNAPSHOT-fat.jar -cluster
    ;;
  *)
    echo "Unknown module: $1"
    exit 1
    ;;
  esac
}

stop() {
  jcmd | grep "$1-1.0.0-SNAPSHOT-fat.jar" | awk '{print $1}' | xargs -I {} kill -9 {}
}

stopAll() {
  stop consumer
  stop provider
}

case $1 in
start)
  start "$2"
  ;;
stop)
  stop "$2"
  ;;
restart)
  stop "$2"
  start "$2"
  ;;
down)
  stopAll
  ;;
*)
  echo "Usage: $0 {start <module>|stop <module>|restart <module>|down}"
  ;;
esac
```

假如先启动其中一个模块，比如启动服务生产者。

```shell
% ./dev.sh start provider
```

从它的日志会发现它已经成为 Hazelcast 集群的唯一成员：

```shell
Members {size:1, ver:1} [
	Member [192.168.0.100]:5701 - 0d97d436-ab4f-432b-abb6-10975e224044 this
]
```

紧接着启动服务消费者。

```shell
% ./dev.sh start consumer
```

服务消费者的视角：

```shell
Members {size:2, ver:2} [
	Member [192.168.0.100]:5701 - 0d97d436-ab4f-432b-abb6-10975e224044 this
	Member [192.168.0.100]:5702 - 12740655-5ee8-4228-a723-112c2992b290
]
```

服务生产者的视角：

```shell
Members {size:2, ver:2} [
	Member [192.168.0.100]:5701 - 0d97d436-ab4f-432b-abb6-10975e224044
	Member [192.168.0.100]:5702 - 12740655-5ee8-4228-a723-112c2992b290 this
]
```

两者相互发现了对方，但是，它们是否能正常通信？

```shell
% curl "localhost:8888/hello?name=huangh"                    
{"name":"huangh","address":"0:0:0:0:0:0:0:1:51328","message":"Hello huangh connected from 0:0:0:0:0:0:0:1:51328"}

% curl localhost:8888/test/request -d "{\"name\":\"huangh\"}"
{"name":"huangh","consumed":true}
```

完整代码已发布，请参考 [vertx-hazelcast-exp](https://github.com/h2cone/vertx-hazelcast-exp)。

## 写在最后

[Hazelcast Management Center](https://docs.hazelcast.org/docs/management-center/latest/manual/html/index.html) 可用于**可视化**监控和管理 Vert.x 集群。

> 本文首发于 https://h2cone.github.io

## 参考资料

- [Eclipse Vert.x and reactive in just a few words](https://vertx.io/introduction-to-vertx-and-reactive/)

- [Vert.x in Action: Asynchronous and Reactive Java](https://livebook.manning.com/book/vertx-in-action/)

- [Understanding Vert.x Architecture - Part I: Inside Vert.x. Comparison with Node.js](https://www.cubrid.org/blog/3826505)

- [Understanding Vert.x Architecture - Part II](https://www.cubrid.org/blog/3826515)

- [Understanding Vert.x: Event Loop](https://alexey-soshin.medium.com/understanding-vert-x-event-loop-46373115fb3e)

- [Understanding Vert.x: Event Bus](https://alexey-soshin.medium.com/understanding-vert-x-event-bus-c31759757ce8)

- [hazelcast/hazelcast](https://github.com/hazelcast/hazelcast)

- [hazelcast/hazelcast-code-samples](https://github.com/hazelcast/hazelcast-code-samples)

- [hazelcast/hazelcast-go-client](https://github.com/hazelcast/hazelcast-go-client)

- [Hazelcast IMDG Reference Manual # Overview](https://docs.hazelcast.org/docs/latest/manual/html-single/index.html#hazelcast-overview)

- [Hazelcast IMDG Reference Manual # Appendix F: Frequently Asked Questions](https://docs.hazelcast.org/docs/latest/manual/html-single/#frequently-asked-questions)

- ~~[Hazelcast # Vert.x Cluster](https://hazelcast.com/blog/vert-x-cluster/)~~

- [etcd versus other key-value stores](https://etcd.io/docs/v3.4.0/learning/why/)

- [Reactiverse](https://reactiverse.io/)

- [Vert.x Awe­some](https://github.com/vert-x3/vertx-awesome)

- [eclipse-vertx/vert.x](https://github.com/eclipse-vertx/vert.x)

- [Advanced Vert.x Guide](http://www.julienviet.com/advanced-vertx-guide/)

- [Vert.x Examples](https://github.com/vert-x3/vertx-examples)

- [Building a Vert.x Native Image](https://how-to.vertx.io/graal-native-image-howto/)
