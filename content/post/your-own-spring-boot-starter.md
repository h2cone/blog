---
title: "造你自己的 Spring Boot Starter 组件"
date: 2020-01-23T20:16:58+08:00
draft: false
description: ""
tags: []
categories: []
---

基于 Spring Boot 共享库。

<!--more-->

## 自动配置

遥想以前，Spring 集成其它模块往往需要大量的 XML 配置和 Java 配置，经历过 SSM（Spring、Spring MVC、MyBatis）或者 SSH（Struts、Spring、Hibernate）框架搭建和填空的人们应该深有体会，特别费时费力，直到 Spring Boot 的流行才有所改善。

Spring Boot 简化配置，开箱即用，得益于自动配置（auto-configuration），开启了自动配置的 Spring Boot 程序会尝试猜测和配置我们可能需要的 Bean。如果我们给一般的 Spring Boot Web 程序（添加了 `spring-boot-starter-web` 依赖的 Spring Boot 程序）关联的 `application.yml` 文件增加一行：

```yml
debug: true
```

程序启动成功后，可以在控制台观察到一段叫做 `CONDITIONS EVALUATION REPORT` 的冗长日志，下面截取若干部分：

```shell
============================
CONDITIONS EVALUATION REPORT
============================


Positive matches:
-----------------

...

   EmbeddedWebServerFactoryCustomizerAutoConfiguration.TomcatWebServerFactoryCustomizerConfiguration matched:
      - @ConditionalOnClass found required classes 'org.apache.catalina.startup.Tomcat', 'org.apache.coyote.UpgradeProtocol' (OnClassCondition)

...


Negative matches:
-----------------

...

   EmbeddedWebServerFactoryCustomizerAutoConfiguration.JettyWebServerFactoryCustomizerConfiguration:
      Did not match:
         - @ConditionalOnClass did not find required classes 'org.eclipse.jetty.server.Server', 'org.eclipse.jetty.util.Loader', 'org.eclipse.jetty.webapp.WebAppContext' (OnClassCondition)

   EmbeddedWebServerFactoryCustomizerAutoConfiguration.NettyWebServerFactoryCustomizerConfiguration:
      Did not match:
         - @ConditionalOnClass did not find required class 'reactor.netty.http.server.HttpServer' (OnClassCondition)

   EmbeddedWebServerFactoryCustomizerAutoConfiguration.UndertowWebServerFactoryCustomizerConfiguration:
      Did not match:
         - @ConditionalOnClass did not find required classes 'io.undertow.Undertow', 'org.xnio.SslClientAuthMode' (OnClassCondition)

...


Exclusions:
-----------

    None


Unconditional classes:
----------------------

    org.springframework.boot.autoconfigure.context.ConfigurationPropertiesAutoConfiguration

    org.springframework.boot.actuate.autoconfigure.info.InfoContributorAutoConfiguration

...
```

这份报告分为四个部分：`Positive matches`、`Negative matches`、`Exclusions`、`Unconditional classes`，顾名思义，对于这个程序内嵌的应用服务器，只有 Tomcat 的配置类是匹配的，而 Jetty、Undertow、Netty 的配置类均不匹配，它们共同的外部类则是一个自动配置类：[EmbeddedWebServerFactoryCustomizerAutoConfiguration](https://github.com/spring-projects/spring-boot/blob/v2.2.4.RELEASE/spring-boot-project/spring-boot-autoconfigure/src/main/java/org/springframework/boot/autoconfigure/web/embedded/EmbeddedWebServerFactoryCustomizerAutoConfiguration.java)，这就是 Spring Boot 提供的内嵌应用服务器的自动配置。

自动配置类满足一些条件时，即匹配，框架就自动进行了配置，例如，如果你在 classpath 上有 `tomcat-embedded.jar`，你可能想要一个 `TomcatServletWebServerFactory` bean，除非你定义了自己的 `ServletWebServerFactory` bean。

不出意外，Spring Web 模块需要配置的 Dispatcher Servlet、数据库操作需要配置的数据源等等，Spring Boot 都提供了基础的配置（参见 Spring Boot 源码的 [spring.factories](https://github.com/spring-projects/spring-boot/blob/v2.2.4.RELEASE/spring-boot-project/spring-boot-autoconfigure/src/main/resources/META-INF/spring.factories) 文件），通常，用户只需要添加对应的依赖，简单声明一下，开箱即用，即使默认配置不满足后期需求，也支持覆盖或重写。

## 自定义吧

自动配置是通过使用 `@Configuration` 注解的类来实现，其它诸如 `@Conditional` 的注解用于约束何时应用自动配置（是否匹配）。比如下面这个自定义的自动配置类：

```java
@ConditionalOnProperty(prefix = "springfox-swagger2", name = "enabled")
@Configuration
@EnableSwagger2
@EnableConfigurationProperties(SpringFoxSwagger2Prop.class)
public class SpringFoxSwagger2AutoConfig {
    @Resource
    private SpringFoxSwagger2Prop springFoxSwagger2Prop;

    @Bean
    @ConditionalOnMissingBean
    public Docket docket() {
        ApiSelectorBuilder builder = new Docket(DocumentationType.SWAGGER_2)
                .apiInfo(apiInfo())
                .select();
        List<String> excludedPaths = springFoxSwagger2Prop.getExcludedPaths();
        if (excludedPaths == null || excludedPaths.isEmpty()) {
            builder.paths(Predicates.not(PathSelectors.regex("/error")))
                    .paths(Predicates.not(PathSelectors.regex("/actuator.*")));
        } else {
            for (String path : excludedPaths) {
                builder.paths(Predicates.not(PathSelectors.regex(path)));
            }
        }
        return builder.build();
    }

    private ApiInfo apiInfo() {
        SpringFoxSwagger2Prop.ApiInfo apiInfo = springFoxSwagger2Prop.getApiInfo();
        if (apiInfo == null) {
            return ApiInfo.DEFAULT;
        }
        SpringFoxSwagger2Prop.Contact contact = apiInfo.getContact();
        return new ApiInfo(
                apiInfo.getTitle(),
                apiInfo.getDescription(),
                apiInfo.getVersion(),
                apiInfo.getTermsOfServiceUrl(),
                new Contact(contact.getName(), contact.getUrl(), contact.getEmail()),
                apiInfo.getLicense(),
                apiInfo.getLicenseUrl(),
                Collections.emptyList()
        );
    }
}
```

`SpringFoxSwagger2AutoConfig` 的目的是创建 `springfox.documentation.spring.web.plugins.Docket` 实例并交由 Spring IoC 容器管理，为了能够让 Spring Boot 采用这个自动配置类，应当在 `springfox-swagger2-spring-boot-autoconfigure/src/main/resources/META-INF/spring.factories` 文件里声明：

```text
org.springframework.boot.autoconfigure.EnableAutoConfiguration=\
io.h2cone.springfox.swagger2.spring.boot.autoconfigure.SpringFoxSwagger2AutoConfig
```

若有多个，则用逗号隔开，若需换行，则用反斜杠。以上代码来源于 [springfox-swagger2-spring-boot](https://github.com/h2cone/springfox-swagger2-spring-boot)，其中有如下三个模块:

- springfox-swagger2-spring-boot-autoconfigure
- springfox-swagger2-spring-boot-starter
- springfox-swagger2-spring-boot-sample

职责分别是自动配置、包装、示例，依赖关系就像 [x-spring-boot](https://github.com/h2cone/x-spring-boot) 一样单纯。利用 Spring Boot 的自动配置特性，我们还可以提前创建好一些复杂单例，注册为 Spring Bean，通过依赖注入来使用......

## 走马观花

以上经验告诉我们，Spring Boot 启动时会读取 `META-INF/spring.factories` 的元数据，加载类，进行自动配置。那我们就能通过 IntelliJ IDEA CE 强大的搜索功能发现加载此文件的类：

![search_spring_factories](/img/search_spring_factories.png)

进去阅读一下 `org.springframework.core.io.support.SpringFactoriesLoader` 的源码和 Javadoc，再利用 IntelliJ IDEA CE 代码分析能力得知 `loadFactories` 和 `loadFactoryNames` 这两个公共方法被 `org.springframework.boot.autoconfigure.AutoConfigurationImportSelector` 使用了。再来看看 `AutoConfigurationImportSelector` 的简介：

```java
/**
 * {@link DeferredImportSelector} to handle {@link EnableAutoConfiguration
 * auto-configuration}. This class can also be subclassed if a custom variant of
 * {@link EnableAutoConfiguration @EnableAutoConfiguration} is needed.
 *
 * @author Phillip Webb
 * @author Andy Wilkinson
 * @author Stephane Nicoll
 * @author Madhura Bhave
 * @since 1.3.0
 * @see EnableAutoConfiguration
 */
public class AutoConfigurationImportSelector implements DeferredImportSelector, BeanClassLoaderAware,
		ResourceLoaderAware, BeanFactoryAware, EnvironmentAware, Ordered {
```

原来是处理 `@EnableAutoConfiguration` 注解的类。我想有人曾经对一般的 Spring Boot 程序的入口感到好奇：

```java
@SpringBootApplication
public class SampleApplication {

    public static void main(String[] args) {
        SpringApplication.run(SampleApplication.class, args);
    }

}
```

瞄了一下 `@SpringBootApplication`：

```java
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Inherited
@SpringBootConfiguration
@EnableAutoConfiguration
@ComponentScan(excludeFilters = { @Filter(type = FilterType.CUSTOM, classes = TypeExcludeFilter.class),
		@Filter(type = FilterType.CUSTOM, classes = AutoConfigurationExcludeFilter.class) })
public @interface SpringBootApplication {
```

当然，开启了自动配置。

## 推荐阅读

[Creating Your Own Auto-configuration / Starter](https://docs.spring.io/spring-boot/docs/current/reference/html/boot-features-developing-auto-configuration.html)

[mybatis/spring-boot-starter](https://github.com/mybatis/spring-boot-starter)
