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

遥想以前，Spring 集成其它模块往往需要大量的 XML 配置和 Java 配置，经历过 SSM（Spring、Spring MVC、Mybatis）或者 SSH（Struts、Spring、Hibernate）框架搭建和填空的人们应该深有体会，特别费时费力，直到 Spring Boot 的流行才有所改善。

Spring Boot 简化配置，开箱即用，得益于自动配置（auto-configuration）。如果我们向一般的 Spring Boot Web 程序（添加了 `spring-boot-starter-web` 依赖的 Spring Boot 程序）关联的 `application.yml` 文件增加一行：

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

这份报告分为四个部分：`Positive matches`、`Negative matches`、`Exclusions`、`Unconditional classes`，顾名思义，对于这个程序内嵌的应用服务器，只有 `Tomcat` 的配置类是匹配的，而 `Jetty`、`Undertow`、`Netty` 的配置类均不匹配，它们共同的外部类则是一个自动配置类：[EmbeddedWebServerFactoryCustomizerAutoConfiguration](https://github.com/spring-projects/spring-boot/blob/v2.2.4.RELEASE/spring-boot-project/spring-boot-autoconfigure/src/main/java/org/springframework/boot/autoconfigure/web/embedded/EmbeddedWebServerFactoryCustomizerAutoConfiguration.java)，这就是 Spring Boot 提供的内嵌应用服务器的基础配置，满足一些条件时，即匹配，框架就自动进行了配置，例如，提前创建好一些复杂单例，注册为 Spring Bean ...... 不出意外，Web 模块需要配置的 `Dispatcher Servlet`、数据库操作需要配置的数据源等等，Spring Boot 都提供了基础的配置（见 [spring.factories](https://github.com/spring-projects/spring-boot/blob/v2.2.4.RELEASE/spring-boot-project/spring-boot-autoconfigure/src/main/resources/META-INF/spring.factories) 文件），通常只需要添加对应的依赖，简单声明一下，开箱即用，即使默认配置不满足后期需求，也支持覆盖或重写。

## 自定义

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

`SpringFoxSwagger2AutoConfig` 的目的是创建 `springfox.documentation.spring.web.plugins.Docket` 实例并交由 Spring IoC 容器管理，为了能够让 Spring Boot 采用这个自动配置类，应当在 `src/main/resources/META-INF/spring.factories` 文件里声明：

```text
org.springframework.boot.autoconfigure.EnableAutoConfiguration=\
io.h2cone.springfox.swagger2.spring.boot.autoconfigure.SpringFoxSwagger2AutoConfig
```

若有多个，则用逗号隔开，若需换行，则用反斜杠。以上代码来源于 [springfox-swagger2-spring-boot](https://github.com/h2cone/springfox-swagger2-spring-boot)，其中有如下三个模块:

- springfox-swagger2-spring-boot-autoconfigure
- springfox-swagger2-spring-boot-starter
- springfox-swagger2-spring-boot-sample

职责分别是自动配置、包装、示例，依赖关系就像 [x-spring-boot](https://github.com/h2cone/x-spring-boot) 一样单纯。

## 推荐阅读

[Creating Your Own Auto-configuration / Starter](https://docs.spring.io/spring-boot/docs/current/reference/html/boot-features-developing-auto-configuration.html)
