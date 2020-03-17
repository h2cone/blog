---
title: "网络·NIO"
date: 2020-03-08T11:07:41+08:00
draft: false
description: ""
tags: [java, network, i/o, netty, thread, async, event-driven]
categories: []
---

Java 基本功（二）。

<!--more-->

## I/O

本文以[多线程·并发编程](https://h2cone.github.io/post/2020/02/thread_concurrent/)中的第一张图作为开篇：

![计算机系统的抽象](/img/csapp/计算机系统的抽象.png)

- I/O 设备包括鼠标、键盘、显示器、磁盘、网卡等。

- I/O（输入/输出），**输入是从 I/O 设备复制数据到主存，输出是从主存复制数据到 I/O 设备。**

从一个计算机角度来看，网络（适配器）是它的一个 I/O 设备。当计算机系统从主存复制字节序列到网络适配器时，数据流经过网络到达另一台机器，同理，计算机系统可以从网络适配器复制字节序列到主存。

## Socket

从人类的角度来看，计算机网络由一台或多台机器组成，网络中，数据从一台机器传输到另一个机器的方式通常是[分组交换](https://en.wikipedia.org/wiki/Packet_switching)，即数据被切分成适合传输的小块数据，小块数据都有各自的编号，它们从一个端点分道扬镳，但殊途同归，到另一个端点时，重新排列组合成完整数据。分组交换的好处之一是充分利用网络带宽。

分组交换有可能出现数据的丢失、乱序、重复，如何检测、重传、缓存，实现可靠性传输是 [TCP](https://en.wikipedia.org/wiki/Transmission_Control_Protocol) 的目标。别问，问就是[三次握手](https://en.wikipedia.org/wiki/Transmission_Control_Protocol#Connection_establishment)、[四次挥手](https://en.wikipedia.org/wiki/Transmission_Control_Protocol#Connection_termination)、[滑动窗口协议](https://en.wikipedia.org/wiki/Sliding_window_protocol)、[拥塞控制算法](https://en.wikipedia.org/wiki/TCP_congestion_control)......

[TCP/IP 协议族](https://zh.wikipedia.org/wiki/TCP/IP%E5%8D%8F%E8%AE%AE%E6%97%8F)对普通程序员来说足够复杂，但是，[David Wheeler](https://en.wikipedia.org/wiki/David_Wheeler_(computer_scientist)) 曾经说过：

> All problems in computer science can be solved by another level of indirection.

![Socket中间层](/img/network_nio/Socket中间层.png)

- Socket 是进程与传输层的中间层。

- Socket 包含五元组**（client ip, client port, server ip, server port, protocol）**。

同在传输层的 [UDP](https://en.wikipedia.org/wiki/User_Datagram_Protocol) 不如 TCP 可靠，但是轻量级，因为它没有确认、重传、超时的概念，也没有拥塞控制，而且无连接，从而能广播。你看，人类是可以接受网络视频或网络游戏偶尔卡顿的。

Socket 隐藏了下层具体实现的复杂性，并给上层提供了简单或统一的 API。下图是 TCP Socket 基本流程，使用 [伯克利 Sockets](https://en.wikipedia.org/wiki/Berkeley_sockets) 描述。

![InternetSocketBasicDiagram_zhtw](/img/network_nio/InternetSocketBasicDiagram_zhtw.png)

Unix 的主题是“一切都是文件”。当进程申请访问 Socket 时，内核则提供相应的文件描述符（int 变量），进程发起系统调用并传递相应的文件描述符来读写 Socket。

## Java 网络编程

### BIO

#### 准备

Java 的 BIO 是指 blocking I/O，通常指 [java.io](https://docs.oracle.com/javase/8/docs/api/java/io/package-summary.html) 包组合 [java.net](https://docs.oracle.com/javase/8/docs/api/java/net/package-summary.html) 包。

![javabio](/img/network_nio/javabio.webp)

这是“点亮架构”公众号的[服务化基石之远程通信系列三：I/O模型](https://mp.weixin.qq.com/s/uDgueoMIEjl-HCE_fcSmSw)中的插图。基于 Java BIO 的服务器端程序，通常一个客户端（Client）向服务器端（Server）发起的请求由一个线程处理，回想前文的 TCP Socket 基本流程图，那么线程与 Socket 的关系如下：

![one-socket-per-thread](/img/network_nio/one-socket-per-thread.png)

处理请求，通常都可以分解为：

1. 读取请求（read）
2. 解码请求（deocode）
3. 计算/处理（compute/process）
4. 编码响应（encode）
5. 发送响应（send/wirte）

其中 1 和 5 必定是 I/O 操作，回想前文所说的 I/O 操作的本质，即字节序列的来向和去向，来向与去向在 `java.io` 中的常见类型是 [InputStream](https://docs.oracle.com/javase/8/docs/api/java/io/InputStream.html) 和 [OutputStream](https://docs.oracle.com/javase/8/docs/api/java/io/OutputStream.html).

![byte[]-Stream](/img/network_nio/byte[]-Stream.png)

基于 Java BIO 的服务器端程序之所以使用线程池（ThreadPool），理由请参考[多线程·并发编程 # Java 多线程 # 线程池](https://h2cone.github.io/post/2020/02/thread_concurrent/#%E7%BA%BF%E7%A8%8B%E6%B1%A0)。

#### Server

以上内容结合 `java.net` 的 Socket API，足以编写典型的 Java BIO 服务器端程序：

```java
class Server implements Runnable {
    final int port;
    final Executor executor;
    final Processable processable;

    public Server(int port, Executor executor, Processable processable) {
        this.port = port;
        this.executor = executor;
        this.processable = processable;
    }

    @Override
    public void run() {
        try {
            ServerSocket serverSocket = new ServerSocket(port);
            while (!Thread.interrupted()) {
                Socket socket = serverSocket.accept();
                executor.execute(new Handler(socket, processable));
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    static class Handler implements Runnable {
        final Socket socket;
        final Processable processable;

        public Handler(Socket socket, Processable processable) {
            this.socket = socket;
            this.processable = processable;
        }

        @Override
        public void run() {
            processable.process(socket);
        }
    }

    @Deprecated
    interface Processable {
        void process(Socket socket);
    }
}
```

注意 Server 的 run 方法，为什么使用 [ServerSocket](https://docs.oracle.com/javase/8/docs/api/java/net/ServerSocket.html) 循环？	首先 `accept()` 是阻塞方法，表现为一个线程（Acceptor）调用该方法时“暂停执行”，直到 `ServerSocket` 准备好接受（accpet）客户端发起的连接（connect）时方法返回，该线程“恢复执行”，返回值的类型是 [Socket](https://docs.oracle.com/javase/8/docs/api/java/net/Socket.html)，表示客户端的 Socket 副本。然后，该线程命令工作线程处理 Socket，这里用 `Handler` 的 `run` 方法作为工作线程的任务，根据 `Executor` 的一般实现，`execute()` 非阻塞，立即返回。最后，继续循环。因此，如果没有工作线程且只有一个线程，容易出现该线程正在处理一个 Socket 而无法脱身去处理其它客户端的请求（供不应求）。

建议使用日志框架代替 `e.printStackTrace()` 和 `System.out.print*`，还有合理设置线程池的参数。仅仅为了方便展示，采用以下方式启动 Server：

```java
public static void main(String[] args) {
    int port = args.length == 0 ? 8080 : Integer.parseInt(args[0]);

    Server server = new Server(port, Executors.newCachedThreadPool(), (socket) -> {
        try (InputStream input = socket.getInputStream(); OutputStream output = socket.getOutputStream()) {
            // read
            int len;
            byte[] buf = new byte[1024];
            if ((len = input.read(buf)) != -1) {
                String msg = new String(buf, 0, len);
                System.out.printf("%s receive '%s' from %s\n", Thread.currentThread().getName(), msg, socket.toString());
                // consuming
                Thread.sleep(DELAY_TIME);
                // write
                msg = String.format("i am %s", Thread.currentThread().getName());
                output.write(msg.getBytes());
                output.flush();
            }
        } catch (IOException | InterruptedException e) {
            e.printStackTrace();
        }
    });
    new Thread(server).start();

    System.out.printf("server running on %s\n", port);
}
```

处理 Socket 的过程首先是使用 `Socket` 得到 `InputStream` 和 `OutputStream`，然后从中读取字节数组，解码为字符串，打印表示收到了客户端发送的数据，最后以“自我介绍”回复客户端。注意，调用 `read` 方法将阻塞，直到输入数据可用或检测到 [EOF](https://en.wikipedia.org/wiki/End-of-file) 或引发异常为止。

多客户端可以用多线程模拟。客户端先向服务器端发送“自我介绍”，然后尝试读取来自服务器端的消息：

```java
public class BioClient {
    public static int NUMBER_OF_CLIENTS = 8;

    public static void main(String[] args) {
        String host = args.length == 0 ? "127.0.0.1" : args[0];
        int port = args.length == 0 ? 8080 : Integer.parseInt(args[1]);

        Runnable runnable = () -> {
            try {
                Socket socket = new Socket(host, port);
                try (OutputStream output = socket.getOutputStream(); InputStream input = socket.getInputStream()) {
                    // write
                    String msg = String.format("i am %s", Thread.currentThread().getName());
                    output.write(msg.getBytes());
                    output.flush();
                    // read
                    int len;
                    byte[] buf = new byte[1024];
                    if ((len = input.read(buf)) != -1) {
                        msg = new String(buf, 0, len);
                        System.out.printf("%s receive '%s' from %s\n", Thread.currentThread().getName(), msg, socket.toString());
                    }
                }
            } catch (IOException e) {
                e.printStackTrace();
            }
        };
        for (int i = 0; i < NUMBER_OF_CLIENTS; i++) {
            new Thread(runnable).start();
        }
    }
}
```

基于 Java NIO 的服务器端程序，虽然使用了线程池，但是处理 Socket 普遍存在阻塞 I/O，工作线程被阻塞或被迫等待较长时间，且一个 Socket 由一个线程处理，即工作线程工时利用率较低，单个这种服务器端程序应对负载增加的能力并不是最优化。

### NIO

Java 的 NIO 是指 non-blocking I/O 或 New I/O，通常指 [java.nio](https://docs.oracle.com/javase/8/docs/api/java/nio/package-summary.html) 包组合 [java.net](https://docs.oracle.com/javase/8/docs/api/java/net/package-summary.html) 包。

![javanio](/img/network_nio/javanio.webp)

上图来自“点亮架构”公众号的文章插图。我在[旧文](https://h2cone.github.io/post/2019/12/implementing-rpc/)里说过，Java NIO 致力于用比 Java BIO 更少的线程处理更多的连接。非常符合人类的直觉，比如，一个不希望被老板开除的店小二将一个客人的订单交给后厨后，不会等待后厨做好后上菜，而是立即去接待其它客人入座、点餐、结账等，后厨做菜完成后自然会通知店小二上菜。

#### 组件

Java NIO 有三大核心组件：

- Channels。支持非阻塞读写 Channel 关联的文件或 Socket。

- Buffers。可以从 Channel 直接读取或直接写入 Channel 的类似数组的对象。

- Selectors。判断一组 Channel 中哪些发生了用户感兴趣的 I/O 事件。

还有一些不容忽视：

- SelectionKeys。维护 I/O 事件状态和附件。

- [ServerSocketChannel](https://docs.oracle.com/javase/8/docs/api/java/nio/channels/ServerSocketChannel.html)。代替 ServerSocket。

- [SocketChannel](https://docs.oracle.com/javase/8/docs/api/java/nio/channels/SocketChannel.html)。代替 Socket。

[Selector](https://docs.oracle.com/javase/8/docs/api/java/nio/channels/Selector.html) 是线程和 Channel 的中间层，多个连接由一个线程处理。

![selector_mid_layer](/img/network_nio/selector_mid_layer.png)

[SelectionKey](https://docs.oracle.com/javase/8/docs/api/java/nio/channels/SelectionKey.html) 定义了四个常量来表示 I/O 事件： `OP_READ`、`OP_WRITE`、`OP_CONNECT`、`OP_ACCEPT`，均符合伯克利 Sockets 的语义，`OP_CONNECT` 为客户端专有，`OP_ACCEPT` 为服务器端专有。

Buffer 维护了 position、limit、capacity 变量，具有写模式和读模式。

![Buffer](/img/network_nio/Buffer.webp)

- 写模式。position 为 0，limit 等于 capacity，每插入一个元素，position 增加 1。

- 读模式。由读模式转换为写模式时，limit 设为 position，position 归零。

[ByteBuffer](https://docs.oracle.com/javase/8/docs/api/java/nio/ByteBuffer.html) 的写入和读取通常经历如下步骤：

1. 将字节数组写入 ByteBuffer。

2. 调用 `flip()`，转换为读模式。

3. 从 ByteBuffer 读取字节数组。

4. 调用 `clear()` 或 `compact()` 清空 ByteBuffer。

Channel 已提供直接从中读取 ByteBuffer 或直接写入其中的方法。

![ByteBuffer-Channel](/img/network_nio/ByteBuffer-Channel.png)

值得一提的是，ByteBuffer 支持分配直接的字节缓存区，即堆外内存。

#### Reactor

根据上文的知识，足以实现典型的 Java NIO 服务器端程序，但是我把它删掉了，因为它表现得不如上文典型的 Java BIO 的服务器端程序，更因为我读到了 [Doug Lea](https://en.wikipedia.org/wiki/Doug_Lea) 讲的 **Reactor 模式**（链接在文章末尾），常翻 JDK 源码可以发现他是大部分并发数据结构的作者。

##### 单线程版

![Basic-Reactor-Design](/img/network_nio/Basic-Reactor-Design.png)

若用 Java 语言来描述上图，基本的 Reactor 模式如下：

```java
class Reactor implements Runnable {
    final Selector selector;
    final ServerSocketChannel serverSocketChannel;
    final ChannelHandler channelHandler;

    public Reactor(int port, ChannelHandler channelHandler) throws IOException {
        selector = Selector.open();
        serverSocketChannel = ServerSocketChannel.open();

        serverSocketChannel.socket().bind(new InetSocketAddress(port));
        serverSocketChannel.configureBlocking(false);
        SelectionKey selectionKey = serverSocketChannel.register(selector, SelectionKey.OP_ACCEPT);
        selectionKey.attach(new Acceptor());        // (1)

        this.channelHandler = channelHandler;
    }

    @Override
    public void run() {
        try {
            while (!Thread.interrupted()) {
                selector.select();
                Set<SelectionKey> selectionKeys = selector.selectedKeys();
                Iterator<SelectionKey> iterator = selectionKeys.iterator();
                while (iterator.hasNext()) {
                    SelectionKey selectionKey = iterator.next();
                    dispatch(selectionKey);     // (2)
                    iterator.remove();
                }
                selectionKeys.clear();
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    private void dispatch(SelectionKey selectionKey) {
        Runnable runnable = (Runnable) selectionKey.attachment();
        if (runnable != null) {
            runnable.run();     // (3)
        }
    }

    class Acceptor implements Runnable {

        @Override
        public void run() {
            try {
                SocketChannel socketChannel = serverSocketChannel.accept();
                if (socketChannel != null) {
                    new Handler(selector, socketChannel, channelHandler);      // (4)
                }
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
    }

    static class Handler implements Runnable {
        final SelectionKey selectionKey;
        final SocketChannel socketChannel;
        final ChannelHandler channelHandler;

        ByteBuffer inputBuf = ByteBuffer.allocate(1024);
        ByteBuffer outputBuf = ByteBuffer.allocate(1024);
        static int READING = 0, WRITING = 1;
        int state = READING;

        public Handler(Selector selector, SocketChannel socketChannel, ChannelHandler channelHandler) throws IOException {
            this.socketChannel = socketChannel;
            this.socketChannel.configureBlocking(false);
            // (5)
            selectionKey = this.socketChannel.register(selector, 0);
            selectionKey.attach(this);
            selectionKey.interestOps(SelectionKey.OP_READ);
            selector.wakeup();

            this.channelHandler = channelHandler;
        }

        @Override
        public void run() {
            try {
                if (state == READING) {
                    read();
                } else if (state == WRITING) {
                    write();
                }
            } catch (Exception e) {
                e.printStackTrace();
            }
        }

        private void read() throws IOException {
            channelHandler.read(socketChannel, inputBuf);
            if (channelHandler.inputCompleted(inputBuf)) {
                channelHandler.process(inputBuf, outputBuf);
                state = WRITING;
                selectionKey.interestOps(SelectionKey.OP_WRITE);
            }
        }

        private void write() throws IOException {
            channelHandler.write(socketChannel, outputBuf);
            if (channelHandler.outputCompleted(outputBuf)) {
                selectionKey.cancel();      // (6)
            }
        }
    }
}
```

（1）Reactor 构造器。使用 serverSocketChannel 注册 selector 并添加感兴趣的 I/O 事件（`OP_ACCEPT`）之后，返回得到一个 selectionKey，selectionKey 可添加一个附件，这个附件是 Acceptor 对象的引用。

（2）分派循环。首先，调用 `selector.select()` 时阻塞，直到选中了一组已准备好进行 I/O 操作的 Channel 所对应的键（SelectionKey），初始只对 `OP_ACCEPT` 感兴趣。然后，迭代得到相应的键，因为一开始只有一个 Channel，所以当前键集合大小为 1，调用 dispatch 时得到的键的附件即是 Acceptor 对象的引用。

（3）分派方法。由（2）可知，Acceptor 的 `run` 方法被调用，但不直接启动新线程。

（4）Acceptor 运行方法。传递 selector 和 socketChannel 来新建 Handler 对象，不直接调用其 `run` 方法，而是返回到分派循环。

（5）Handler 构造器。用当前的 socketChannel 注册 selector 并添加感兴趣的 I/O 事件（`OP_READ`）和附件（Handler 对象的引用），但要注意唤醒 selector，使尚未返回的第一个 select 操作立即返回，理由是有新的 Channel 加入。

（6）Handler 运行方法。在分派循环中，若可读的 socketChannel 对应的键被选中，则该键的附件，即 Handler 对象的 `run` 方法被调用，对 Channel 进行非阻塞读写操作，中间还有 process 方法，写完之后取消该键关联的 socketChannel 对 selector 的注册。

在 Java NIO 中，对 Channel 的读写是非阻塞方法，通常要判断输入是否完成（inputCompleted），完成后进行业务逻辑处理（process），以及判断输出是否完成（outputCompleted），完成后注销（短连接）。

```java
public interface ChannelHandler {

    void read(SocketChannel socketChannel, ByteBuffer inputBuf) throws IOException;

    boolean inputCompleted(ByteBuffer inputBuf);

    void process(ByteBuffer inputBuf, ByteBuffer outputBuf);

    void write(SocketChannel socketChannel, ByteBuffer outputBuf) throws IOException;

    boolean outputCompleted(ByteBuffer outputBuf);

}
```

仅仅为了方便展示，采用以下方式启动 Reactor：

```java
public static void main(String[] args) throws IOException {
    int port = args.length == 0 ? 8080 : Integer.parseInt(args[0]);

    ExecutorService executorService = Executors.newSingleThreadExecutor();
    executorService.execute(new Reactor(port, Executors.newCachedThreadPool(), new DefaultChannelHandler()));

    System.out.printf("server running on %s\n", port);
}
```

一图胜千言。

![BasicReactor](/img/network_nio/BasicReactor.png)

与上文 BIO 客户端程序类似，也模拟多客户端。客户端先向服务器端发送“自我介绍”，然后尝试读取来自服务器端的消息：

```java
public class Client {

    public static void main(String[] args) {
        String host = args.length == 0 ? "127.0.0.1" : args[0];
        int port = args.length == 0 ? 8080 : Integer.parseInt(args[1]);
        SocketAddress socketAddress = new InetSocketAddress(host, port);

        Runnable runnable = () -> {
            try {
                SocketChannel socketChannel = SocketChannel.open(socketAddress);
                socketChannel.configureBlocking(true);
                // write
                String msg = String.format(DefaultChannelHandler.SEND, Thread.currentThread().getName());
                ByteBuffer buffer = ByteBuffer.wrap(msg.getBytes());
                socketChannel.write(buffer);
                // read
                buffer = ByteBuffer.allocate(1024);
                socketChannel.read(buffer);
                if (buffer.position() > 0) {
                    buffer.flip();
                    msg = Charset.defaultCharset().newDecoder().decode(buffer).toString();
                    System.out.printf(DefaultChannelHandler.RECEIVE + "\n", Thread.currentThread().getName(), msg);
                }
            } catch (IOException e) {
                e.printStackTrace();
            }
        };
        for (int i = 0; i < BioClient.NUMBER_OF_CLIENTS; i++) {
            new Thread(runnable).start();
        }
    }
}
```

##### 多线程版

![Using-Worker-Thread-Pools](/img/network_nio/Using-Worker-Thread-Pools.png)

仔细审视单线程版可以发现，accept、read、process、write 都只由一个线程执行，但是应对高并发时单线程工作能力有限。如果它读完了一个 Channel 后在 process 方法中执行耗时任务，那么就没有空闲时间进行其它 Channel 的 accept、read、write 操作。因此，使用 Boss 线程执行非阻塞的 accept、read、write 操作，命令工作线程执行耗时的 process 操作，充分消费多处理器来提高程序性能。

```java
static class Handler implements Runnable {
    final Selector selector;
    final SelectionKey selectionKey;
    final SocketChannel socketChannel;
    final ChannelHandler channelHandler;

    ByteBuffer inputBuf = ByteBuffer.allocate(1024);
    ByteBuffer outputBuf = ByteBuffer.allocate(1024);
    static int READING = 0, PROCESSING = 1, WRITING = 2;
    int state = READING;

    final Executor executor;

    public Handler(Selector selector, SocketChannel socketChannel, Executor executor, ChannelHandler channelHandler) throws IOException {
        this.selector = selector;
        this.socketChannel = socketChannel;
        this.socketChannel.configureBlocking(false);

        selectionKey = this.socketChannel.register(selector, 0);
        selectionKey.attach(this);
        selectionKey.interestOps(SelectionKey.OP_READ);
        selector.wakeup();

        this.executor = executor;
        this.channelHandler = channelHandler;
    }

    @Override
    public void run() {
        try {
            if (state == READING) {
                read();
            } else if (state == PROCESSING) {
                processAndHandOff();
            } else if (state == WRITING) {
                write();
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    private synchronized void read() throws IOException {
        channelHandler.read(socketChannel, inputBuf);
        if (channelHandler.inputCompleted(inputBuf)) {
            state = PROCESSING;
            executor.execute(this::processAndHandOff);
        }
    }

    private synchronized void processAndHandOff() {
        channelHandler.process(inputBuf, outputBuf);
        state = WRITING;
        selectionKey.interestOps(SelectionKey.OP_WRITE);
        selector.wakeup();
    }

    private void write() throws IOException {
        channelHandler.write(socketChannel, outputBuf);
        if (channelHandler.outputCompleted(outputBuf)) {
            selectionKey.cancel();
        }
    }
}
```

在单线程版的基础上修改 Handler，然后用以下方式启动 Reactor（建议合理设置线程池的参数）：

```java
ExecutorService executorService = Executors.newSingleThreadExecutor();
executorService.execute(new Reactor(port, Executors.newCachedThreadPool(), new DefaultChannelHandler()));
```

进一步扩展，甚至可以同时运行两个 Boss 线程，大 Boss 线程负责 accept，小 Boss 线程负责 read 和 write，工作线程则负责 process。

![Using-Multiple-Reactors](/img/network_nio/Using-Multiple-Reactors.png)

一般的开发人员直接使用 Java NIO 编写服务器端或客户端，既要保证可靠，又要保证高性能，实属不易，终于到了主角登场的时候。

### Netty

[Netty](https://netty.io/) 是异步事件驱动网络应用程序框架，用于快速开发可维护的高性能协议服务器端和客户端。

![netty-components](/img/network_nio/netty-components.png)

如何使用 Netty，参考 [Netty # User guide for 4.x](https://netty.io/wiki/user-guide-for-4.x.html) 和 [netty/netty/tree/4.1/example](https://github.com/netty/netty/tree/4.1/example) 以及 [normanmaurer/netty-in-action](https://github.com/normanmaurer/netty-in-action) 足矣。下文则更关注如何理解 Netty 的核心（Core）。

#### 事件模型

![event-loop](/img/network_nio/event-loop.png)

[EventLoop](https://netty.io/4.1/api/io/netty/channel/EventLoop.html)，敬请期待。

![ChannelPipeline](/img/network_nio/ChannelPipeline.png)

[ChannelPipeline](https://netty.io/4.1/api/io/netty/channel/ChannelPipeline.html)。敬请期待。

```java
public class CustomFilter implements Filter {
 
    public void doFilter(
      ServletRequest request,
      ServletResponse response,
      FilterChain chain)
      throws IOException, ServletException {
 
        // process the request
 
        // pass the request (i.e. the command) along the filter chain
        chain.doFilter(request, response);
    }
}
```

#### 最少化内存复制

[io.netty.buffer](https://netty.io/4.1/api/io/netty/buffer/package-summary.html)。Netty 高性能的原因之一是使用 Java NIO 和 Reactor 模式，更重要的原因是减少不必要的内存复制。敬请期待。

### I/O 模型

敬请期待。

## 文中代码

已发布，请移步 [network](https://github.com/h2cone/java-examples/tree/master/network)。

> 本文首发于 https://h2cone.github.io

## 认知更多

- [Non-blocking I/O (Java) - Wikipedia](https://en.wikipedia.org/wiki/Non-blocking_I/O_(Java)#Channels)

- [Scalable IO in Java - Doug Lea](http://gee.cs.oswego.edu/dl/cpjslides/nio.pdf)

- [Java NIO trick and trap](http://www.blogjava.net/killme2008/archive/2010/11/22/338420.html)

- [UNP # Chapter 6. I/O Multiplexing: The select and poll Functions](https://notes.shichao.io/unp/ch6/#io-models)

- [6.2 I/O Models - MASTERRAGHU](http://www.masterraghu.com/subjects/np/introduction/unix_network_programming_v1.3/ch06lev1sec2.html)

- [It’s all about buffers: zero-copy, mmap and Java NIO](https://medium.com/@xunnan.xu/its-all-about-buffers-zero-copy-mmap-and-java-nio-50f2a1bfc05c)

- [Zero-copy - Wikipedia](https://en.wikipedia.org/wiki/Zero-copy)

- [Build Your Own Netty — Reactor Pattern](https://medium.com/@kezhenxu94/in-the-previous-post-we-already-have-an-echoserver-that-is-implemented-with-java-nio-lets-check-ccf5b5b32da9)

- [Reactor pattern - Wikipedia](https://en.wikipedia.org/wiki/Reactor_pattern)

- [Event (computing) - Wikipedia](https://en.wikipedia.org/wiki/Event_(computing))

- [Netty in Action # Chapter 7. EventLoop and threading model](https://livebook.manning.com/book/netty-in-action/chapter-7/)

- [Netty in Action # Chapter 6. ChannelHandler and ChannelPipeline](https://livebook.manning.com/book/netty-in-action/chapter-6/)

- [Chain-of-responsibility pattern - Wikipedia](https://en.wikipedia.org/wiki/Chain-of-responsibility_pattern)

- [Chain of Responsibility Design Pattern in Java](https://www.baeldung.com/chain-of-responsibility-pattern)

- [Core J2EE Patterns - Intercepting Filter](https://www.oracle.com/technetwork/java/interceptingfilter-142169.html)

- [Java Tutorials # Basic I/O](https://docs.oracle.com/javase/tutorial/essential/io/index.html)

- [Java Tutorials # Custom Networking](https://docs.oracle.com/javase/tutorial/networking/)

- [Vert.x # Guide](https://vertx.io/docs/guide-for-java-devs/)

- [一文读懂高性能网络编程中的I/O模型](https://mp.weixin.qq.com/s/saZl6PsVoYKF9QwGBGFJwg)

