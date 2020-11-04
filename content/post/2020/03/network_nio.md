---
title: "网络·NIO"
date: 2020-03-08T11:07:41+08:00
draft: false
description: ""
tags: [java, network, i/o, netty, thread, async, event-driven]
categories: []
---

长话短说。

<!--more-->

## I/O

本文以[多线程·并发编程](https://h2cone.github.io/post/2020/02/thread_concurrent/)中的第一张图作为开篇：

![计算机系统的抽象](/img/csapp/计算机系统的抽象.png)

- I/O 设备包括鼠标、键盘、显示器、磁盘、网卡等。

- I/O（输入/输出），**输入是从 I/O 设备复制数据到主存，输出是从主存复制数据到 I/O 设备。**

从一个计算机角度来看，网络（适配器）是它的一个 I/O 设备。当计算机系统从主存复制字节序列到网络适配器时，数据流经过网络到达另一台机器，同理，计算机系统可以从网络适配器复制字节序列到主存。

![计算机系统硬件组成](/img/csapp/计算机系统硬件组成.webp)

## Socket

从人类的角度来看，计算机网络由一台或多台机器组成。网络中，数据从一台机器传输到另一个机器的方式通常是[分组交换](https://en.wikipedia.org/wiki/Packet_switching)，即数据被切分成适合传输的小块数据，小块数据都有各自的编号；它们从一个端点分道扬镳，但殊途同归，到另一个端点时，重新排列组合成完整数据。分组交换的好处之一是充分利用网络带宽，而当 TCP 连接空闲时，通常不占用任何带宽。

分组交换有可能出现数据的丢失、乱序、重复，如何检测、重传、缓存，实现可靠性传输是 [TCP](https://en.wikipedia.org/wiki/Transmission_Control_Protocol) 的目标。别问，问就是[三次握手](https://en.wikipedia.org/wiki/Transmission_Control_Protocol#Connection_establishment)、[四次挥手](https://en.wikipedia.org/wiki/Transmission_Control_Protocol#Connection_termination)、[滑动窗口协议](https://en.wikipedia.org/wiki/Sliding_window_protocol)、[拥塞控制算法](https://en.wikipedia.org/wiki/TCP_congestion_control)......

[TCP/IP 协议族](https://zh.wikipedia.org/wiki/TCP/IP%E5%8D%8F%E8%AE%AE%E6%97%8F)对普通程序员来说足够复杂，但是，[David Wheeler](https://en.wikipedia.org/wiki/David_Wheeler_(computer_scientist)) 曾经说过：

> All problems in computer science can be solved by another level of indirection.

![Socket中间层](/img/network_nio/Socket中间层.png)

- Socket 是进程与传输层的中间层。

- Socket 包含五元组 (**client ip, client port, server ip, server port, protocol**)。

同在传输层的 [UDP](https://en.wikipedia.org/wiki/User_Datagram_Protocol) 不如 TCP 可靠，但是轻量级，因为它没有确认、超时、重传的概念，也没有拥塞控制，而且无连接，从而能广播。

Socket 隐藏了下层具体实现的复杂性，并给上层提供了简单或统一的 API。下图是 TCP Socket 基本流程，使用 [伯克利 Sockets](https://en.wikipedia.org/wiki/Berkeley_sockets) 描述。

![InternetSocketBasicDiagram_zhtw](/img/network_nio/InternetSocketBasicDiagram_zhtw.png)

Unix 的主题是“一切都是文件”。当进程申请访问 Socket 时，内核则提供相应的文件描述符（int 变量），进程发起系统调用并传递相应的文件描述符来读写 Socket。

## Java 网络编程

### BIO

Java 的 BIO 是指 blocking I/O，通常指 [java.io](https://docs.oracle.com/javase/8/docs/api/java/io/package-summary.html) 包组合 [java.net](https://docs.oracle.com/javase/8/docs/api/java/net/package-summary.html) 包。

#### 模型

![javabio](/img/network_nio/javabio.webp)

上图来自[服务化基石之远程通信系列三：I/O模型](https://mp.weixin.qq.com/s/uDgueoMIEjl-HCE_fcSmSw)。基于 Java BIO 的服务器端程序，通常一个客户端（Client）向服务器端（Server）发起的请求由一个线程处理，回想前文的 TCP Socket 基本流程图，那么线程与 Socket 的关系如下：

![one-socket-per-thread](/img/network_nio/one-socket-per-thread.png)

处理请求，通常都可以分解为：

1. 读取请求（receive/read）
2. 解码请求（deocode）
3. 计算/处理（compute/process）
4. 编码响应（encode）
5. 发送响应（send/wirte）

其中 1 和 5 必定是 I/O 操作，回想前文所说的 I/O 操作的本质，即字节序列的来向和去向，来向与去向在 java.io 中的常见类型是 [InputStream](https://docs.oracle.com/javase/8/docs/api/java/io/InputStream.html) 和 [OutputStream](https://docs.oracle.com/javase/8/docs/api/java/io/OutputStream.html)，I/O Stream 表示输入源或输出目的地。

![byte[]-Stream](/img/network_nio/byte[]-Stream.png)

基于 Java BIO 的服务器端程序之所以使用线程池（ThreadPool），理由请参考[多线程·并发编程 # Java 多线程 # 线程池](https://h2cone.github.io/post/2020/02/thread_concurrent/#%E7%BA%BF%E7%A8%8B%E6%B1%A0)。

#### Server

以上内容结合 java.net 的 Socket API，足以编写典型的 Java BIO 服务器端程序：

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

注意 Server 的 run 方法，为什么使用 [ServerSocket](https://docs.oracle.com/javase/8/docs/api/java/net/ServerSocket.html) 循环？首先 accept() 是阻塞方法，表现为一个线程调用该方法时被阻塞在该方法，直到 ServerSocket 准备好接受（accpet）客户端发起的连接（connect）时方法返回，该线程退出该方法，返回值的类型是 [Socket](https://docs.oracle.com/javase/8/docs/api/java/net/Socket.html)，表示客户端的 Socket 副本。然后，该线程命令工作线程处理 Socket，这里用 Handler 的 run 方法作为工作线程的任务，根据 Executor 的一般实现，execute() 非阻塞，立即返回。最后，继续循环。因此，如果没有工作线程且只有一个线程，容易出现该线程正在处理一个 Socket 而无法脱身去处理其它客户端的请求（供不应求）。

建议使用日志框架代替 e.printStackTrace() 和 System.out.print*，还有合理设置线程池的参数，仅仅为了方便展示，采用以下方式启动 Server：

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

处理 Socket 的过程首先是使用 Socket 得到 InputStream 和 OutputStream，然后从中读取字节数组，解码为字符串，打印表示收到了客户端发送的数据，最后以“自我介绍”回复客户端。注意，调用 read 方法将阻塞，直到输入数据可用或检测到 [EOF](https://en.wikipedia.org/wiki/End-of-file) 或引发异常为止。

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

基于 Java NIO 的服务器端程序，虽然使用了线程池，但是处理 Socket 普遍存在阻塞 I/O，工作线程被阻塞或被迫等待较长时间，且一个 Socket 由一个线程处理，即线程工时利用率较低，单个这种服务器端程序应对负载增加（C10K ~ C100K）的能力并不是最优化。

### NIO

Java 的 NIO 是指 non-blocking I/O 或 New I/O，通常指 [java.nio](https://docs.oracle.com/javase/8/docs/api/java/nio/package-summary.html) 包组合 [java.net](https://docs.oracle.com/javase/8/docs/api/java/net/package-summary.html) 包。

#### 模型

![javanio](/img/network_nio/javanio.webp)

上图来自[服务化基石之远程通信系列三：I/O模型](https://mp.weixin.qq.com/s/uDgueoMIEjl-HCE_fcSmSw)。Java NIO 致力于用比 Java BIO 更少的线程处理更多的连接。比如，一个不希望被老板开除的店小二将一位客人的订单交给后厨后，不会只等待后厨做好相应的菜然后上菜，而是立即去接待其它客人入座、点餐、结账等，若店小二观察到后厨做菜完成后则上菜或者后厨做菜完成后通知店小二上菜。

Java NIO 有三大核心组件：

- Channels。支持非阻塞读写 Channel 关联的文件或 Socket。

- Buffers。可以从 Channel 直接读取或直接写入 Channel 的类似数组的对象。

- Selectors。判断一组 Channel 中哪些发生了用户感兴趣的 I/O 事件。

一些不容忽视：

- SelectionKeys。维护 I/O 事件状态和附件。

- [ServerSocketChannel](https://docs.oracle.com/javase/8/docs/api/java/nio/channels/ServerSocketChannel.html)。代替 ServerSocket。

- [SocketChannel](https://docs.oracle.com/javase/8/docs/api/java/nio/channels/SocketChannel.html)。代替 Socket。

#### Channel&Selector

[Selector](https://docs.oracle.com/javase/8/docs/api/java/nio/channels/Selector.html) 是线程和 Channel 的中间层，多个连接可由一个线程处理。

![selector_mid_layer](/img/network_nio/selector_mid_layer.png)

[SelectionKey](https://docs.oracle.com/javase/8/docs/api/java/nio/channels/SelectionKey.html) 定义了四种 I/O 事件： `OP_READ`、`OP_WRITE`、`OP_CONNECT`、`OP_ACCEPT`，均符合伯克利 Sockets 的语义，OP_CONNECT 为客户端专有，OP_ACCEPT 为服务器端专有。

- OP_ACCEPT。ServerSocketChannel **接受就绪**。

- OP_READ。例如，SocketChannel **读就绪**。

- OP_WRITE。例如，SocketChannel **写就绪**。

#### Buffer

Buffer 维护了 position、limit、capacity 变量，具有写模式和读模式。

![Buffer](/img/network_nio/Buffer.webp)

- 写模式。position 为 0，limit 等于 capacity，每插入一个元素，position 增加 1。

- 读模式。由读模式转换为写模式时，limit 设为 position，position 归零。

[ByteBuffer](https://docs.oracle.com/javase/8/docs/api/java/nio/ByteBuffer.html) 的写入和读取通常经历如下步骤：

1. 将字节数组写入 ByteBuffer。

2. 调用 `flip()`，转换为读模式。

3. 从 ByteBuffer 读取字节数组。

4. 调用 clear() 或 compact() 清空 ByteBuffer。

Channel 已提供直接从中读取 ByteBuffer 或直接写入其中的方法。

![ByteBuffer-Channel](/img/network_nio/ByteBuffer-Channel.png)

值得一提的是，ByteBuffer 支持分配直接字节缓冲区，即堆外内存。

```java
public static ByteBuffer allocateDirect(int capacity) {
    return new DirectByteBuffer(capacity);
}
```

```java
public static ByteBuffer allocate(int capacity) {
    if (capacity < 0)
        throw new IllegalArgumentException();
    return new HeapByteBuffer(capacity, capacity);
}
```

DirectByteBuffer 通常比 HeapByteBuffer 内存复制次数更少。以写 Socket 为例，JVM 先从堆中复制数据到进程缓冲区，操作系统内核再从进程缓冲区复制数据到内核缓冲区，然后从内核缓冲区复制数据到 I/O 设备。如果分配直接缓冲区，那么就减去了从堆复制数据到进程缓冲区的操作。`allocateDirect` 方法使用了 `sun.misc.Unsafe#allocateMemory` 方法，这种方法返回的缓冲区通常比非直接缓冲区具有更高的分配和释放成本，因为堆外内存在 GC 范围之外，即使 `java.nio.DirectByteBuffer` 实现了自己的缓冲区对象管理，仍然有堆外内存泄露的风险，通常要考虑以下的 JVM 选项：

```java
-XX:MaxDirectMemorySize=size
```

一个直接字节缓冲区也可以通过将文件区域直接 [mapping](https://docs.oracle.com/javase/8/docs/api/java/nio/channels/FileChannel.html#map-java.nio.channels.FileChannel.MapMode-long-long-) 到内存中来创建，原理是 [mmap](https://en.wikipedia.org/wiki/Mmap)。

#### Reactor

根据上文的知识，足以实现典型的 Java NIO 服务器端程序，但是我把它删掉了；因为它表现得不如上文典型的 Java BIO 的服务器端程序，更因为我读到了 [Doug Lea](https://en.wikipedia.org/wiki/Doug_Lea) 讲的 **Reactor 模式**（链接在文章末尾），常翻 JDK 源码可以发现他是大部分并发数据结构的作者。

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

（1）Reactor 构造器。使用 serverSocketChannel 注册 selector 并添加感兴趣的 I/O 事件（OP_ACCEPT）之后，返回得到一个 selectionKey，selectionKey 可添加一个附件，这个附件是 Acceptor 对象的引用。

（2）分派循环。首先，调用 `selector.select()` 时阻塞，直到选中了一组已准备好进行 I/O 操作的 Channel 所对应的键（SelectionKey），初始只对 OP_ACCEPT 感兴趣。然后，迭代得到相应的键，因为一开始只有一个 Channel，所以当前键集合大小为 1，调用 dispatch 时得到的键的附件即是 Acceptor 对象的引用。

（3）分派方法。由（2）可知，Acceptor 的 `run` 方法被调用，但不直接启动新线程。

（4）Acceptor 运行方法。传递 selector 和 socketChannel 来新建 Handler 对象，不直接调用其 `run` 方法，而是返回到分派循环。

（5）Handler 构造器。用当前的 socketChannel 注册 selector 并添加感兴趣的 I/O 事件（OP_READ）和附件（Handler 对象的引用），但要注意**唤醒** selector，使尚未返回的第一个 select 操作立即返回，理由是有新的 Channel 加入。

（6）Handler 运行方法。在分派循环中，若可读的 socketChannel 对应的键被选中，则该键的附件，即 Handler 对象的 `run` 方法被调用，对 Channel 进行非阻塞读写操作，中间还有 process 方法（业务逻辑），写完之后取消该键关联的 socketChannel 对 selector 的注册。

在 Java NIO 中，对 Channel 的读写是非阻塞方法（直接执行且立即返回，但稍后再执行），通常要判断输入是否完成（inputCompleted），完成后进行业务逻辑处理（process），以及判断输出是否完成（outputCompleted），完成后注销（短连接）。

```java
public interface ChannelHandler {

    void read(SocketChannel socketChannel, ByteBuffer inputBuf) throws IOException;

    boolean inputCompleted(ByteBuffer inputBuf);

    void process(ByteBuffer inputBuf, ByteBuffer outputBuf);

    void write(SocketChannel socketChannel, ByteBuffer outputBuf) throws IOException;

    boolean outputCompleted(ByteBuffer outputBuf);

}
```

```java
public class DefaultChannelHandler implements ChannelHandler {
    public static final String SEND = "i am %s";
    public static final String RECEIVE = "%s receive '%s'";

    @Override
    public void read(SocketChannel socketChannel, ByteBuffer inputBuf) throws IOException {
        socketChannel.read(inputBuf);
    }

    @Override
    public boolean inputCompleted(ByteBuffer inputBuf) {
        return inputBuf.position() > 2;
    }

    @Override
    public void process(ByteBuffer inputBuf, ByteBuffer outputBuf) {
        try {
            inputBuf.flip();
            String msg = Charset.defaultCharset().newDecoder().decode(inputBuf).toString();
            System.out.printf(RECEIVE + "\n", Thread.currentThread().getName(), msg);

            // consuming
            Thread.sleep(BioServer.DELAY_TIME);

            msg = String.format(SEND, Thread.currentThread().getName());
            outputBuf.put(ByteBuffer.wrap(msg.getBytes()));
        } catch (IOException | InterruptedException e) {
            e.printStackTrace();
        }
    }

    @Override
    public void write(SocketChannel socketChannel, ByteBuffer outputBuf) throws IOException {
        outputBuf.flip();
        socketChannel.write(outputBuf);
    }

    @Override
    public boolean outputCompleted(ByteBuffer outputBuf) {
        return !outputBuf.hasRemaining();
    }
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

仔细审视单线程版可以发现，accept、read、process、write 都只由一个线程执行，但是应对高并发时单线程工作能力有限。如果它读完了一个 Channel 后在 process 中执行耗时任务，那么就没有空闲时间进行其它 Channel 的 accept、read、write 操作；因此，使用 Boss 线程执行非阻塞的 accept、read、write 操作，命令工作线程执行耗时的 process 操作，充分消费多处理器来提高程序性能。

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

进一步扩展，甚至可以同时运行两个 Boss 线程，大 Boss 线程负责 accept，分派已接受的 Channel 给小 Boss 线程 read 和 write，命令工作线程 process。

![Using-Multiple-Reactors](/img/network_nio/Using-Multiple-Reactors.png)

一般的开发人员直接使用 Java NIO 编写服务器端或客户端，既要保证可靠，又要保证高性能，实属不易，终于到了主角登场的时候。

### Netty

[Netty](https://netty.io/) 是异步、事件驱动网络应用程序框架，用于快速开发可维护的高性能协议服务器端和客户端。

![netty-components](/img/network_nio/netty-components.png)

如何使用 Netty，参考 [Netty # Wiki](https://github.com/netty/netty/wiki)、[netty/netty/tree/4.1/example](https://github.com/netty/netty/tree/4.1/example)、[normanmaurer/netty-in-action](https://github.com/normanmaurer/netty-in-action) 。下文则更关注如何理解 Netty 4.x 的核心（Core）。

- Bootstrapor or ServerBootstrap
- **EventLoop**
- EventLoopGroup
- **ChannelPipeline**
- Channel
- Future or ChannelFuture
- ChannelInitializer
- ChannelHandler

#### 事件模型

##### EventLoop

![event-loop](/img/vertx/event-loop.png)

[EventLoop](https://netty.io/4.1/api/io/netty/channel/EventLoop.html)，即事件循环，一个 EventLoop 通常将处理多个 [Channel](https://netty.io/4.1/api/io/netty/channel/Channel.html) 的事件，EventLoop 在它生命周期中只绑定单个线程，而 [EventLoopGroup](https://netty.io/4.1/api/io/netty/channel/EventLoopGroup.html) 包含一个或多个 EventLoop。

EventLoop 类的族谱如下所示：

![EventLoop-class-hierarchy](/img/network_nio/EventLoop-class-hierarchy.jpg)

由此可见，EventLoop 的本源是 Executor（请先阅读[多线程·并发编程 # Java 多线程 # 线程池](https://h2cone.github.io/post/2020/02/thread_concurrent/#%E7%BA%BF%E7%A8%8B%E6%B1%A0)），那么 EventLoop 处理 Channel 的事件转换为执行（execute）相应的任务，

![EventLoop-execution-logic](/img/network_nio/EventLoop-execution-logic.jpg)

任务的基本实现是 [Runable](https://docs.oracle.com/javase/8/docs/api/java/lang/Runnable.html)，任务可能立即执行，也可能加入队列，取决于调用 execute 方法的线程是否是 EventLoop 绑定的线程。

如下图所示，一个 [NioEventLoopGroup](https://netty.io/4.1/api/io/netty/channel/nio/NioEventLoopGroup.html) 通常维护多个 [NioEventLoop](https://netty.io/4.1/api/io/netty/channel/nio/NioEventLoop.html) 。

![EventLoop-allocation-for-non-blocking-transports](/img/network_nio/EventLoop-allocation-for-non-blocking-transports.jpg)

当一个 Channel 注册到一个 NioEventLoopGroup，根据上文所说的 Java NIO 知识，该 Channel 注册到一个由某个 NioEventLoop 维护的 Selector，因此，NioEventLoop 通常将处理多个 Channel 的事件。

##### ChannelPipeline

事件分为入站（inbound）事件和出站（outbound）事件。一个事件被 EventLoop 作为任务执行之前，它流经 [ChannelPipeline](https://netty.io/4.1/api/io/netty/channel/ChannelPipeline.html) 中已安装的一个或多个 [ChannelHandler](https://netty.io/4.1/api/io/netty/channel/ChannelHandler.html)。

![ChannelPipeline](/img/network_nio/ChannelPipeline.png)

每个 Channel 都有各自的 ChannelPipeline，新建 Channel 时自动创建，使用 ChannelPipeline 添加或删除 ChannelHandler 是线程安全的。ChannelPipeline 的子接口有 [ChannelInboundHandler](https://netty.io/4.1/api/io/netty/channel/ChannelInboundHandler.html) 和 [ChannelOutboundHandler](https://netty.io/4.1/api/io/netty/channel/ChannelOutboundHandler.html)，分别用于 EventLoop 处理入站事件和出站事件。

![ChannelHandlerAdapter-class-hierarchy](/img/network_nio/ChannelHandlerAdapter-class-hierarchy.jpg)

ChannelPipeline 实现了 [Intercepting Filter](http://www.oracle.com/technetwork/java/interceptingfilter-142169.html) 模式的高级形式，所谓 Filter 模式，常常被认为属于**责任链模式**，比如 [Servlet](https://en.wikipedia.org/wiki/Java_servlet) 的请求过滤器：

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

一个 Filter 可以拦截请求，也可以转发请求给下一个 Filter。为了帮助理解，[HandlerChain](https://github.com/h2cone/java-examples/blob/master/network/src/main/java/io/h2cone/network/staff/HandlerChain.java) 演示了基于链表和多态的责任链模式。

对于 [DefaultChannelPipeline](https://netty.io/4.1/api/io/netty/channel/DefaultChannelPipeline.html) 来说，其链表通常有一个特别的头（HeadContext）和尾（TailContext），实际上结点是包装了 ChannelHandler 的 [ChannelHandlerContext](https://netty.io/4.1/api/io/netty/channel/ChannelHandlerContext.html)。ChannelHandlerContext 定义了事件传播方法（event propagation method），例如 [ChannelHandlerContext.fireChannelRead(Object)](https://netty.io/4.1/api/io/netty/channel/ChannelHandlerContext.html#fireChannelRead-java.lang.Object-) 和 [ChannelOutboundInvoker.write(Object)](https://netty.io/4.1/api/io/netty/channel/ChannelOutboundInvoker.html#write-java.lang.Object-)，事件在 ChannelPipeline 中流动。

以 Channel 读就绪为例，它属于入站事件，输入的数据也在 ChannelPipeline 中流动。

![Event-propagation-via-the-Channel-or-the-ChannelPipeline](/img/network_nio/Event-propagation-via-the-Channel-or-the-ChannelPipeline.jpg)

若以服务器端接受请求和发送响应为例，假设 RequestDecoder 和 BussinessHandler 都继承了 [ChannelInboundHandlerAdapter](https://netty.io/4.1/api/io/netty/channel/ChannelInboundHandlerAdapter.html)，ResponseEncoder 继承了 [ChannelOutboundHandlerAdapter](https://netty.io/4.1/api/io/netty/channel/ChannelOutboundHandlerAdapter.html)。

```java
ChannelPipeline pipeline = channel.pipeline();
pipeline.addLast(new RequestDecoder());
pipeline.addLast(new ResponseEncoder());
pipeline.addLast(new BussinessHandler());
```

（1）接受请求。

```
-> RequestDecoder（解码）-> ResponseEncoder（非触发）-> BussinessHandler（处理）->
```

（2）业务逻辑。

假设处理完成后调用 [ChannelOutboundInvoker.writeAndFlush(Object)](https://netty.io/4.1/api/io/netty/channel/ChannelOutboundInvoker.html#writeAndFlush-java.lang.Object-) 来写回复消息。

（3）发送响应。

```
-> BussinessHandler（写消息）-> ResponseEncoder（编码）-> RequestDecoder（非触发）->
```

#### 最小化内存复制

Netty 使用它自己的 [buffer](https://netty.io/4.1/api/io/netty/buffer/package-summary.html) API 代替 Java NIO 的 ByteBuffer 来表示字节序列。Netty 新的缓冲区类型，名为 [ByteBuf](https://netty.io/4.1/api/io/netty/buffer/ByteBuf.html)，它具有如下特性：

- 您可以根据需要定义缓冲区类型。
- 透明的**零复制**是通过内置的聚合缓冲区类型实现的。
- 开箱即有，动态扩容。
- 不需要调用 flip() 了。
- 它通常比 ByteBuffer 快。

注意，上面的零复制并不是操作系统级零复制，操作系统级零复制是指 CPU 不执行将数据从一个存储区域复制到另一个存储区域的任务，详情见 [zero-copy](https://en.wikipedia.org/wiki/Zero-copy)。如果 I/O 设备支持 [DMA](https://en.wikipedia.org/wiki/Direct_memory_access) 的 [scatter-gather](https://en.wikipedia.org/wiki/Vectored_I/O) 操作，那么 Java NIO 提供操作系统级零复制方法是 [transferTo](https://docs.oracle.com/javase/8/docs/api/java/nio/channels/FileChannel.html#transferTo-long-long-java.nio.channels.WritableByteChannel-)。

聚合缓冲区类型是指 [CompositeByteBuf](https://netty.io/4.1/api/io/netty/buffer/CompositeByteBuf.html)。

![CompositeByteBuf-holding-a-header-and-body](/img/network_nio/CompositeByteBuf-holding-a-header-and-body.jpg)

假设有两个字节数组，header 和 body，在模块化系统中，这两个字节数组可以由不同的模块生产，然后在消息发送后聚合。如果用 Java NIO 的 ByteBuffer 来聚合两个字节数组，一般人可能考虑新建一个缓冲区数组并持有两个字节数组，或者新建一个缓冲区并插入两个字节数组。

```java
// Use an array to composite them
ByteBuffer[] message = new ByteBuffer[] { header, body };
```

```java
// Use copy to merge both
ByteBuffer message2 = ByteBuffer.allocate(header.remaining() + body.remaining());
message.put(header);
message.put(body);
message.flip();
```

以上两种方式不仅有内存复制的成本，而且第一种方式还引入了不兼容或复杂的缓冲区数组类型。

```java
// The composite type is incompatible with the component type.
ByteBuf message = Unpooled.wrappedBuffer(header, body);

// Therefore, you can even create a composite by mixing a composite and an
// ordinary buffer.
ByteBuf messageWithFooter = Unpooled.wrappedBuffer(message, footer);
```

如果使用 Netty 的 ByteBuf 实现，则内存复制次数几乎为零，因为缓冲区引用了两个或多个数组（指针）。

```java
CompositeByteBuf compBuf = Unpooled.compositeBuffer();
ByteBuf headerBuf = ...;    // can be backing or direct
ByteBuf bodyBuf = ...;      // can be backing or direct
compBuf.addComponent(headerBuf, bodyBuf);
```

同理，聚合两个缓冲区，使用指针而不是从原缓冲区复制。

```java
ByteBuf buf = Unpooled.copiedBuffer("Hello, World!", StandardCharsets.UTF_8);
ByteBuf sliced = buf.slice(0, 14);
```

同理，缓冲区的切片，返回的切片引用了原缓冲区的子数组。

#### 为什么高性能

为什么 Netty 吞吐量更高、延迟更低、资源消耗更少？比如 [RxNetty vs Tomcat](https://github.com/Netflix-Skunkworks/WSPerfLab/blob/master/test-results/RxNetty_vs_Tomcat_April2015.pdf) 和 [七种 WebSocket 框架的性能比较](https://colobu.com/2015/07/14/performance-comparison-of-7-websocket-frameworks/)。

- 使用 Java NIO 和 Reactor 模式。为什么 Java NIO 高效，上文的解释是“以阻塞时间换工作时间”，下文将补充操作系统层解释；为什么说 Netty 使用了 Reactor 模式，这里提供一个线索，Netty 中的 ServerBootstrap 的 group 方法有两个类型均为 EventLoopGroup 的参数，回想一下上文“Reactor 多线程版” 最后一张图。

- GC 优化。例如，使用缓冲区对象池，复用缓冲区对象减少了频繁新建对象和收集垃圾引起的延迟，且使用直接缓冲区，详情见 [Netty 4 at Twitter: Reduced GC Overhead](https://blog.twitter.com/engineering/en_us/a/2013/netty-4-at-twitter-reduced-gc-overhead.html) 和 [PooledByteBufAllocator.java](https://github.com/netty/netty/blob/4.1/buffer/src/main/java/io/netty/buffer/PooledByteBufAllocator.java)。

- 减少不必要的内存复制。如上文所说。

- ......

#### 应用程序优化

**S0** 优化业务逻辑。

**S1** 避免阻塞 bossEventLoopGroup/parentGroup 和 workerEventLoopGroup/childGroup 中的线程。执行耗时任务（如访问数据库），考虑新建给定线程数的 EventLoopGroup 对象，添加它和业务逻辑的 ChannelHandler 到 ChannelPipeline。

**S2** 复用 ByteBuf 对象，减少 GC 引起的延迟。

> ByteBuf is a reference-counted object which has to be released explicitly via the release() method. Please keep in mind that it is the handler's responsibility to release any reference-counted object passed to the handler

**S2.1** 使用 [release()](https://netty.io/4.1/api/io/netty/util/ReferenceCounted.html#release--)，回收对象后将隐式复用对象。

```java
@Override
public void channelRead(ChannelHandlerContext ctx, Object msg) {
    // Do something with msg
    ((ByteBuf) msg).release();
}
```

```java
@Override
public void channelRead(ChannelHandlerContext ctx, Object msg) {
    try {
        // Do something with msg
    } finally {
        ReferenceCountUtil.release(msg);
    }
}
```

```java
@Override
public void channelRead(ChannelHandlerContext ctx, Object msg) {
    // Do something with msg
    ctx.write(msg);
    ctx.flush();
}
```

> It is because Netty releases it for you when it is written out to the wire.

**S2.2** 继承 [SimpleChannelInboundHandler](https://netty.io/4.1/api/io/netty/channel/SimpleChannelInboundHandler.html)。

> Be aware that depending of the constructor parameters it will release all handled messages by passing them to ReferenceCountUtil.release(Object). In this case you may need to use ReferenceCountUtil.retain(Object) if you pass the object to the next handler in the ChannelPipeline.

**S2.3** 使用事件传播方法，转发给其它结点释放。

**A1** [ChannelOption](https://netty.io/4.1/api/io/netty/channel/ChannelOption.html) 配置或参数调优，例如调整 TCP 发送/接收缓冲区（TCP Send/Receive Buffers）的大小：

```java
ServerBootstrap bootstrap = new ServerBootstrap()
        .channel(EpollServerSocketChannel.class)
        .group(bossEventLoopGroup, workerEventLoopGroup)
        .handler(new LoggingHandler(LogLevel.INFO))
        .childHandler(new CustomChannelInitializer())
        .childOption(ChannelOption.SO_SNDBUF, 1024 * 1024)
        .childOption(ChannelOption.SO_RCVBUF, 32 * 1024);
```

**A2** 复用自定义的 ChannelHandler 对象。使用 [@ChannelHandler.Sharable](https://netty.io/4.1/api/io/netty/channel/ChannelHandler.Sharable.html)，但要注意是否存在多线程访问共享变量的安全问题。

## I/O 模型

经典的 《UNIX Network Programming》已经完美诠释了五种 I/O 模型。

![unix-io-model](/img/unp/unix-io-models.png)

- blocking I/O
- nonblocking I/O
- I/O multiplexing (`select` and `poll` and `epoll`)
- signal driven I/O (`SIGIO`)
- asynchronous I/O (the POSIX `aio_` functions)

目前来说，signal driven I/O 和 asynchronous I/O 在 Linux 的应用较为罕见，因此本文只关注前三种。

回想开头所说的 I/O 的本质，但别忘了操作系统是应用程序和硬件的中间层。

- 输入是从 I/O 设备复制字节序列到内核缓冲区，然后从内核缓冲区复制字节序列到进程缓冲区。

- 输出是从进程缓冲区复制字节序列到内核缓冲区，然后从内核缓冲区复制字节序列到 I/O 设备。

### blocking I/O & nonblocking I/O

![Blocking-IO-Model](/img/unp/Blocking-IO-Model.png)

以读 Socket 为例，线程调用 `recvfrom` 函数并传递目标 Socket 文件描述符，该线程被阻塞在该函数，当目标 Socket 读就绪，内核复制数据报，复制完成后该函数返回 OK，该线程退出该函数并执行后续语句。

![Nonblocking-IO-Model](/img/unp/Nonblocking-IO-Model.png)

仍以读 Socket 为例，线程调用 `recvfrom` 函数并传递目标 Socket 文件描述符，该线程没被阻塞在该函数，该函数返回错误码，表示目标 Socket 非读就绪，线程重复调用该函数（轮询），当目标 Socket 读就绪，该线程被阻塞在该函数，内核复制数据报，复制完成后该函数返回 OK，该线程退出该函数并执行后续语句。

注意，blocking I/O 模型和 nonblocking I/O 模型都出现了线程被阻塞在函数的现象。

最后以先读 Socket 后写 Socket 为例，下面这张来自 [Shawn Xu](https://medium.com/@xunnan.xu) 的文章（文末有链接）的图详细描述了 Java BIO 的底层行为。

![java-bio-under-the-hood](/img/network_nio/java-bio-under-the-hood.png)

注意，JVM 发起 2 次系统调用，内核执行 2 次数据复制。

### I/O multiplexing

![IO-Multiplexing-Model](/img/unp/IO-Multiplexing-Model.png)

继续以读 Socket 为例，线程在调用 `recvfrom` 函数前，先调用 `select` 函数并传递目标 Socket 文件描述符列表，该线程被阻塞在 `select` 函数，直到一个或多个目标 Socket 读就绪，内核对列表中可读的 Socket 文件描述符做了标记，然后 `select` 函数返回，线程执行循环语句遍历这个列表，查找已标记的 Socket 文件描述符，每命中一个 Socket 文件描述符就调用 `recvfrom` 函数并传递 Socket 文件描述符，该线程被阻塞在 `recvfrom` 函数，当目标 Socket 读就绪，内核复制数据报，复制完成后该函数返回 OK，该线程退出该函数并继续执行循环语句。`select` 函数的实现细节有明显可优化的地方，比如，内核只需回复一个只存储就绪的 Socket 文件描述符列表，可节省顺序查找的开销。

虽然以上三种 I/O 模型均出现了线程被阻塞在函数的现象，但是 I/O multiplexing 模型的优势在于单一线程在相同时间内能够处理更多的连接或请求，同时组合多线程模型，例如 Reactor 模式，所以才说，一个基于 I/O multiplexing 的 Java NIO 服务器端应对负载增加的能力通常高于一个 Java BIO 服务器端。

## 原生传输

早在 JDK 6 就已经包括了基于 Linux [epoll](https://en.wikipedia.org/wiki/Epoll) 全新的 [SelectorProvider](https://docs.oracle.com/javase/8/docs/api/java/nio/channels/spi/SelectorProvider.html)，当检测到内核 2.6 以及更高版本时，默认使用基于 epoll 的实现，当检测到 2.6 之前的内核版本时，将使用基于 [poll](https://en.wikipedia.org/wiki/Poll_(Unix)) 的实现。

Netty 则提供了特别的 JNI 传输，与基于 NIO 的传输相比，产生更少的垃圾，通常可以提高性能。

- NioEventLoopGroup → EpollEventLoopGroup
- NioEventLoop → EpollEventLoop
- NioServerSocketChannel → EpollServerSocketChannel
- NioSocketChannel → EpollSocketChannel

详情请见 [Netty # Native transports](https://netty.io/wiki/native-transports.html)。

## 文中代码

已发布，请移步 [network](https://github.com/h2cone/java-examples/tree/master/network)。

> 本文首发于 https://h2cone.github.io

## 更多经验

- [Scalable IO in Java - Doug Lea](http://gee.cs.oswego.edu/dl/cpjslides/nio.pdf)

- [Java NIO trick and trap](http://www.blogjava.net/killme2008/archive/2010/11/22/338420.html)

- [It’s all about buffers: zero-copy, mmap and Java NIO](https://medium.com/@xunnan.xu/its-all-about-buffers-zero-copy-mmap-and-java-nio-50f2a1bfc05c)

- [Build Your Own Netty — Reactor Pattern](https://medium.com/@kezhenxu94/in-the-previous-post-we-already-have-an-echoserver-that-is-implemented-with-java-nio-lets-check-ccf5b5b32da9)

- [Reactor pattern - Wikipedia](https://en.wikipedia.org/wiki/Reactor_pattern)

- [Event (computing) - Wikipedia](https://en.wikipedia.org/wiki/Event_(computing))

- [Netty in Action # Chapter 7. EventLoop and threading model](https://livebook.manning.com/book/netty-in-action/chapter-7/)

- [Netty in Action # Chapter 6. ChannelHandler and ChannelPipeline](https://livebook.manning.com/book/netty-in-action/chapter-6/)

- [Netty in Action # Chapter 5. ByteBuf](https://livebook.manning.com/book/netty-in-action/chapter-5/)

- [Chain-of-responsibility pattern - Wikipedia](https://en.wikipedia.org/wiki/Chain-of-responsibility_pattern)

- [Chain of Responsibility Design Pattern in Java](https://www.baeldung.com/chain-of-responsibility-pattern)

- [High Performance JVM Networking with Netty - Speaker Deck](https://speakerdeck.com/daschl/high-performance-jvm-networking-with-netty)

- [Netty # Wiki # Reference counted objects](https://github.com/netty/netty/wiki/Reference-counted-objects)

- [Oracle # Enhancements in Java I/O](https://docs.oracle.com/javase/8/docs/technotes/guides/io/enhancements.html)

- [UNP # Chapter 6. I/O Multiplexing: The select and poll Functions](https://notes.shichao.io/unp/ch6/#io-models)

- [6.2 I/O Models - MASTERRAGHU](http://www.masterraghu.com/subjects/np/introduction/unix_network_programming_v1.3/ch06lev1sec2.html)

- [一文读懂高性能网络编程中的I/O模型](https://mp.weixin.qq.com/s/saZl6PsVoYKF9QwGBGFJwg)

- [select、poll、epoll之间的区别总结[整理]](https://www.cnblogs.com/anker/p/3265058.html)

- [Java Tutorials # Basic I/O](https://docs.oracle.com/javase/tutorial/essential/io/index.html)

- [Java Tutorials # Custom Networking](https://docs.oracle.com/javase/tutorial/networking/)

- [Vert.x # Guide](https://vertx.io/docs/guide-for-java-devs/)
