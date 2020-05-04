---
title: "使用 Lua 拓展 Nginx"
date: 2020-03-31T14:44:18+08:00
draft: false
description: ""
tags: [openresty, nginx, lua]
categories: []
---

体验 OpenResty。

<!--more-->

## Nginx

[Nginx](https://www.nginx.com/) 是高性能的负载均衡器、Web 服务器、反向代理服务器。它是我们既熟悉又陌生的老朋友，经常依靠它水平扩展应用程序、部署前端应用程序、代理应用程序、构建 API 网关等，Nginx 由纯 C 语言实现，但却非常易于使用。

早在 2005 年，官方博客用一篇标题为 [Inside NGINX: How We Designed for Performance & Scale](https://www.nginx.com/blog/inside-nginx-how-we-designed-for-performance-scale/) 的文章描述了 Nginx 的架构：

- Nginx 如何创建进程以有效利用资源。

- 使用状态机来管理流量（traffic）。

- 非阻塞和事件驱动的架构使 Nginx 可以同时调度多个状态机。

- 进程架构如何支持不间断的优雅更新和二进制升级。

![nginx_architecture_thumbnail](/img/nginx/nginx_architecture_thumbnail.png)

## OpenResty

不妨先看看 [OpenResty](https://openresty.org/) 官方的宣传语。

> OpenResty® 是一个基于 Nginx 与 Lua 的高性能 Web 平台，其内部集成了大量精良的 Lua 库、第三方模块以及大多数的依赖项。用于方便地搭建能够处理超高并发、扩展性极高的动态 Web 应用、Web 服务和动态网关。

比起使用 C 语言，使用 [Lua](https://www.lua.org/) 门槛要稍低一些，而且有 [LuaJIT](https://luajit.org/) 的性能优化。

> OpenResty® 通过汇聚各种设计精良的 Nginx 模块（主要由 OpenResty 团队自主开发），从而将 Nginx 有效地变成一个强大的通用 Web 应用平台。这样，Web 开发人员和系统工程师可以使用 Lua 脚本语言调动 Nginx 支持的各种 C 以及 Lua 模块，快速构造出足以胜任 10K 乃至 1000K 以上单机并发连接的高性能 Web 应用系统。

对于基于 I/O 多路复用（请见[网络·NIO # I/O 模型](https://h2cone.github.io/post/2020/03/network_nio/#i-o-%E6%A8%A1%E5%9E%8B)）的 Nginx 来说，单机 C1000K 不在话下，反而是受限于操作系统或配置。

> OpenResty® 的目标是让你的 Web 服务直接跑在 Nginx 服务内部，充分利用 Nginx 的非阻塞 I/O 模型，不仅仅对 HTTP 客户端请求，甚至于对远程后端诸如 MySQL、PostgreSQL、Memcached 以及 Redis 等都进行一致的高性能响应。

既然支持访问多种数据库，则足矣处理复杂的业务逻辑。

接下来，以一个名为 [openresty-exp/redis-example](https://github.com/h2cone/openresty-exp/tree/master/redis-example) 的例子来初步体验 OpenResty。

```
.
├── RedisExample.lua
├── conf
│   └── nginx.conf
├── logs
│   └── error.log
```

首先新建配置文件目录（conf）和日志文件目录（logs），然后编写 Nginx 配置文件（nginx.conf）。

```
worker_processes 1;
error_log logs/error.log;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80;
        location ~ /redis/(.+)/(.+) {
            charset utf-8;
            lua_code_cache on;
            content_by_lua_file RedisExample.lua;
        }
    }
}
```

Nginx http server 监听 80 端口，为了方便展示，匹配的请求 URL 包含两个路径参数。Nginx 处理 HTTP 请求分成了若干阶段，详情请见 [Nginx # http phases](http://nginx.org/en/docs/dev/development_guide.html#http_phases)，或则直接参考 [OpenResty # 执行阶段概念](https://moonbingbing.gitbooks.io/openresty-best-practices/ngx_lua/phase.html)，这里只关心正常生成响应的阶段（content）并使用 Lua 脚本处理业务逻辑。

假设 HTTP 客户端发送包含键值对的请求到 Nginx server，Nginx server 先将键值对插入 Redis 实例，然后再从 Redis 实例查询相应的键所对应的值，最后发送包含键值对的响应到 HTTP 客户端。

```lua
local json = require "cjson"
local redis = require "resty.redis"
local red = redis.new()

red:set_timeouts(1000, 1000, 1000)

local ok, err = red:connect("127.0.0.1", 6379)
if not ok then
    ngx.say("failed to connect: ", err)
    return
end

local key = ngx.var[1]
local val = ngx.var[2]

local ok, err = red:set(key, val)
if not ok then
    ngx.say("failed to set: ", err)
    return
end

local val, err = red:get(key)
if not val then
    ngx.say("failed to get: ", err)
    return
end

if val == ngx.null then
    ngx.say("key no found")
    return
end

local ok, err = red:close()
if not ok then
    ngx.say("failed to close: ", err)
    return
end

ngx.say(json.encode({[key]=val}))
```

启动 Nginx 并指定配置文件。

```shell
openresty -p `pwd`/ -c conf/nginx.conf
```

使用 HTTP 客户发送请求。

```shell
% curl 127.0.0.1/redis/hello/world
{"hello":"world"}
```

Nginx server 响应正常。

> 本文首发于 https://h2cone.github.io

## Memo

- [Inside NGINX](https://www.nginx.com/resources/library/infographic-inside-nginx/)

- [The Architecture of Open Source Applications (Volume 2): nginx](https://www.aosabook.org/en/nginx.html)

- [Nginx # development guide](http://nginx.org/en/docs/dev/development_guide.html)

- [HTTP request processing phases in Nginx](http://www.nginxguts.com/phases/)

- [Nginx # modules # lua](https://www.nginx.com/resources/wiki/modules/lua/)

- [OpenResty # Components](https://openresty.org/cn/components.html)

- [lua-nginx-module](https://github.com/openresty/lua-nginx-module)

- [lua-resty-redis](https://github.com/openresty/lua-resty-redis)

- [OpenResty 最佳实践](https://moonbingbing.gitbooks.io/openresty-best-practices/content/)

- [OpenResty 不完全指南](https://mp.weixin.qq.com/s/ddgT0DX3WA45PqC-30A45A)

- [Lua Style Guide](http://lua-users.org/wiki/LuaStyleGuide)
