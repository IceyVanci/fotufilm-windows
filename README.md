# Fotufilm for Windows (unofficial)

Fotufilm（https://fotufilm.com）的非官方 Windows 移植，附带简体中文界面。

> **Not affiliated with, endorsed by, or sponsored by MUAStudio Inc.**
> 与 MUAStudio Inc. 无隶属、授权或赞助关系。

上游项目：[DhaliwalX/fotufilm-engine](https://github.com/DhaliwalX/fotufilm-engine)

## 状态

跟随上游 **1.16**，移植版本号 `1.16.0-w1`。

## 这个移植做了什么

| 类别 | 内容 |
|---|---|
| 构建 | Swift 6.2 Windows 工具链 + MSVC，Halide 走 AOT Vulkan 核（无 JIT） |
| 平台层 | Win32 内存映射替换 POSIX mmap、Windows 宿主能力（浏览器/资源管理器/回收站） |
| 界面 | Flutter Windows runner，简体中文界面 |
| 发行 | 单文件便携版 |

详细清单见 [NOTICE-PORT.md](NOTICE-PORT.md)（Apache-2.0 第 4(b) 条要求的变更声明）。

## 功能范围

**只支持静态图片。** 这个移植没有接入视频与影片的宿主层：影片的导入、播放和导出在界面上不会出现，不是隐藏，是引擎自己关闭了这条路径。

| 能力 | 本版本 |
|---|---|
| 静态图片：RAW、JPEG、PNG、TIFF、HEIF、OpenEXR | ✅ |
| 负片扫描、片基取样、串色校正 | ✅ |
| 批量导出、缩略图 | ✅ |
| 视频 / 影片 | ❌ 引擎的影片层由各平台的媒体框架提供，Windows 侧未接入 |
| 插件安装、检查更新、社区胶片包 | ❌ 对应的宿主服务尚未接入 |
| 手机 / 平板布局 | ❌ 桌面窗口专属 |

## 系统要求

- Windows 10 1903+ / Windows 11，x64
- 支持 AVX2 的 CPU
- 支持 Vulkan 的显卡（引擎的 GPU 路径只有 Vulkan）

## 仓库结构

| 路径 | 内容 |
|---|---|
| `port/overlay/` | 移植自己写或改定的文件，按仓库内相对路径摆放 |
| `port/patches/` | 相对上游 tag 的 unified diff |
| `port/i18n/` | 汉化词表与重写器 |
| `scripts/sync-upstream.ps1` | 把移植层重放新的上游版本上 |
| `scripts/build.ps1` | 引擎 + 界面 + 单文件打包 |
| `packaging/` | 启动器与压缩打包器的源码 |
| `upstream.lock` | 当前携带的上游 tag 与 commit |
| `docs/` | 构建说明、跟随上游的流程 |

这里不放上游代码。重放方式见 [port/README.md](port/README.md) 与 [docs/upstream-sync.md](docs/upstream-sync.md)。

## 许可

- 本项目新增的代码：**Apache-2.0**
- 上游代码：**Apache-2.0**（MUAStudio Inc.）
- 47 个胶片配置与编辑器字形：**CC BY-SA 4.0**，版权归 MUAStudio Inc.，原样分发

仓库根目录带有 `LICENSE`、`NOTICE`、`LICENSING.md`、`THIRD_PARTY_NOTICES.md` 与 `licenses/`；
发行包内同样附带这些文件。对上游的改动见 `NOTICE-PORT.md`。

## English

An unofficial Windows port of [Fotufilm](https://fotufilm.com) with a Simplified Chinese interface.
Not affiliated with MUAStudio Inc. Code under Apache-2.0; the 47 film profiles and editor glyphs
remain CC BY-SA 4.0, (c) MUAStudio Inc., redistributed unmodified.

**Still images only.** The engine's movie layer is not wired on Windows, so video import, playback
and movie export are absent. Plug-in installation, update checks and community film packs are also
off: those host services are not implemented for this platform.

The repository carries no upstream code: `port/` holds the port layer and `scripts/sync-upstream.ps1`
replays it onto an upstream tag.
