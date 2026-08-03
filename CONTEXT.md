# Caddy Build

构建一个内置腾讯云 DNS 插件的自定义 Caddy 容器镜像，并通过 GitHub Actions 自动跟踪上游 Caddy 版本重新构建与发布。Caddyfile、域名、腾讯云凭证均不在镜像内，由运行时挂载。

## Language

**Custom Image**:
我们的构建产物 -- 用 xcaddy 把 tencentcloud 插件编译进 caddy 二进制后得到的镜像。只含 caddy 二进制，不含 Caddyfile 与凭证。
_Avoid_: our caddy, the caddy image

**Official Image**:
上游 `caddyserver/caddy-docker` 发布的 `caddy:<version>-alpine` 与 `caddy:<version>-builder`，分别作为 Custom Image 的运行时基础镜像与构建镜像来源。
_Avoid_: base image, upstream image

**Upstream**:
Custom Image 跟踪的全部外部源头，共三类：Caddy 本体（`caddyserver/caddy` 的 release）、DNS 插件（`caddy-dns/tencentcloud` 的 release）、以及 Official Image（基础镜像）。前两类靠版本号追踪；第三类的 tag 名不变但内容随上游 OS 补丁漂移，只能靠 digest 追踪。任一变化都应触发一次 Sync。
_Avoid_: source, origin

**Sync**:
检测 Upstream 出现新版本后，重新构建 Custom Image 并发布的过程。是本项目存在的核心理由。
_Avoid_: update, rebuild
