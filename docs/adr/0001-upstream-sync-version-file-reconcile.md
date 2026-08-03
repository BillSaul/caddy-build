# 0001 - 上游同步：lock 文件 + reconcile 工作流

## 背景

Custom Image 需要自动跟踪 Upstream 的三类漂移并重建发布，同时避免无谓的重复构建。三类漂移：

1. Caddy 本体发新版（版本号可追踪）
2. tencentcloud 插件发新版（版本号可追踪）
3. 基础镜像 OS 补丁--`caddy:<ver>-alpine` tag 名不变、内容（digest）随上游 alpine 补丁漂移（不可靠版本号追踪）

## 决策

仓库根目录维护 `.upstream.lock` 文件，持有三个值，作为唯一事实来源：

```
caddy=2.11.4
plugin=v0.4.3
base=sha256:<caddy:<caddy>-alpine 的 manifest digest>
```

一个 reconcile 工作流按以下触发器运行：

- **每日定时**：取三个最新值--Caddy 最新稳定 release（`/releases/latest`，不含 pre-release）、插件最新 release（GitHub API）、当前 caddy 版本对应 `caddy:<ver>-alpine` 的 manifest digest（`docker buildx imagetools inspect`）。三者分别与 lock 比对，**任一不同才构建**（`--pull` 拉 fresh base），构建成功后把三个新值 bot 提交回 `.upstream.lock`。
- **手动 dispatch**：可带 `version` 输入强制构建指定 caddy 版本。
- **push 到 main 且改了 `Dockerfile`/workflow**：用当前 lock 重建（配置变更）。

Dockerfile **不**硬编码版本号；caddy 版本作为 `--build-arg CADDY_VERSION` 由工作流从 lock 注入。push 触发器只监听 `Dockerfile`/workflow 路径，lock 文件的 bot 提交不会回环触发。

## 考虑过的备选

- **查 GHCR tag 判断是否已构建**：丢失 git 审计轨迹，检查阶段需碰 registry API。否决。
- **每周强制重建当 base 漂移安全网**：base 补丁跟进慢（1 周），且有「啥也没变也重建」的浪费。改为每日 base digest 追踪后无需每周重建。
- **只追 caddy + 插件版本（不追 base digest）**：漏掉基础镜像 OS 补丁，公网 TLS 服务不可接受。

## 后果

- main 上会有 bot 的 lock 文件变更提交（审计需要，视为特性）。
- 同一 caddy 版本号 tag（如 `2.11.4`）在 base 补丁触发重建后会被覆盖为含新 OS 包的镜像，非字节可复现；可接受。
- **已知小缺口**：builder 镜像的 Go 运行时安全修复（静态编进 caddy 二进制）未单独追踪--通常 caddy 会在 Go 出安全修复时跟着发新版，被 caddy 版本追踪覆盖；仅 caddy 未跟上的窗口期会漏，必要时手动 dispatch 补。
