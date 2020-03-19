---
title: "实现 RPC"
date: 2019-12-25T14:57:57+08:00
draft: false
description: ""
tags: [java, rpc, netty, spring boot]
categories: []
---

基于 Netty 和 Spring Boot。

<!--more-->

## 前言

RPC 是远程过程调用，分布在不同机器上的进程能够调用对方的函数或方法。RPC 框架的远程调用通常伪装成本地调用，但是本地调用一般只发生在同一机器的同一进程，执行效率比前者高，却不能跨机器交换数据。在微服务架构中，服务或进程之间的通信不可避免，常见的 HTTP Request/Response 可以认为是一种 RPC，它的优势是几乎所有编程语言都支持，[REST](https://en.wikipedia.org/wiki/Representational_state_transfer) 依然很流行，但是 HTTP 不是一个精简的协议，而且序列化协议往往使用文本协议，比如 JSON 或 XML。如果对服务的吞吐率敏感，自定义 TCP 协议或序列化协议的 RPC 可能更适合后端服务之间的通信。谷歌的 [gRPC](https://grpc.io/) 就是基于 [HTTP/2](https://developers.google.com/web/fundamentals/performance/http2) 的 RPC，还采用了二进制编码的 [Protocol Buffers](https://developers.google.com/protocol-buffers) 作为序列化协议。

Java 生态中主流的 RPC 框架基于 [Netty](https://netty.io/) 。比如，谷歌开源的 [grpc-java](https://github.com/grpc/grpc-java) 以及起源于阿里巴巴的 [Apache Dubbo](https://dubbo.apache.org/)。官方解释说 Netty 是一个**异步**、**事件驱动**网络应用程序框架，用于快速开发可维护的**高性能**协议服务器端和客户端。它很受欢迎，据说 [Elasticsearch](https://www.elastic.co/)、[Cassandra](http://cassandra.apache.org)、[Flink](https://flink.apache.org/) 以及 [Spark](https://spark.apache.org/) 都采用了 Netty，值得一提的是 [Vert.x](https://vertx.io/) 也是基于 Netty，这篇文章能够完成是因为选择了 Netty。

Netty 高性能的原因之一是使用了 [Java NIO](https://docs.oracle.com/javase/8/docs/api/java/nio/package-summary.html)。传统的 Java IO 是阻塞 IO，一般对应着 Unix 网络编程的五种 IO 模型中的 blocking IO，一个连接由一个线程处理，线程数随着连接数增加而增加，当需要运行的线程数足够多，线程并不便宜，不仅占用大量的空间，在高负载下操作系统内核需要花费大量的时间在线程调度上，可以读写的 Socket 占少数，大量的线程处于等待数据的状态，吞吐率自然不高。一种缓解办法是采用[线程池](https://en.wikipedia.org/wiki/Thread_pool)，比如 [Tomcat](http://tomcat.apache.org/) 就是这么做的，还可以使用 [Nginx](https://www.nginx.com/) 负载均衡并水平扩展 Tomcat 以此应对高并发场景。更好的办法可能是使用 Java NIO，对应着 Unix 网络编程的五种 IO 模型中的 IO multiplexing，Nginx 就采用了 IO 多路复用，致力于用更少的线程处理更多的连接。Java NIO 有三个重要概念，分别是 Channel、Buffer、Selector，其中 Channel 是一个双向的数据读写通道，可用来表示 Socket，数据读写经过 Buffer，Selector 用于轮询多个 Channel，但是 Java NIO 编程过于复杂，因此出现了高效且可靠的 Netty。

了解更多，推荐以下文章：

- [小白科普：Netty有什么用？](https://mp.weixin.qq.com/s?__biz=MzAxOTc0NzExNg==&mid=2665514049&idx=1&sn=5c0b2c44e21ae15b62057f7a9531be19&chksm=80d67c02b7a1f514a66b5351357aa3a1bfe67c763d337bd897980503b783724ce566af94a5a4&scene=21#wechat_redirect)

- [服务化基石之远程通信系列三：I/O模型](https://mp.weixin.qq.com/s/uDgueoMIEjl-HCE_fcSmSw)

- [IO - 同步，异步，阻塞，非阻塞 （亡羊补牢篇）](https://blog.csdn.net/historyasamirror/article/details/5778378)

- [Java IO 的自述](https://mp.weixin.qq.com/s?__biz=MzAxOTc0NzExNg==&mid=2665513547&idx=1&sn=51044826a7a8dd5294c129389d62748c&chksm=80d67a08b7a1f31e87b14046a31ff2560e802937d32b19f14b0b53ac747180197c9a401df4bb&scene=21#wechat_redirect)

- [Http Server ： 一个差生的逆袭](https://mp.weixin.qq.com/s?__biz=MzAxOTc0NzExNg==&mid=2665513467&idx=1&sn=178459f4bb9891c9cf471a28e7c340be&chksm=80d679b8b7a1f0aea8f6e3f09acb6969993825753170dc3db63f8ef35c95cce98aa40a0c7097&scene=21#wechat_redirect)

## 三角

微服务架构下，各个程序被分发部署到各个机器上运行，多个进程可能是同一程序代码，进程间通信需要知道彼此的位置从而建立连接。一个连接可以用（本地 IP，本地端口，远程 IP，远程端口，协议）表示，这里的协议通常是 TCP 或 UDP。那么，如何确定位置呢？比如，有两个微服务 A 和 B 部署在不同的机器上，A 服务需要调用 B 服务的方法，把具体的地址和端口写死是不可能的，因为不知道下次 B 服务会部署到哪台机器上。想象一下我们在浏览器输入域名并成功访问一个网站，并不需要知道网站的 IP，因为浏览器帮我们向 DNS 发送一个 UDP 包：根据域名查询 IP。俗话说“计算机科学领域的任何问题都可以通过增加一个中间层来解决”，我们引入注册点或注册中心，它提供根据服务名查询服务位置的功能，服务名对应的位置信息则来源于服务向注册中心注册自身的位置信息。

![triangle](/img/implementing-rpc/rpc_triangle.png)

## 开始

如上文所说，RPC 可由三个模块组成，分别是 Client，Registry，Server，因此问题就变成了如何用 Netty 让三者互动起来。简单流程是 Client 调用 Server 时先询问 Registry 被调用方的位置，如果 Server 提前向 Registry 注册了自身位置，Client 就能获取到 Server 的位置，从而建立连接，Client 向 Server 请求，Server 则响应 Client。

体验了 [Netty 用户指南](https://netty.io/wiki/user-guide-for-4.x.html) 之后，开始实现 RPC。

```
└── rpcnetty
    ├── Request.java
    ├── Response.java
    ├── RpcHandler.java
    ├── client
    │   ├── RpcCaller.java
    │   ├── RpcClient.java
    │   ├── RpcClientChannelInitializer.java
    │   └── RpcClientHandler.java
    ├── codec
    │   ├── RequestDecoder.java
    │   ├── RequestEncoder.java
    │   ├── ResponseDecoder.java
    │   └── ResponseEncoder.java
    ├── common
    │   ├── InetUtils.java
    │   ├── JacksonUtils.java
    │   ├── PrimitiveUtils.java
    │   └── RetrofitUtils.java
    ├── registry
    │   ├── Service.java
    │   ├── ServiceRegistry.java
    │   ├── consul
    │   │   ├── AgentServiceApi.java
    │   │   ├── ConsulRegistry.java
    │   │   └── ConsulService.java
    │   └── zk
    └── server
        ├── RpcExecutor.java
        ├── RpcServer.java
        ├── RpcServerChannelInitializer.java
        ├── RpcServerHandler.java
        └── ServerExecutor.java
```

Server 正常启动。

```java
public void start() {
    int port = service.getPort();
    if (port <= 0) {
        port = Integer.parseInt(System.getProperty("port", "8080"));
    }
    if (bossGroup == null && workerGroup == null) {
        bossGroup = new NioEventLoopGroup();
        workerGroup = new NioEventLoopGroup();
        try {
            // Server 设置。
            ServerBootstrap bootstrap = new ServerBootstrap();
            bootstrap.group(bossGroup, workerGroup)
                    .channel(NioServerSocketChannel.class)
                    .handler(new LoggingHandler(LogLevel.INFO))
                    .childHandler(new RpcServerChannelInitializer(executors))
                    .option(ChannelOption.SO_BACKLOG, 128)
                    .childOption(ChannelOption.SO_KEEPALIVE, true);

            // 遍历网卡获取第一个非回环地址，端口则由使用者配置。
            InetAddress address = InetUtils.getFirstNonLoopbackAddress();
            service.setHost(null == address ? "127.0.0.1" : address.getHostAddress());

            // 服务注册。
            registry.register(service);

            // 绑定地址和端口并启动后开始接受连接，直到连接关闭。
            ChannelFuture future = bootstrap.bind(address, port).sync();
            future.channel().closeFuture().sync();
        } catch (InterruptedException e) {
            log.error("Server failed to start", e);
        } finally {
            shutdown();
        }
    }
}
```

Client 主动连接 Server。

```java
private Channel connect(String host, int port) {
    try {
        // Client 设置。
        Bootstrap bootstrap = new Bootstrap();
        bootstrap.group(workerGroup)
                .channel(NioSocketChannel.class)
                .handler(initializer.encoder(encoder)
                        .decoder(new ResponseDecoder())
                        .handler(handler))
                .option(ChannelOption.SO_KEEPALIVE, true);
        // 等待连接完成。
        return bootstrap.connect(host, port).sync().channel();
    } catch (InterruptedException e) {
        log.error("Failed to connect " + host + ":" + port, e);
        return null;
    }
}
```

Client 请求 Server。

```java
public Response sendRequest(Request request, Channel channel) {
    // 把请求数据写入通道。
    channel.writeAndFlush(request);
    Long id = request.getId();
    // 如果当前请求没有对应的响应。
    responses.putIfAbsent(id, new LinkedBlockingQueue<>(1));
    Response response;
    try {
        // 通过 ID 获取响应，阻塞除非获取完成或已超时。
        response = responses.get(id).poll(timeout, timeUnit);
        if (response == null) {
            channel.close().sync();
            response = Response.notOk("cause: timeout");
        }
    } catch (InterruptedException e) {
        log.error("Send request failed", e);
        response = Response.notOk("cause: " + e);
    } finally {
        responses.remove(id);
    }
    return response;
}
```

Client 获取响应完成前。

```java
@Override
public void channelRead(ChannelHandlerContext ctx, Object msg) throws Exception {
    Response response = (Response) msg;
    // 获取响应并保存。
    BlockingQueue<Response> queue = responses.get(response.getId());
    if (queue != null) {
        queue.add(response);
    }
}
```

Server 响应 Client。

```java
@Override
public void channelRead(ChannelHandlerContext ctx, Object msg) throws Exception {
    Request request = (Request) msg;
    // 创建响应。
    Response response = createResponse(request);
    response.setId(request.getId());
    ctx.writeAndFlush(response);
}

private Response createResponse(Request request) {
    // 获取被 Client 调用的目标。
    ServerExecutor executor = executors.get(request.getSimpleClassName());
    if (executor == null) {
        return Response.notOk("Executor not found: " + request.getSimpleClassName());
    }
    Class clazz = executor.getClazz();
    Object instance = executor.getInstance();

    Response response;
    try {
        // 获取目标方法。
        Method method = clazz.getDeclaredMethod(request.getMethodName(), request.getParamTypes());
        // 目标方法调用。
        response = (Response) method.invoke(instance, request.getArgs());

        Type genericReturnType = method.getGenericReturnType();
        if (genericReturnType instanceof ParameterizedType) {
            Type[] types = ((ParameterizedType) genericReturnType).getActualTypeArguments();
            response.setTypeParamTypeName(types[0].getTypeName());
        } else {
            String msg = "Generic return type not a parameterized type";
            log.error(msg);
            response = Response.notOk("cause: " + msg);
        }
    } catch (NoSuchMethodException | SecurityException | IllegalAccessException | IllegalArgumentException
            | InvocationTargetException | ClassCastException e) {
        log.error("Failed to invoke: " + request, e);
        response = Response.notOk("cause: " + e);
    }
    return response;
}
```

Client 和 Server 的数据传输协议，这里以 JSON 序列化和反序列化为例。

Client 请求 Server，如下图所示：

![client2server](/img/implementing-rpc/client2server.png)

Server 响应 Client，如下图所示：

![server2client](/img/implementing-rpc/server2client.png)

然后，设计简单的注册中心接口。

```java
public interface ServiceRegistry {

    Service get(String id);

    void register(Service service);

}
```

采用 [Consul](https://www.consul.io/) 作为注册中心，使用它的 Agent API。

了解更多，推荐以下文章：

- [使用Consul做服务发现的若干姿势](http://blog.didispace.com/consul-service-discovery-exp/)

- [springcloud(十三)：注册中心 Consul 使用详解](http://www.ityouknow.com/springcloud/2018/07/20/spring-cloud-consul.html)

## 伪装

将远程调用伪装成本地调用。

### 被调用者

提供接口和模型，隐藏实现。

```java
@RpcCaller(serviceId = "rpc-server")
public interface UserService {

    Response<List<User>> find(String name, int age);

    Response<List<User>> query(String keyword);

    Response<User> get(Long id);

    Response<Long> save(User user);

    Response<List<Long>> save(List<User> users);

}
```

```java
public class User {
    private Long id;

    private String name;

    private int age;

    // Getter, Setter
}
```

启动服务。

```java
public static void main(String[] args) {
    SpringApplication.run(RpcServerApplication.class, args);

    ConsulService service = new ConsulService();
    service.setName("rpc-server").setPort(8080);
    ConsulRegistry registry = new ConsulRegistry("127.0.0.1", 8500);
    String executorsPkg = "io.h2cone.rpcserver.service";

    RpcServer server = new RpcServer(service, registry, executorsPkg);
    server.start();
}
```

### 调用者

配置。

```java
@Configuration
public class ServiceConf {

    @Bean
    @ConditionalOnMissingBean
    public ConsulRegistry consulRegistry() {
        return new ConsulRegistry("127.0.0.1", 8500);
    }

    @Bean
    @ConditionalOnMissingBean
    public UserService userService(@Qualifier("consulRegistry") ServiceRegistry registry) {
        return (UserService) Proxy.newProxyInstance(UserService.class.getClassLoader(),
                new Class[]{UserService.class},
                new RpcHandler(registry, new RpcClient().timeout(10000).timeUnit(TimeUnit.MILLISECONDS)));
    }
}
```

依赖注入。

```java
@Resource
private UserService userService;
```

调用接口。

```java
Response<List<User>> response = userService.find("Dorothy", 14);
```

```java
CompletableFuture<Response<List<User>>> future = CompletableFuture.supplyAsync(() -> userService.find("Dorothy", 14));
future.whenComplete((response, e) -> {
    // ...
});
```

## 缺少

- 编码和解码的类型转换。
- JSON 和 Protobuf。
- 同步调用和异步调用。
- 长连接、短连接、连接检查、连接池。
- 服务查询缓存和缓存更新。
- 注册中心集群、服务多副本、Docker 集群。
- 服务发现和负载均衡。
- 健康检查、心跳、重连、重试、超时。
- 多种注册中心。
- 服务注销。
- 异常处理。
- 日志输出。
- spring-boot-starter。
- 熔断、降级、限流。
- 基准测试和性能优化。
- 链路监控。
- ......

## 起源

完整代码已发布，请参考 [rpc-spring-boot](https://github.com/h2cone/rpc-spring-boot)。

> 本文首发于 https://h2cone.github.io
