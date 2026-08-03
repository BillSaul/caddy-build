# syntax=docker/dockerfile:1
#
# 自定义 Caddy 镜像，内置腾讯云（DNSPod）DNS 提供商，用于 ACME DNS-01 challenge。
# Caddy 版本由 CI 工作流通过 --build-arg CADDY_VERSION 注入（见 .upstream.lock），
# 这里不硬编码，以便工作流升级版本时无需改动 Dockerfile。
#
# 本地构建：
#   docker build --build-arg CADDY_VERSION=2.11.4 -t caddy-tencentcloud .

ARG CADDY_VERSION=2.11.4

# --- 构建阶段：官方 caddy builder（已预装 xcaddy，已设置 CADDY_VERSION 环境变量）---
FROM caddy:${CADDY_VERSION}-builder AS builder
# xcaddy 按 builder 镜像内置的版本（== CADDY_VERSION）构建 Caddy，并拉取最新的
# tencentcloud 插件。XCADDY_SETCAP=1（builder 已设置）给输出二进制授予 cap_net_bind_service，
# 使其能以非 root 绑定 80/443 端口。
RUN xcaddy build \
      --with github.com/caddy-dns/tencentcloud

# --- 运行时阶段：官方 caddy:alpine，用我们自定义的二进制覆盖原 caddy ---
FROM caddy:${CADDY_VERSION}-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
