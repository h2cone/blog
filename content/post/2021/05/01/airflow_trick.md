---
title: "Airflow 杂技"
date: 2021-05-01T18:12:03+08:00
draft: false
description: ""
tags: [airflow, python, codegen, java, docker, go]
categories: []
---

DAG 之道。

<!--more-->

## 背景

近期，从零开始搭建 [SOAR](https://www.gartner.com/en/information-technology/glossary/security-orchestration-automation-response-soar) 平台，其中[工作流](https://en.wikipedia.org/wiki/Workflow)引擎或任务编排组件是核心组件之一。

## Airflow

[Airflow](http://airflow.apache.org/) 是用于描述、执行、监控工作流的平台。目前为止，启动 Airflow 最快的方式是——[在 Docker 中运行 Airflow](https://airflow.apache.org/docs/apache-airflow/stable/start/docker.html)，这种安装方式也有利于可扩展性。

![airflow-architecture](/img/airflow/airflow-architecture.png)

有一些组件需要说明一下（此处省略 [Flower](https://airflow.apache.org/docs/apache-airflow/stable/security/flower.html)）：

- Webserver：提供访问 DAG、任务、变量、连接等等的状态信息的 [Airflow REST API](https://airflow.apache.org/docs/apache-airflow/stable/stable-rest-api-ref.html)。
- Scheduler：负责将必要的任务添加到队列中。
- Worker：执行由 Scheduler 分配的任务。
- Redis：Scheduler 与 Worker 之间的消息代理。
- Postgres：存储有关 DAG、任务、变量、连接等等的状态信息。

上述组件是进程级组件，需要注意的是 DAGs 并不是进程，而是指多个 Python 源文件。[DAG](https://airflow.apache.org/docs/apache-airflow/stable/concepts.html#dags) 是[有向无环图（Directed Acyclic Graph）](https://en.wikipedia.org/wiki/Directed_acyclic_graph)的缩写，从 Airflow 的角度来看，DAG 用于描述工作流，有向无环图中的结点被称为任务（Task），而 [Task](https://airflow.apache.org/docs/apache-airflow/stable/concepts.html#tasks) 是通过 [Operator](https://airflow.apache.org/docs/apache-airflow/stable/concepts.html#operators) 来实现。DAGs 的位置在 Airflow 配置文件中指定，重要的事情是 Webserver 和 Scheduler 以及 Worker 都需要读取 DAGs。

## 生成 DAG

编写 DAG 需要一定的 Python 知识，甚至 Airflow 并不提供创建 DAG 的 UI 或 REST API。情理之中，Airflow 创建工作流并不包含“无代码”或“低代码”特性，从官方首页可以看到其定位：

> Airflow is a platform created by the community to **programmatically** author, schedule and monitor workflows.

后端满足可视化任务编排需求解决方案之一是通过用户输入生成 DAG 源文件，即生成特定的 Python 源文件。

### 模板方法

体验过[编写 DAG](https://airflow.apache.org/docs/apache-airflow/stable/tutorial.html) 或浏览过 [DAG 示例](https://github.com/apache/airflow/tree/master/airflow/example_dags)之后可以归纳出 DAG 的一般结构：

1. Import Statements（导入语句）

2. Default Arguments（默认参数）

3. DAG Constructor（DAG 构造器）

4. Operators（Operator 构造器）

5. Dependencies（Operator 之间的依赖关系）

如果需要一些复杂函数才能满足需求，完全可以将复杂度转移到 Airflow 之外的服务提供者（service provider），例如在 DAG 中使用 [HTTP Operators](https://airflow.apache.org/docs/apache-airflow-providers-http/stable/operators.html) 向服务提供者发送请求，由服务提供者处理请求（具体业务逻辑在服务提供者实现）。

程序可以根据 DAG 的一般结构，依次追加代码片段。根据[关注点分离](https://en.wikipedia.org/wiki/Separation_of_concerns)原则，类似于模型（Model）与视图（View）的分离降低了复杂度，代码片段可分为静态内容和动态内容，前者通常是是样板代码，后者通常是参数值；将静态内容与动态内容合成源代码最便利的工具是[模板引擎](https://en.wikipedia.org/wiki/Template_processor)，而不是重新发明轮子。

![gen-dag](/img/airflow/gen-dag.png)

各种编程语言早已有[面向 Web 领域的模板引擎](https://en.wikipedia.org/wiki/Comparison_of_web_template_engines)，但此处并不需要基于文档树（DOM）生成，因为期望输出不是 HTML 之类的文件，而是 Python 源文件，即纯文本，因而考虑基于字符串的模板引擎，例如 [Antlr Project](https://github.com/antlr) 下的 [StringTemplate 4](https://github.com/antlr/stringtemplate4)，此[介绍](https://github.com/antlr/stringtemplate4/blob/master/doc/introduction.md)非常有助于理解 StringTemplate 4。

```java
import org.stringtemplate.v4.*;
...
class User {
    public int id; // template can directly access via u.id
    private String name; // template can't access this
    public User(int id, String name) { this.id = id; this.name = name; }
    public boolean isManager() { return true; } // u.manager
    public boolean hasParkingSpot() { return true; } // u.parkingSpot
    public String getName() { return name; } // u.name
    public String toString() { return id+":"+name; } // u
}
...
ST st = new ST("<b>$u.id$</b>: $u.name$", '$', '$');
st.add("u", new User(999, "parrt"));
String result = st.render(); // "<b>999</b>: parrt"
```

如何使用 StringTemplate 4 的模板表达式编写 DAG 模板？不妨参考 [airflow-up/templates](https://github.com/h2cone/airflow-up/tree/main/templates)。此处列举一例：

```text
<t.taskId> = SimpleHttpOperator(
    task_id='<t.taskId>',
    http_conn_id='<t.httpConnId>',
    endpoint='<t.endpoint>',
    method='<t.method>',
    <if(t.data)>data="{{ dag_run.conf['<t.taskId>']['data'] <if(t.dataFilter)><t.dataFilter><endif> }}",<endif>
    <if(t.headers)>headers=<t.headers>,<endif>
    <if(t.responseCheck)>response_check=<t.responseCheck>,<endif>
    <if(t.responseFilter)>response_filter=<t.responseFilter>,<endif>
    <if(t.extraOptions)>extra_options=<t.extraOptions>,<endif>
    <if(logResponse)>log_response=<logResponse>,<endif>
    dag=dag,
)
```

DAG 源文件甚至可以包含 [Jinja](https://jinja.palletsprojects.com) 表达式（dataFilter 的值选自 [Jinja2 内置过滤器](https://jinja.palletsprojects.com/en/2.11.x/templates/#builtin-filters)，在[触发 DAG 运行](https://airflow.apache.org/docs/apache-airflow/stable/dag-run.html#external-triggers)时，Airflow 渲染 DAG 源文件，并且传递额外配置参数（`dag_run.conf`）的值。之所以使用 Jinja2，除了 Airflow 天然支持以外，原因之一是业务系统将事件作为请求参数的一部分（额外配置参数）传递给 Webserver 用于触发一个新的 DAG 运行的接口（[POST /dags/{dag_id}/dagRuns](https://airflow.apache.org/docs/apache-airflow/stable/stable-rest-api-ref.html#operation/post_dag_run)），因此有些参数没法在生成 DAG 源文件时确定，而只能在运行时确定。

> Note: The parameters from dag_run.conf can only be used in a template field of an operator.

原因之二是 [SimpleHttpOperator](https://airflow.apache.org/docs/apache-airflow-providers-http/stable/_api/airflow/providers/http/operators/http/index.html) 或 [HttpSensor](https://airflow.apache.org/docs/apache-airflow-providers-http/stable/_api/airflow/providers/http/sensors/http/index.html) 的构造器对于不同的请求方法（method）要求不同结构的请求参数（data），例如 POST 请求参数要求 [JSON](https://en.wikipedia.org/wiki/JSON)，而 GET 请求参数要求 [Query String](https://en.wikipedia.org/wiki/Query_string)。

Airflow 官方推荐[使用移位运算符定义 Operator 之间的依赖关系](https://airflow.apache.org/docs/apache-airflow/stable/concepts.html#bitshift-composition)。用户提交到后端的流程图（通常是树或有向无环图）定义了结点之间的依赖关系，生成 Operator 之间的依赖关系最直截了当的方式是使用[深度搜索](https://en.wikipedia.org/wiki/Depth-first_search)列出所有路径：每个栈帧都维护一个有序列表（子路径），方法执行过程将结点或 Operator 添加到子路径，递归调用时将子路径元素存入新子路径，循环结束后将子路径添加到主路径。

![demo_tree-path](/img/data-structure/demo_tree-path.png)

### DAG 代理

Airflow 的 Scheduler 定期扫描 [DAG 目录](https://airflow.apache.org/docs/apache-airflow/stable/configurations-ref.html#dags-folder)，发现新 DAG 文件，同时定期解析该目录下的每一个 DAG 文件，两者的频率可通过 [min_file_process_interval](https://airflow.apache.org/docs/apache-airflow/stable/configurations-ref.html#min-file-process-interval) 和 [dag_dir_list_interval](https://airflow.apache.org/docs/apache-airflow/stable/configurations-ref.html#dag-dir-list-interval) 设置。应用程序是否也必须知道该目录的绝对路径？应用程序必须与 Airflow 运行在同一台服务器上？显然不是，只需要在应用程序与 DAGs 之间插入一个中间层。

![dag-agent](/img/airflow/dag-agent.png)

#### 共享卷

假如在 Docker 中运行 Airflow，方便开发运维起见，DagAgent 理应在 Docker 中运行，但是 DagAgent 接收到 DAG 文件后应该写到哪里去？以 [airflow/docker-compose.yaml](https://airflow.apache.org/docs/apache-airflow/stable/docker-compose.yaml) 为例，创建了三个[卷（Volume）](https://docs.docker.com/storage/volumes/)：

```yaml
version: '3'
x-airflow-common:
  ...
  volumes:
    - ./dags:/opt/airflow/dags
    - ./logs:/opt/airflow/logs
    - ./plugins:/opt/airflow/plugins
  ...
...
```

其中 DAG 目录的源地址是 `./dags`（宿主机视角），而目的地是 `/opt/airflow/dags`（Docker 容器视角）；可喜可贺的是 [Docker CLI 已经支持 Compose 命令](https://docs.docker.com/compose/cli-command/)，捣鼓 Docker 版 Airflow 也就不需要 [docker-compose](https://github.com/docker/compose) ：

```shell
% docker compose up -d
[+] Running 8/8
 ⠿ Network "airflow_default"              Created                                                                                                              0.6s
 ⠿ Container airflow_redis_1              Started                                                                                                              1.6s
 ⠿ Container airflow_postgres_1           Started                                                                                                              1.4s
 ⠿ Container airflow_airflow-scheduler_1  Started                                                                                                             10.0s
 ⠿ Container airflow_airflow-init_1       Started                                                                                                             10.3s
 ⠿ Container airflow_airflow-worker_1     Started                                                                                                             10.5s
 ⠿ Container airflow_airflow-webserver_1  Started                                                                                                              7.8s
 ⠿ Container airflow_dagagent_1           Started                                                                                                             10.6s
% docker ps
CONTAINER ID   IMAGE                  COMMAND                  CREATED          STATUS                    PORTS                    NAMES
122a8455e781   dagagent:latest        "./dagagent"             16 minutes ago   Up 16 minutes (healthy)   0.0.0.0:1323->1323/tcp   airflow_dagagent_1
8ab76a88a05a   apache/airflow:2.0.2   "/usr/bin/dumb-init …"   16 minutes ago   Up 16 minutes (healthy)   0.0.0.0:8889->8080/tcp   airflow_airflow-webserver_1
1d0e1b191ea0   apache/airflow:2.0.2   "/usr/bin/dumb-init …"   16 minutes ago   Up 16 minutes             8080/tcp                 airflow_airflow-scheduler_1
a389b993a2c3   apache/airflow:2.0.2   "/usr/bin/dumb-init …"   16 minutes ago   Up 16 minutes             8080/tcp                 airflow_airflow-worker_1
12015f9bc778   postgres:13            "docker-entrypoint.s…"   16 minutes ago   Up 16 minutes (healthy)   5432/tcp                 airflow_postgres_1
e32501a14963   redis:latest           "docker-entrypoint.s…"   16 minutes ago   Up 16 minutes (healthy)   0.0.0.0:6379->6379/tcp   airflow_redis_1
```

当前主目录如下：

```shell
.
├── dags
├── logs
├── plugins
└── docker-compose.yaml
```

在宿主机上将 DAG 文件输入到 `dags`，运行在 Docker 中的 Airflow 可感知；Airflow 的 Docker 容器输出的文件在宿主机可观测。由于 DagAgent 容器化，它的文件 I/O 自然作用于容器文件系统，因此从 DagAgent 的角度来看，DAG 目录也是 `/opt/airflow/dags`；既然 Webserver、Scheduler、Worker 都引用了 `airflow-common`，DagAgent 服务配置中可以使用 [volumes_from](https://docs.docker.com/compose/compose-file/compose-file-v2/#volumes_from) 共享 DAG 目录：

```yaml
...
  dagagent:
    image: dagagent:latest
    ports:
      - 1323:1323
    environment:
      AIRFLOW__CORE__DAGS_FOLDER: /opt/airflow/dags
      ...
    volumes_from:
      - airflow-webserver:rw
    ...
...
```

#### 最小化镜像

DagAgent 仅仅是一个微小的服务，容器化 Java 程序的话通常过于重量级，不妨使用 Go 编写，详情可参考 [dagagent](https://github.com/h2cone/dagagent)。

基于 [Go 官方镜像](https://hub.docker.com/_/golang)构建应用程序镜像，直接了当的 [Dockerfile](https://docs.docker.com/engine/reference/builder/) 文件：

```dockerfile
FROM golang:1.16

WORKDIR /go/src/github.com/h2cone/dagagent
COPY . .

RUN go get -d -v ./...
RUN go install -v ./...

CMD ["dagagent"]
```

构建名为 dagagent:straightforward 的镜像：

```shell
% docker build -t dagagent:straightforward -f docker/Dockerfile-straightforward .
```

但是 dagagent:straightforward 实在是太大了！

```shell
% docker image list
REPOSITORY       TAG               IMAGE ID       CREATED         SIZE
dagagent         straightforward   149604a01e75   6 seconds ago   1.05GB
redis            latest            739b59b96069   2 weeks ago     105MB
apache/airflow   2.0.2             d7a0ff8c98a9   2 weeks ago     871MB
postgres         13                26c8bcd8b719   3 weeks ago     314MB
```

基础镜像是罪魁祸首？使用 `golang:1.16-alpine` 代替 `golang:1.16`：

```dockerfile
FROM golang:1.16-alpine

WORKDIR /go/src/github.com/h2cone/dagagent
COPY . .

RUN go get -d -v
RUN go install -v

CMD ["dagagent"]
```

构建名为 dagagent:small 的镜像：

```shell
% docker build -t dagagent:small -f docker/Dockerfile-small .
```

该镜像大小已经小于 1G，是否还能再精简？

```shell
% docker image list                                          
REPOSITORY       TAG               IMAGE ID       CREATED              SIZE
dagagent         small             145b612b635e   5 seconds ago        485MB
dagagent         straightforward   149604a01e75   About a minute ago   1.05GB
redis            latest            739b59b96069   2 weeks ago          105MB
apache/airflow   2.0.2             d7a0ff8c98a9   2 weeks ago          871MB
postgres         13                26c8bcd8b719   3 weeks ago          314MB
```

分析一下以上两个镜像的组成，至少包含下载的依赖文件、应用程序的源文件、静态编译输出的可执行文件等。DagAgent 运行时只需要可执行文件与操作系统，故使用[多阶段构建（multi-stage builds）](https://docs.docker.com/develop/develop-images/multistage-build/)，将编译时与运行时分为两个阶段，运行时所需的可执行文件拷贝自编译时，最终只产出包含可执行文件与操作系统的镜像：

```dockerfile
FROM golang:1.16-alpine3.12 AS builder

WORKDIR /go/src/github.com/h2cone/dagagent
COPY . .

RUN go build -v

FROM alpine:3.12

WORKDIR /root
COPY --from=builder /go/src/github.com/h2cone/dagagent/dagagent .
CMD ["./dagagent"]
```

构建名为 dagagent:min 的镜像：

```shell
% docker build -t dagagent:min -f docker/Dockerfile-min .
```

该镜像大小已降低 94%：

```shell
% docker image list                                      
REPOSITORY       TAG               IMAGE ID       CREATED          SIZE
dagagent         min               75dbfbb53d78   10 seconds ago   27.3MB
dagagent         small             145b612b635e   4 minutes ago    485MB
dagagent         straightforward   149604a01e75   5 minutes ago    1.05GB
redis            latest            739b59b96069   2 weeks ago      105MB
apache/airflow   2.0.2             d7a0ff8c98a9   2 weeks ago      871MB
postgres         13                26c8bcd8b719   3 weeks ago      314MB
```

#### 加速构建

回头看 dagagent:straightforward，除了镜像过大，还有一个缺点，即下载依赖时（通常最耗时）无法命中缓存。只更新了 DagAgent 的源代码但不更新依赖，构建镜像时却需重新下载依赖。

加速镜像构建首要方式是充分利用[构建缓存（Leverage build cache）](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#leverage-build-cache)。Docker 镜像建立在一系列[层](https://docs.docker.com/storage/storagedriver/#images-and-layers)之上，每一层表示 Dockerfile 中的一条指令的执行结果。假如不禁用缓存，Docker 执行每一条 Dockerfile 指令时先查找之前层的缓存，若命中（例如[校验和](https://en.wikipedia.org/wiki/Checksum)相等），则不重新执行当前指令而是引用已存在的层。一般情况下，结果不易变的指令写在结果易变的指令之前的 Dockerfile 缓存利用率更高。

DagAgent 源代码比依赖更易变，根据上文，先下载依赖后拷贝源代码：

```dockerfile
FROM golang:1.16

WORKDIR /go/src/github.com/h2cone/dagagent
COPY go.mod .
COPY go.sum .
RUN go mod download -x

COPY . .

RUN go install -v

CMD ["dagagent"]
```

结合上一节的“最小化镜像”，最终版本的 Dockerfile 如下所示：

```dockerfile
# syntax=docker/dockerfile:1
FROM golang:1.16-alpine3.12 AS builder

ENV GOPROXY="https://goproxy.io,direct"

WORKDIR /go/src/github.com/h2cone/dagagent
COPY go.mod .
COPY go.sum .
RUN go mod download -x

COPY . .

RUN go build -v

FROM alpine:3.12
RUN apk add curl

WORKDIR /root
COPY --from=builder /go/src/github.com/h2cone/dagagent/dagagent .
CMD ["./dagagent"]
```

构建名为 dagagent:latest 的镜像:

```shell
% docker build -t dagagent -f docker/Dockerfile .
[+] Building 36.5s (19/19) FINISHED                                                                                                                                          
 => [internal] load build definition from Dockerfile                                                                                                                    0.0s
 => => transferring dockerfile: 37B                                                                                                                                     0.0s
 => [internal] load .dockerignore                                                                                                                                       0.0s
 => => transferring context: 2B                                                                                                                                         0.0s
 => resolve image config for docker.io/docker/dockerfile:1                                                                                                             19.2s
 => CACHED docker-image://docker.io/docker/dockerfile:1@sha256:e2a8561e419ab1ba6b2fe6cbdf49fd92b95912df1cf7d313c3e2230a333fdbcc                                         0.0s
 => [internal] load metadata for docker.io/library/alpine:3.12                                                                                                          7.6s
 => [internal] load metadata for docker.io/library/golang:1.16-alpine3.12                                                                                              17.1s
 => [builder 1/7] FROM docker.io/library/golang:1.16-alpine3.12@sha256:1636899c10870ab66c48d960a9df620f4f9e86a0c72fbacf36032d27404e7e6c                                 0.0s
 => => resolve docker.io/library/golang:1.16-alpine3.12@sha256:1636899c10870ab66c48d960a9df620f4f9e86a0c72fbacf36032d27404e7e6c                                         0.0s
 => [stage-1 1/4] FROM docker.io/library/alpine:3.12@sha256:36553b10a4947067b9fbb7d532951066293a68eae893beba1d9235f7d11a20ad                                            0.0s
 => [internal] load build context                                                                                                                                       0.0s
 => => transferring context: 6.42kB                                                                                                                                     0.0s
 => CACHED [stage-1 2/4] RUN apk add curl                                                                                                                               0.0s
 => CACHED [stage-1 3/4] WORKDIR /root                                                                                                                                  0.0s
 => CACHED [builder 2/7] WORKDIR /go/src/github.com/h2cone/dagagent                                                                                                     0.0s
 => CACHED [builder 3/7] COPY go.mod .                                                                                                                                  0.0s
 => CACHED [builder 4/7] COPY go.sum .                                                                                                                                  0.0s
 => CACHED [builder 5/7] RUN go mod download -x                                                                                                                         0.0s
 => CACHED [builder 6/7] COPY . .                                                                                                                                       0.0s
 => CACHED [builder 7/7] RUN go build -v                                                                                                                                0.0s
 => CACHED [stage-1 4/4] COPY --from=builder /go/src/github.com/h2cone/dagagent/dagagent .                                                                              0.0s
 => exporting to image                                                                                                                                                  0.0s
 => => exporting layers                                                                                                                                                 0.0s
 => => writing image sha256:ad807e3e1bda89824e55db14088156f9d4e8dabce6d4e79af117eb533371e4dc                                                                            0.0s
 => => naming to docker.io/library/dagagent                                                                                                                             0.0s
```

判断指令是否命中缓存可通过一个关键词——`CACHED`来判断。

## 插件发现

当 Airflow 生态的现有的 Operators 不满足需求时，可以考虑[自定义 Operator](https://airflow.apache.org/docs/apache-airflow/stable/howto/custom-operator.html)，例如要实现一个[哨兵语句式的 HTTP Operator](https://github.com/h2cone/airflow-up/blob/main/plugins/operators/simple_http_sentinel.py)（与名为 `none_failed_or_skipped` 的[触发规则](https://airflow.apache.org/docs/apache-airflow/stable/concepts.html#trigger-rules)一起）。

```shell
.
├── dags
├── logs
├── plugins
│   └── operators
│       ├── __init__.py
│       └── simple_http_sentinel.py
└── docker-compose.yaml
```

实现了新的 Operator 之后，当前版本的 Airflow 能够发现类似上面 plugins/operators 目录下的自定义 Operator，技巧在于内容空白的 `__init__.py`，自定义 Operator 的导入语句如下：

```python
from operators.simple_http_sentinel import SimpleHttpSentinel
```

## 状态同步

业务系统很可能需要知道一个 DAG 运行后的状态（成功或失败），[DAG](https://airflow.apache.org/docs/apache-airflow/stable/_api/airflow/models/dag/index.html) 构造器有成功/失败的回调函数类型的参数（`on_success_callback`/`on_failure_callback`），美中不足的是没有表示失败重试次数的参数，然而受到 [Python Requests 的高级使用 - 超时，重试，钩子](https://findwork.dev/blog/advanced-usage-python-requests-timeouts-retries-hooks/)的启发，于是编写了 [templates/dag_post_callback](https://github.com/h2cone/airflow-up/blob/main/templates/dag_post_callback) 来提高回调更新状态的成功率。

## 尾声

曾经考虑过 Uber 的编排引擎（orchestration engine）——[Cadence](https://cadenceworkflow.io/)。

> 本文首发于 https://h2cone.github.io

## 参考资料

- [Airflow # Concepts](https://airflow.apache.org/docs/apache-airflow/stable/concepts.html)

- [Airflow # Celery Executor](https://airflow.apache.org/docs/apache-airflow/stable/executor/celery.html)

- [Airflow # Configuration Reference](https://airflow.apache.org/docs/apache-airflow/stable/configurations-ref.html)

- [Airflow # Ecosystem](https://airflow.apache.org/ecosystem/)

- [Curated list of resources about Apache Airflow](https://github.com/jghoman/awesome-apache-airflow)

- [Develop with Docker](https://docs.docker.com/develop)
