---
title: "注解处理器"
date: 2019-11-30T23:43:35+08:00
draft: false
description: ""
tags: [java, annotation]
categories: []
---

Project Lombok 的底子之一。

<!--more-->

## 为什么使用 Getter/Setter

Java 的啰嗦和冗余是闻名于世的，特别在开发基于 Java 的业务系统的时候，继续不断地编写普通的 Java 类（数据类型），不假思索地用 `private` 修饰成员变量，熟练运用编辑器或集成开发环境不停地生成 Getter、Setter、ToString、Constructor 等方法。

```java
public class Member {
    public static final Logger log = LoggerFactory.getLogger(Member.class);

    private Long id;
    private String name;

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    @Override
    public String toString() {
        return new StringJoiner(", ", Member.class.getSimpleName() + "[", "]")
                .add("id=" + id)
                .add("name='" + name + "'")
                .toString();
    }
}
```

如果被问到为什么怎么做，便美名其曰“面向对象编程”（不管重复多少遍，我都想回到过去抗议不翻译成**对象导向编程**的人）；为了诠释什么是 Java 对象，于是把对象三大特征给搬了出来：状态、标识、行为。

特征 | 解释
--- | ---
状态 | 数据类型的值
标识 | 内存地址
行为 | 数据类型的操作

再结合“面向对象编程”的三大特征：继承、多态、封装，特别指出封装（理直气壮，好像**函数式编程**不能封装似的），高谈阔论封装的好处，比如分离数据结构与其操作，提供 API，对使用者隐藏实现细节、隐藏数据的内部表示，非常利于维护、重用、单元测试，还不忘拾人牙慧，复读 David Wheeler 的话：

> All problems in computer science can be solved by another level of indirection.

计算机科学领域的任何问题都可以通过增加一个中间层来解决，Getter 和 Setter 就是封装形成的中间层（私有变量不能直接访问，只能通过中间层访问，不过该中间层往往非常浅薄），最后甩来一个链接：[why-use-getters-and-setters-accessors](https://stackoverflow.com/questions/1568091/why-use-getters-and-setters-accessors)。

## Project Lombok

用 `private` 修饰的字段和其 Getter/Settter 方法，既然已经成为**约定俗成**（若改用 `public` 修饰字段，可能成为”异类“），又或者这是**库或框架的要求**（我们不显式调用的方法，它们却很有可能需要隐式调用才能正常工作），或许还有其它理由，Java 程序员们需要不厌其烦去手动编写或静态生成那些刻板又繁多的代码，还好他们有化繁为简的神器，名为 [Project Lombok](https://projectlombok.org/)：

> Project Lombok is a java library that automatically plugs into your editor and build tools, spicing up your java.
Never write another getter or equals method again, with one annotation your class has a fully featured builder, Automate your logging variables, and much more.

若用 Lombok 简化前面的代码：

```java
@Slf4j
@Getter
@Setter
@Accessors(chain = true)
@ToString
public class Member {
    private Long id;

    private String name;
}
```

特地用 `@Accessors(chain = true)` 进行了增强，允许链式调用 Setter 方法创建对象（因为每次都返回 `this`）：

```java
Member member = new Member()
        .setId(0L)
        .setName("lombok");
```

创建一个复杂对象，主流的做法是使用建造者模式（Builder Pattern），只需要一个 `@Builder` 注解到类上，更多特色的注解在[这里](https://projectlombok.org/features/all)可以找到。

注解 （Annotation）并不神奇，它们只是只读的元数据，程序读取它们，按我们的声明进行处理，我们可以偷看一下 `@Slf4j` 这个注解的类：

```java
@Retention(RetentionPolicy.SOURCE)
@Target(ElementType.TYPE)
public @interface Slf4j {
    String topic() default "";
}
```

`@Retention` 是一个元注解（注解的注解），其唯一属性的类型是 `RetentionPolicy`, 这个枚举只有三个：`SOURCE`、`CLASS`、`RUNTIME`，分别表示注解只保留到源文件，还是只保留到类文件，抑或是保留到运行时。由此可见，Lombok 的特色注解只保留到源文件，那么 Lombok 不是在运行时生成代码，而是在编译时生成代码（进一步证实是反编译有 Lombok 特色注解的源文件编译后的类文件）。

## Annotation Processor

早在 Java 6 时期，开发人员就可以使用 Pluggable Annotation Processing API（JSR 269）定制注解处理器（Annotation Processor），处理源文件中的注解。比如，检查代码并发出自定义的错误或警告，就像 Java 编译器编译 Java 源文件时，它就会检查被 `@Override` 修饰的方法是否与父类或接口的方法签名相同，如果不同，就会报错（编译失败），又或者像 Lombok 那样，根据注解提供的信息在编译时修改代码（修改抽象语法树），而不会有运行时修改代码的开销。

下面展示一个简单的注解处理器：

```java
@SupportedAnnotationTypes({
        "io.h2cone.annotation.processor.Inspect"
})
@SupportedSourceVersion(SourceVersion.RELEASE_8)
public class SimpleAnnotationProcessor extends AbstractProcessor {

    @Override
    public boolean process(Set<? extends TypeElement> annotations, RoundEnvironment roundEnv) {
        for (TypeElement element : annotations) {
            this.processingEnv.getMessager().printMessage(Diagnostic.Kind.NOTE, element.getQualifiedName());
            System.out.println(element.getQualifiedName());
        }
        return false;
    }
}
```

关键在于定制的注解处理器类需要继承 `AbstractProcessor` 类，并重写感兴趣的方法，去处理特定的注解，例如我们指定了一个自定义注解：

```java
@Retention(RetentionPolicy.SOURCE)
@Target({
        ElementType.TYPE,
        ElementType.METHOD
})
public @interface Inspect {

    boolean ignore() default false;

}
```

预期 `process` 方法会在**编译时**被调用，输出或打印传递而来的自定义注解的名称。可是其它项目如何使用定制的注解处理器？如果定制的注解处理器项目为 [annotation-processor](https://github.com/h2cone/java-examples/tree/master/annotation-processor)，那么它还需要一个文件（src/main/resources/META-INF/services/javax.annotation.processing.Processor）用来告诉编译器定制的注解处理器类在哪里：

```
io.h2cone.annotation.processor.SimpleAnnotationProcessor
```

除此之外，构建此项目时应当添加编译参数 `-proc:none`，意味着无需注解处理即可进行编译（以 Maven 为例）：

```xml
<build>
    <plugins>
        <plugin>
            <groupId>org.apache.maven.plugins</groupId>
            <artifactId>maven-compiler-plugin</artifactId>
            <configuration>
                <compilerArgument>-proc:none</compilerArgument>
            </configuration>
        </plugin>
    </plugins>
</build>
```

否者会编译失败，得到一个错误（error: Bad service configuration file）。

假设准备使用定制的注解处理器的项目为 [annotation-processor-demo](https://github.com/h2cone/java-examples/tree/master/annotation-processor-demo)，那么它只需添加依赖：

```xml
<dependency>
    <groupId>io.h2cone</groupId>
    <artifactId>annotation-processor</artifactId>
    <version>${project.version}</version>
</dependency>
```

此依赖还包含了上面说到的自定义注解：

```java
@Inspect(ignore = true)
public class Foobar {
}
```

若使用 IntelliJ IDEA，依次点击 Build > Rebuild Project，成功后可以在底部的 Messages 看到 `process` 方法被调用从而输出了 Inspect 注解的名称：

```
Information:java: io.h2cone.annotation.processor.Inspect
```

> 本文首发于 https://h2cone.github.io

## 参考资料

- [Java开发神器Lombok的使用与原理](http://blog.didispace.com/java-lombok-how-to-use/)

- [Open JDK # Compilation Overview](http://openjdk.java.net/groups/compiler/doc/compilation-overview/index.html)

- [【Lombok原理1】自定义注解处理器](http://patamon.me/icemimosa/Java/[Lombok%E5%8E%9F%E7%90%861]%E8%87%AA%E5%AE%9A%E4%B9%89%E6%B3%A8%E8%A7%A3%E5%A4%84%E7%90%86%E5%99%A8/)

- [Java Pluggable Annotation Processor](https://www.logicbig.com/tutorials/core-java-tutorial/java-se-annotation-processing-api/annotation-processing-concepts.html)
