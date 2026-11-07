# Fotufilm for Windows (unofficial)

Fotufilm（https://fotufilm.com）的非官方 Windows 移植，附带简体中文界面。

> **Not affiliated with, endorsed by, or sponsored by MUAStudio Inc.**
> 与 MUAStudio Inc. 无隶属、授权或赞助关系。

上游项目：[DhaliwalX/fotufilm-engine](https://github.com/DhaliwalX/fotufilm-engine)

## 状态

开发中，尚未发布。首个版本目标：跟随上游 **1.14**，移植版本号 `1.14.0-w1`。

## 这个移植做了什么

| 类别 | 内容 |
|---|---|
| 构建 | Swift 6.2 Windows 工具链 + MSVC，Halide 走 AOT Vulkan 核（无 JIT） |
| 平台层 | Win32 内存映射替换 POSIX mmap、Windows 宿主能力（浏览器/资源管理器/回收站） |
| 界面 | Flutter Windows runner，简体中文界面 |
| 发行 | 单文件便携版 + 安装版 |

详细清单见 `NOTICE-PORT.md`（Apache-2.0 第 4(b) 条要求的变更声明）。

## 系统要求

- Windows 10 1903+ / Windows 11，x64
- 支持 AVX2 的 CPU
- 支持 Vulkan 的显卡（引擎的 GPU 路径只有 Vulkan）

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

