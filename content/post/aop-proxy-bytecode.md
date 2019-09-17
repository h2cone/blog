---
title: "切面和动态代理以及字节码"
date: 2019-09-17T11:29:21+08:00
draft: false
description: ""
tags: []
categories: []
---

纵向的代码在横向被魔术师悄无声息地注入了新的代码.

<!--more-->

## 楔子

想象一下, 我们编写的代码块重复了两次或两次以上, 理智的程序员可能会考虑重构, 提取公共的部分抽象成函数或方法, 通过重用函数或方法以此减少冗余, 简化代码, 甚至预防了 "牵一发而动全身" 的噩梦. 这已经算得上是对 DRY 和 SoC 原则的践行, DRY (Don't repeat yourself) 教导我们尽量减少重复代码, 而 SoC (Separation of Concerns) 指的是关注点分离, 因为关注点混杂会极大地增强复杂性, 好比把什么都混为一谈, 堆积而成的祖传代码, 这又是程序员们的另一个噩梦, 所以才把复杂的问题分解成若干独立的小问题, 模块化, 极力追求 "高内聚, 低耦合".

AOP (Aspect-oriented programming) 是对横向的重用, 非常符合 DRY 和 SoC 的原则. 直观上, 代码总是从上往下执行, 不妨称之为纵向, OOP (Object-oriented Programming) 的继承也可看作是纵向, 相对则是横向, 从横跨多个类的角度来看, 横向有着许许多多的统一逻辑可以切入, 比如**安全检查, 异常处理, 日志输出, 事务管理, 跟踪, 监控**等等, 这些统一逻辑能够被抽象成模块, 重用它们甚至不需要显式调用或只需要编写简单的元数据进行声明, 一次编写, 到处执行, Java 程序员们已经体验过不少 Spring AOP 的魔术.

AOP 能够使前文所述的统一逻辑模块化, 这些统一逻辑可称之为横切关注点 (crosscutting concerns), 切面 (Aspect) 则作为模块, 因此译为切面导向编程. 切面的作用效果彷佛是往程序的执行点注入了新的代码, 这些执行点被称之为接入点 (Join Point), 比如方法调用的前后. 接入点的集合称之为切入点 (Pointcut), 比如满足条件的一组方法. 注入的代码称之为建议 (Advice), 比如在方法调用前后输出日志. 其中代码注入的术语是编织 (Weaving), 既然把编织工作交给库或框架, 那么可能是在**编译时编织**或**运行时编织**, 还可能在**编译后编织 (Post-compile weaving)** 或**加载时编织 (Load-time weaving)**.

虽说如此, 那属于 Spring 核心的 Spring AOP 的魔术是怎么做到的呢?

喧闹中, 听见了一句悄悄话

> Spring AOP is implemented by using runtime proxies.

另一句悄悄话

> In the Spring Framework, an AOP proxy is a JDK dynamic proxy or a CGLIB proxy.

原来 Spring AOP 是使用运行时代理实现的, 代理则是由 JDK 动态代理或 CGLIB 生成. 据传闻所说, 利用 JDK 动态代理能够在运行时生成代理, 一番打听之后也了解到 CGLIB 是一个字节码生成和转换库, 也可用于动态生成代理.

> Byte Code Generation Library is high level API to generate and transform JAVA byte code. It is used by AOP, testing, data access frameworks to generate dynamic proxy objects and intercept field access.

门打开了, 面前是通向秘密地下室的分岔, 一条是名为 JDK 动态代理的路, 另一条是名为 CGLIB 的路.

## 探秘

Python, JavaScript, PHP, Ruby 等动态语言们, 竟然能在运行时对类/属性/方法/函数进行操作, 作为静态语言的 Java 在不重启 JVM 的前提下, 是否也可以在运行时操作类?

当我们写完一个 Java 程序, 通过 Java 编译器编译后输出包含 Java 字节码的 Class 文件, 随后启动 Java 虚拟机 (JVM, 本文以 HotSpot 为例), Java 运行时环境 (JRE) 通过类加载器 (Class Loader) 加载类到 JVM 运行时的方法区, 方法区储存着类的数据, 比如运行时的常量池 (Run-Time Constant Pool) 和方法代码等, 应用程序也能利用类加载器动态加载类. 因此, 如果在运行时修改类又或者在运行时生成类并动态加载到方法区, Java 运行时操作类显然是可能的.

一番搜索后, 果然其中一些想法早已实现在 JDK 里. JDK 动态代理不仅能够在运行时生成类, 还能拦截方法调用, 接下来用简单的代码详细说明.

我们有一个简单的接口和接口实现类

```java
public interface PersonService {

    String sayHello(String name);

}
```

```java
public class SimplePersonService implements PersonService {

    @Override
    public String sayHello(String name) {
        return "Hello, " + name;
    }
}
```

感谢多态, 我们可以使用接口 say hello

```java
    @Test
    public void helloWorld() {
        PersonService service = new SimplePersonService();
        String result = service.sayHello("World");
        Assert.assertEquals("Hello, World", result);
    }
```

可是, 如果我们需要在 `sayHello("World")` 调用前后添加一些逻辑, 比如

```java
System.out.println("之前做点什么");
String result = service.sayHello("World");
System.out.println("之后做点什么");
```

插入一两处也许还能接受, 如果 `sayHello(...)` 遍布各处或不便改动其上下文代码, 为了减少代码冗余和分离关注点, 试试 JDK 动态代理吧.

```java
    @Test
    public void sayHello() {
        // 创建目标实例 (被代理实例, 可选)
        SimplePersonService target = new SimplePersonService();

        // 生成代理类, 创建代理实例
        PersonService proxy = (PersonService) Proxy.newProxyInstance(target.getClass().getClassLoader(),
                target.getClass().getInterfaces(),
                new PersonServiceHandler(target));

        String result = proxy.sayHello("World");
        Assert.assertEquals("Hello, World", result);
    }

    /**
     *  拦截 PersonService 方法调用的处理器
     */
    static class PersonServiceHandler implements InvocationHandler {
        /**
         * 目标实例 (被代理实例)
         */
        Object target;

        PersonServiceHandler() {
        }

        PersonServiceHandler(Object target) {
            this.target = target;
        }

        @Override
        public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
            System.out.printf("proxy class: %s\n", proxy.getClass());
            System.out.printf("method: %s\n", method);
            System.out.printf("args: %s\n", Arrays.toString(args));

            if (target != null) {
                System.out.println("Before invoke"); // 调用前, 添加逻辑

                Object result = method.invoke(target, args);
                System.out.println(result);

                System.out.println("After invoke"); // 调用后, 添加逻辑
                return result;
            }
            return null;
        }
    }
```

上面这段代码通过了测试并输出了以下内容

```console
proxy class: class com.sun.proxy.$Proxy4
method: public abstract java.lang.String io.h2cone.proxy.jdk.PersonService.sayHello(java.lang.String)
args: [World]
Before invoke
Hello, World
After invoke
```

生成的代理类名叫 `com.sun.proxy.$Proxy4`, 官方文档对代理类的定义是

> A dynamic proxy class is a class that implements a list of interfaces specified at runtime such that a method invocation through one of the interfaces on an instance of the class will be encoded and dispatched to another object through a uniform interface

同时注意到了 `java.lang.reflect.Proxy#newProxyInstance` 方法参数

```javadoc
loader – the class loader to define the proxy class
interfaces – the list of interfaces for the proxy class to implement
h – the invocation handler to dispatch method invocations to
```

第二个参数是代理类实现的接口列表, 原来代理类是接口实现类, 回顾一下上文的代码, `com.sun.proxy.$Proxy4` 实现了接口 `PersonService`, 而 `SimplePersonService` 也实现了接口 `PersonService`, 也就说代理类和被代理类是兄弟姐妹. 所谓代理, 在这里就是通过重写 `InvocationHandler` 的 `invoke` 方法拦截 `PersonService` 方法调用并能在调用前后添加逻辑.

当用 Java 工作的时候, 程序员们也许经常编写许多接口, 但每个接口却只有一个实现类, 不免有一种 “过度工程” 的嫌疑, 往往很多接口成为了不必要的抽象, 还因此多了一些运行时开销, 接口虽好却不必过早设计. 回到动态代理的话题, 是否有可能不需要接口就能动态生成代理类呢?

到了 CGLIB 的用武之地. CGLIB 其实是 (Code Generation Library) 的简称, 译作代码生成库, 但这会让人困惑, 难道是生成 Java 源代码? 并不是, 它的真名是 Java 字节码生成库. Java 字节码 (Java bytecode) 看起来是怎么样子的?

对于上文的代码, 当我们用 `javac` 编译源代码成功会输出 `PersonService.class` 和 `SimplePersonService.class` 等文件. 我们用编辑器看看其中一个文件的内容

```class
cafe babe 0000 0034 0009 0700 0707 0008
0100 0873 6179 4865 6c6c 6f01 0026 284c
6a61 7661 2f6c 616e 672f 5374 7269 6e67
3b29 4c6a 6176 612f 6c61 6e67 2f53 7472
696e 673b 0100 0a53 6f75 7263 6546 696c
6501 0012 5065 7273 6f6e 5365 7276 6963
652e 6a61 7661 0100 2169 6f2f 6832 636f
6e65 2f70 726f 7879 2f6a 646b 2f50 6572
736f 6e53 6572 7669 6365 0100 106a 6176
612f 6c61 6e67 2f4f 626a 6563 7406 0100
0100 0200 0000 0000 0104 0100 0300 0400
0000 0100 0500 0000 0200 06
```

这就是 Java 字节码看起来的样子, 这里表现为十六进制数据. Java 编译的过程是从源代码到字节码再到机器码 (Machine code), 机器只理解机器码, 而 JVM 只理解 Java 字节码, 可以说 **Java 字节码是 JVM 的指令集**. 既然 Class 文件包含了 Java 字节码, 则修改类或生成类是由操作 Java 字节码开始, 可是我们大部分都只擅长 Java 代码, 操作 Java 字节码要怎么开始呢?

不妨先试试从 Class 文件逆向到 Java 文件, 利用反汇编命令行工具, 例如敲下 `javap -v SimplePersonService.class`, 你将得到 Class 文件格式 (The class File Format) 的直观认识, 但是, 操作 Java 字节码需要透彻理解 Java 虚拟机规范, 比如 JVM 的指令集和 JVM 内幕, ASM 的出现使之成为可能, ASM 是一个 Java 字节码操作和分析框架, 可用于修改已存在类或者动态生成类, 程序员们不满足于此, 利用 ASM 封装了更高层的 Java API, 最终出现了 CGLIB.

我们来看看 CGLIB 仓库的维基的一段描述

> cglib is a powerful, high performance and quality Code Generation Library, It is used to extend JAVA classes and implements interfaces at runtime

无需接口动态生成代理类不是不可能的, 因为代理类可以继承被代理类. 接下来体验一下 CGLIB, 我们使用抽象类代替接口

```java
public abstract class PersonService {

    public String sayHello(String name) {
        return "Hello, " + name;
    }
}
```

然后, 用 CGLIB 的方式 say hello

```java
    @Test
    public void sayHello() {
        Enhancer enhancer = new Enhancer();
        enhancer.setSuperclass(PersonService.class);    // 设置基类
        enhancer.setCallback(new PersonServiceInterceptor());   // 设置方法调用拦截器
        PersonService service = (PersonService) enhancer.create();  // 生成代理类, 创建代理实例

        String result = service.sayHello("World");
        Assert.assertEquals("Hello, World", result);
    }

    /**
     *  PersonService 方法调用拦截器
     */
    static class PersonServiceInterceptor implements MethodInterceptor {

        @Override
        public Object intercept(Object obj, Method method, Object[] args, MethodProxy proxy) throws Throwable {
            System.out.printf("obj class: %s\n", obj.getClass());
            System.out.printf("method: %s\n", method);
            System.out.printf("args: %s\n", Arrays.toString(args));
            System.out.printf("method proxy: %s\n", proxy);

            System.out.println("Before invoke"); // 调用前, 添加逻辑

            Object result = proxy.invokeSuper(obj, args);
            System.out.println(result);

            System.out.println("After invoke"); // 调用后, 添加逻辑
            return result;
        }
    }
```

输出结果如下

```shell
obj class: class io.h2cone.proxy.cglib.PersonService$$EnhancerByCGLIB$$64e53be2
method: public java.lang.String io.h2cone.proxy.cglib.PersonService.sayHello(java.lang.String)
args: [World]
method proxy: net.sf.cglib.proxy.MethodProxy@629f0666
Before invoke
Hello, World
After invoke
```

这种方式的代理类名称是 `obj calss` 对应的值, 顾名思义, 它是 `PersonService` 的增强类. 在生成代理类之前, `enhancer` 设置了基类 `PersonService`, 由此生成的代理类自然就继承了被代理类 `PersonService`, 它们是孩子与父母的关系. CGLIB 与 JDK 动态代理一样都能拦截方法调用, 替被拦截方法做一些它做不到的事情.

综上所述, **JDK 动态代理只能通过接口生成代理类, 代理类与被代理类是兄弟姐妹, 而 CGLIB 还能通过基类生成代理类, 代理类是被代理类的子类.** 除了能力上的区别, 在性能上, 似乎普遍认为 CGLIB 要快于 JDK 动态代理. 前文提到了 Spring AOP 使用 JDK 动态代理或 CGLIB 在运行时生成代理类, 那么 Spring AOP 在什么情况下采用 JDK 动态代理? 又是在什么情况下次采用 CGLIB? 如结论所说, 如果被代理类或目标类实现了一个或多个接口, 那么 Spring AOP 将采用 JDK 动态代理生成一个实现每个接口的代理类. 如果被代理类或目标类没有实现接口, 那么 Spring AOP 将采用 CGLIB 动态生成代理类, 它是被代理类或目标类的子类. 当然, Spring AOP 很大可能也提供了强制采用其中某种方式的方法.

虽然动态生成了代理类, 但是如果不能把代理类加载到 JVM 方法区, 它就不能像其它正常类一样产生 `java.lang.Class` 的实例, 也就不会有后续的动态性. 回头看一下 JDK 动态代理的 `newProxyInstance` 方法的首要参数

```javadoc
loader – the class loader to define the proxy class
```

它是一个用于定义代理类的类加载器, 我们传递了被代理类的类加载器, 因而被代理类和代理类的类加载器是相同的.

```console
target class loader: sun.misc.Launcher$AppClassLoader@18b4aac2
proxy class loader: sun.misc.Launcher$AppClassLoader@18b4aac2
```

`AppClassLoader` 是应用程序类加载器, 又名为系统类加载器 (System Class Loader), 它所在的家族大概长这样子

```text
System Class Loader -> Extension Class Loader -> Bootstrap Class Loader
```

其中没有双亲的 Bootstrap Class Loader 从 `JRE/lib/rt.jar` 加载类, 它的孩子 Extension Class Loader 从 `JRE/lib/ext` 或 `java.ext.dirs` 加载类, 它的子孙 `System Class Loader` 从 `CLASSPATH`, `-classpath`, `-cp`, `Mainfest` 加载类, 不仅如此, 类加载机制使用双亲委派模型处理类加载请求, 先将请求委派给父母, 若父母不能完成加载, 则退回由孩子加载, 这么做的好处之一是防止同一类被加载多次. 当然, 如果有需要自定义类加载器, 则需要编写类继承 `java.lang.ClassLoader` 并重写相应的方法.

## 后记

在 Spring AOP 的使用过程中, 还发现一个叫做 AspectJ 的家伙. 在编译时和运行时之间, 有编译后和加载时, 它就在加载时动手脚...

## 参考

[冒号课堂§3.3：切面范式](https://blog.zhenghui.org/2009/09/10/colon-class-3_3/)

[Aspect Oriented Programming with Spring](https://docs.spring.io/spring/docs/5.1.9.RELEASE/spring-framework-reference/core.html#aop)

[JDK- and CGLIB-based proxies](https://docs.spring.io/spring/docs/5.1.9.RELEASE/spring-framework-reference/core.html#aop-pfb-proxy-types)

[Spring本质系列(2)-AOP](https://mp.weixin.qq.com/s?__biz=MzAxOTc0NzExNg==&mid=2665513187&idx=1&sn=f603eee3e798e79ce010c9d58cd2ecf3&scene=21#wechat_redirect)

[Dynamic Proxy Classes](https://docs.oracle.com/javase/8/docs/technotes/guides/reflection/proxy.html)

[Java帝国之动态代理](https://mp.weixin.qq.com/s?__biz=MzAxOTc0NzExNg==&mid=2665513926&idx=1&sn=1c43c5557ba18fed34f3d68bfed6b8bd&chksm=80d67b85b7a1f2930ede2803d6b08925474090f4127eefbb267e647dff11793d380e09f222a8&scene=21#wechat_redirect)

[从兄弟到父子：动态代理在民间是怎么玩的？](https://mp.weixin.qq.com/s?__biz=MzAxOTc0NzExNg==&mid=2665513980&idx=1&sn=a7d6145b13270d1768dc416dbc3b3cbd&chksm=80d67bbfb7a1f2a9c01e7fe1eb2b3319ecc0d210a88a1decd1c4d4e1d32e50327c60fa5b45c8&scene=21#wechat_redirect)

[CGLIB 仓库](https://github.com/cglib/cglib)

[ASM： 一个低调成功者的自述](https://mp.weixin.qq.com/s?__biz=MzAxOTc0NzExNg==&mid=2665513528&idx=1&sn=da8b99016aeb4ede2e3c078682be0b46&chksm=80d67a7bb7a1f36dbbc3fc9b3a08ca4b9fae63dbcbd298562b9372da739d5fa4b049dec7ed33&scene=21#wechat_redirect)

[ASM 官网](https://asm.ow2.io/)

[classloader-in-java](https://www.geeksforgeeks.org/classloader-in-java/)

[Class ClassLoader](https://docs.oracle.com/javase/8/docs/api/java/lang/ClassLoader.html)

[Java运行时动态生成class的方法](https://www.liaoxuefeng.com/article/1080190250181920)

[Load-time Weaving with AspectJ in the Spring Framework](https://docs.spring.io/spring/docs/current/spring-framework-reference/core.html#aop-aj-ltw)
