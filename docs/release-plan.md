# Windows 版发布方案（v2：不向上游提 PR）

> 状态：方案已落地。仓库结构、重放脚本与首次发布（1.15.0-w1）都已完成，
> 本文保留当时的取舍与理由；当前流程以 [upstream-sync.md](upstream-sync.md) 与
> [port/README.md](../port/README.md) 为准。

> 前提变更：**不与上游协作、不提 PR、不指望合并回去**。
> 这一条把方案从"维护一个跟得上上游的 fork"简化成"维护一个能吸收上游更新的独立发行版"。

## 0. 硬事实（不变）

| 项 | 值 |
|---|---|
| 上游许可 | 代码 **Apache-2.0**；47 个胶片配置与编辑器字形 **CC BY-SA 4.0**；**不授予商标权** |
| 上游版本 | `MARKETING_VERSION=1.14`，`CURRENT_PROJECT_VERSION=1024` |
| 我们的改动 | 修改 98 文件 / 新增 244（其中 210 是生成物） |
| 产物 | 便携单 exe 97 MB；安装包预计 ~95 MB |

许可义务与我们是否提 PR 无关：Apache-2.0 第 4(b) 条要求**改过的文件有变更声明**，
CC BY-SA 4.0 要求**署名 + 说明改动**，商标**没有授权**。

## 1. 因为不提 PR，方案简化了四处

| 原来（fork 思路） | 现在（独立发行版） |
|---|---|
| fork 关系、GitHub 的 upstream 比对 | **不需要**，独立仓库 |
| 补丁要"能被上游接受"的写法 | 不用迁就上游风格，只管我们自己看得懂 |
| 分支上要能 `git merge upstream/main` | 改成**重放**：新版本上重新打补丁 |
| 贡献指南、issue 模板、CoC | 不需要（除非你以后想收社区 PR） |

代价：GitHub 上没有 fork 徽章、`git blame` 看不到上游历史。**所以溯源必须靠文档写清楚**，
比原来更重要，不是更不重要。

## 2. 仓库形态：独立仓库，只放"我们这层"

不再把上游代码复制进仓库，也不再做 fork。

```
F:\Futo\fotufilm-windows\        ← 发布目录 = 仓库根目录，几百个文件，不含上游代码
├─ README.md / README.zh.md
├─ NOTICE-PORT.md                 ← Apache §4(b) 的变更声明
├─ LICENSE                        ← Apache-2.0（我们的移植层）
├─ upstream.lock                  ← 上游 commit + version.env + 工具链版本
├─ port/
│  ├─ patches/                    ← 14 个补丁（对上游文件的改动）
│  ├─ overlay/                    ← 新增文件树（flutter/windows、packaging、tools、i18n）
│  └─ i18n/                       ← zh-catalogue.json / zh-ui.json
├─ installer/fotufilm.iss
├─ scripts/{sync-upstream,apply-port,build}.ps1
└─ .github/workflows/sync-check.yml
```

`vendor/upstream` 与 `work/` 都 gitignore，由脚本按 `upstream.lock` 现场克隆、铺层、打补丁。

**好处**：仓库小（无 2187 个上游文件）、历史干净、没有合并冲突这回事——
同步就是"在新版本上重放"，冲突只可能出现在 14 个补丁里，看得见、改得动。

**代价**：不能对着上游代码在线跳转查历史；排查时得把 `vendor` 拉下来。
对个人/小团队发行版，这个代价可以接受。

## 3. 溯源：把"移植自谁、汉化了什么"写死在三处

没有 fork 徽章，社区第一眼靠 README 判断。三处都要写：

**① README 首屏**（中英各一段）
- 一句话定位："Fotufilm（https://fotufilm.com）的非官方 Windows 移植，含简体中文界面。"
- "Not affiliated with, endorsed by, or sponsored by MUAStudio Inc."
- 跟随的上游版本、最近同步日期
- 两条链接：`NOTICE-PORT.md`（改了什么）、`docs/upstream-sync.md`（怎么跟版本）

**② `NOTICE-PORT.md`** —— 按类别列改动，每类给文件清单：
Win32 内存映射、Halide Windows 兼容层与 AOT、vcpkg/CMake 接线、Windows runner、汉化、打包工具。
这张表同时也是维护者的地图。

**③ 应用内**
- 关于对话框：版本号 + "Windows port …，based on Fotufilm 1.14" + 上游链接
- 开源许可页：把 CC BY-SA 的胶片配置与字形单独列出（现在只列了 Apache 部分）
- 安装包 `licenses\ ` 目录随包带 `LICENSE` / `NOTICE` / `LICENSING.md` / `THIRD_PARTY_NOTICES.md`

## 4. 跟随上游：重放，不是合并

```
sync-upstream.ps1 -Tag v1.15.0
  ├ fetch → checkout <tag> 到 vendor/upstream
  ├ 复制到 work/（干净副本）
  ├ 铺 port/overlay          （新文件，直接覆盖）
  ├ git apply port/patches/* （14 个补丁；失败就 print reject）
  ├ 跑 apply-zh              （汉化：生成 lib/i18n/zh.dart + 改写 UI 字面量）
  ├ 跑三个检查脚本           （分组 / module 键 / 标识位翻译）
  └ 更新 upstream.lock，输出"下一步：build.ps1"
```

**版本号**：`1.14.0-w1`（上游 1.14.0 + 移植修订 1）；只改移植层就 `-w2`。

**CI（可选但推荐）**：每周跑 `sync-upstream.ps1 -DryRun`，只判断"补丁还打得上吗"，
失败就在仓库里开一个 issue。**不做完整构建**——Swift 6.2 + Halide + vcpkg 在
windows-latest 上跑不动，不值得。

README 放进度表：

| 上游 | 本移植 | 日期 | 备注 |
|---|---|---|---|
| 1.14 | 1.14.0-w1 | 2026-11-07 | 首个 Windows 版 |

## 5. 两种产物

| 产物 | 做法 | 体积 | 说明 |
|---|---|---|---|
| **便携版** | 现有启动器 + 压缩归档，双击解包到 `%LOCALAPPDATA%\Fotufilm\runtime\<hash>` | 97 MB | 免安装，带进度窗口与目录回退 |
| **安装版** | Inno Setup 6，每用户安装（`PrivilegesRequired=lowest`） | ~95 MB | 开始菜单项 + HKCU 卸载项 + 卸载程序 |

MSIX 排除（强制签名，与"不签名"冲突）。两份产物共用同一份 `dist\app`。
不签名 → SmartScreen 必拦，Release 说明里写清操作步骤，附 `SHA256SUMS.txt`。

系统要求写进 Release：Windows 10 1903+ / 11，x64，AVX2，**支持 Vulkan 的显卡**。

## 6. 发布流程

```
1. sync-upstream.ps1 -Tag v<新版本>   → 补丁全绿
2. build.ps1                          → 全量构建 + 冒烟
3. 打两个包 + SHA256SUMS.txt
4. tag v<ver>-w<N>，push
5. GitHub Release：正文写"Changes from upstream / What's new in this port（中文为主）"
6. 上传：portable.exe、setup.exe、SHA256SUMS.txt、source.tar.gz（上游 tag + 我们的层）
```

`source.tar.gz` 同时满足 CC BY-SA 的可获取要求，也让别人能复现。

## 7. 工作量

| 步骤 | 内容 | 预计 |
|---|---|---|
| P0 | 建仓库、导入移植层、产出 14 补丁 + overlay | 半天 |
| P1 | sync-upstream.ps1 跑通（不换版本也能完整重放） | 半天 |
| P2 | NOTICE-PORT + 双语 README + 许可口径 + 关于对话框 | 半天 |
| P3 | Inno 脚本 + 两产物 + SHA256 | 半天 |
| P4 | 同步检查 workflow（可选） | 1 小时 |
| P5 | 首次 Release 1.14.0-w1 | 1 小时 |

## 8. 已定

| 项 | 决定 |
|---|---|
| 仓库名 | `fotufilm-windows` |
| 程序名 | **Fotufilm for Windows (unofficial)**；中文界面写作「Fotufilm for Windows（非官方）」 |
| 发布暂存区 | `F:\Futo\fotufilm-windows\` —— 工作区改完、确认发布后，才把快照复制进去 |

**标识方式（已定）**：程序顶部横幅保持「Fotufilm 胶片暗房」不改；身份靠两处表达——

1. 横幅右侧一枚小字：`Fotufilm 1.14 · 2026-11-07`（原始项目版本 + 构建日期），悬停显示完整说明；
2. 关于对话框：移植版本 `1.14.0-w1`、上游版本、构建日期、上游链接、许可与"非官方"声明。

这两处由 `lib/app/build_info.dart` 驱动，构建时由 `build.ps1` 现场写入
（版本取 `upstream/version.env`，修订号取 `port-version.txt`）。

发布暂存区的规则写在 [release/README.md](../release/README.md)：只复制源码与脚本，不复制任何
构建缓存与生成物，标准是"别人 clone 后能按文档产出一模一样的 exe"。

## 9. 风险

- **商标**：描述性使用的边界；独立名可规避。
- **CC BY-SA**：分发未修改的配置与字形 → 义务是署名 + 说明改动，不要求我们整体转 BY-SA。
- **SmartScreen**：不签名必然出现，只能靠说明 + 哈希缓解。
- **补丁漂移**：`Package.swift` 最容易冲突（上游改依赖/目标时）。
- **上游消失或改许可**：我们按 Apache 已有副本继续，但要重新评估 BY-SA 部分。
