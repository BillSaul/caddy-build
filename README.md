# caddy-build

自定义 Caddy 容器镜像，内置 [腾讯云（DNSPod）DNS 插件](https://github.com/caddy-dns/tencentcloud)，用于 ACME **DNS-01 challenge** 实现自动 HTTPS。通过 GitHub Actions 自动跟踪上游并重建发布到 GHCR。

镜像本身是**通用的**：只含 `caddy` 二进制 + 插件。Caddyfile、域名、腾讯云凭证都在运行时挂载/注入，不进镜像。

## 它怎么工作

镜像派生自三类上游源头（见 `CONTEXT.md` 的 Upstream），任一漂移都会触发重建：

| 漂移源 | 追踪方式 |
|---|---|
| Caddy 本体发版 | GitHub `releases/latest` tag |
| tencentcloud 插件发版 | GitHub `releases/latest` tag |
| 基础镜像 OS 补丁（`caddy:<ver>-alpine` 的 digest） | Docker Hub manifest digest |

`.upstream.lock` 是唯一事实来源，记三个值：

```
caddy=2.11.4
plugin=v0.4.3
base=sha256:5f5c8640...
```

`build.yml` 工作流（`.github/workflows/build.yml`）按这些触发器运行：

- **每日 03:00 UTC**：取三个最新值，与 lock 比对，任一不同才构建，构建成功后把新值 bot 提交回 `.upstream.lock`。
- **手动 dispatch**：可带 `version` 输入强制构建指定 Caddy 版本。
- **push 到 main 且改了 `Dockerfile`/workflow**：用当前 lock 重建（配置变更）。
- **PR**：只构建不推送（验证 Dockerfile，secrets 不暴露给 fork）。

> 决策细节见 `docs/adr/0001-upstream-sync-version-file-reconcile.md`。

构建产物为多架构（amd64 + arm64），用原生 arm64 runner 分别构建再合并 manifest，不走 QEMU。tag 策略：`<精确版本>`（如 `2.11.4`）+ `latest`。

## 文件结构

```
.
├── .upstream.lock              # 三值锁，事实来源
├── Dockerfile                  # 多阶段：官方 builder + alpine，覆盖二进制
├── Caddyfile.example           # DNS-01 challenge 示例配置
├── docker-compose.example.yml  # 起容器示例
├── CONTEXT.md                  # 领域术语表
├── docs/adr/                   # 架构决策记录
└── .github/
    ├── workflows/build.yml     # 同步 + 构建 + 发布
    └── dependabot.yml          # 给 SHA-pinned actions 提 bump
```

## 首次设置

### 1. GHCR 镜像可见性

首次 workflow 推送后，GHCR 会创建一个 **private** 的 `caddy` package（与仓库可见性互相独立）。要让它公开可匿名 pull：

- GitHub 仓库页 → 右侧 `Packages` → `caddy` → `Package settings` → `Danger Zone` → `Change visibility` → `Public`。

> `GITHUB_TOKEN` 权限不够改可见性，必须手动翻一次。之后无需再动。

### 2. 腾讯云 CAM 子账号（最小权限）

不要用主账号凭证。在 [腾讯云 CAM](https://console.cloud.tencent.com/cam) 建子用户，挂 **`QcloudDNSPodFullAccess`** 策略（最简），或自定义策略只给 DNS 记录增删查（更最小权限，操作：`dnspod:DescribeRecordList` / `CreateRecord` / `DeleteRecord`，资源限定你的域名）。

取该子用户的 `SecretId` / `SecretKey`，运行时作为 `TENCENTCLOUD_SECRET_ID` / `TENCENTCLOUD_SECRET_KEY` 注入。

## 运行

```bash
cp Caddyfile.example Caddyfile
# 编辑 Caddyfile，把 {your-domain} 换成你的域名

cat > .env <<EOF
TENCENTCLOUD_SECRET_ID=AKIDxxxxxxxx
TENCENTCLOUD_SECRET_KEY=xxxxxxxx
EOF

# 编辑 docker-compose.example.yml，把 <owner> 换成你的 GitHub 用户名
cp docker-compose.example.yml docker-compose.yml
docker compose up -d
```

Caddy 会通过 DNS-01 在腾讯云上自动申请并续期证书，无需开放入站 80 端口。

## 手动触发

- **构建最新版**：仓库 → Actions → `build` → `Run workflow`（version 留空）。
- **构建指定版**：同上，version 填如 `2.11.4`。
- **强制刷新当前版**（例如怀疑插件更新但 lock 没变）：手动 dispatch 留空 version，会以最新插件重建当前 Caddy 版本并覆盖同名 tag。

## 本地构建

```bash
docker build --build-arg CADDY_VERSION=2.11.4 -t caddy-tencentcloud .
docker run --rm -p 8080:80 caddy-tencentcloud caddy version
```

## 备注 / 排错

- **同名 tag 被覆盖**：`2.11.4` 在基础镜像补丁触发重建后会被覆盖为含新 OS 包的镜像（caddy 版本号不变，底层 alpine 刷新），非字节可复现。属预期。
- **arm64 构建失败**：公开仓库的 `ubuntu-24.04-arm` runner 免费可用；若你的仓库改为私有，arm64 runner 需付费计划，届时从 `build.yml` 的 matrix 移除 arm64 条目即可退回 amd64-only。
- **lock 没更新但想刷新**：见上文「手动触发 → 强制刷新当前版」。
- **检查当前锁定的版本**：`cat .upstream.lock`，或看 Actions 运行日志的 `trigger=...` notice 行。
- **update-lock 推送失败 (403)**：仓库 Settings -> Actions -> General -> Workflow permissions 需为 "Read and write permissions"（job 级 `permissions: contents: write` 通常已足够；若组织强制只读则需放开）。
