# Changes from upstream

本文件是 Apache License 2.0 第 4(b) 条要求的变更声明：说明本次移植相对上游
[DhaliwalX/fotufilm-engine](https://github.com/DhaliwalX/fotufilm-engine) 修改了哪些文件、为什么。

> 上游代码版权归 MUAStudio Inc.。本移植与 MUAStudio Inc. 无隶属、授权或赞助关系。

## 基线

| 项 | 值 |
|---|---|
| 上游 | `DhaliwalX/fotufilm-engine`，`version.env` 记录 `MARKETING_VERSION=1.14`、`CURRENT_PROJECT_VERSION=1024` |
| 移植版本 | `1.14.0-w1` |
| 工具链 | Swift 6.2（Windows）、Flutter 3.41.7、MSVC 14.50、Windows SDK 10.0.26100 |

## 规模

相对上游快照：**修改 100 个文件、新增 248 个文件**（新增里 210 个是构建期生成的资源）。

## 一、引擎与平台层（14 个文件）

| 文件 | 改动 |
|---|---|
| `Sources/FotufilmCore/MappedBuffer.swift` | POSIX `mmap`/`pwrite`/`msync` 换成 `CreateFileMappingW`/`MapViewOfFile`/`WriteFile`/`FlushViewOfFile` |
| `Sources/CFotufilmCodecs/Thumbnail.cpp` | 局部变量 `small` 改名（与 `<rpcndr.h>` 的宏冲突） |
| `Sources/FotufilmHalide/FotufilmHalideLinux.cpp` | Windows 兼容层：`LoadLibraryA`/`GetProcAddress`、`vulkan-1.dll`、`_putenv_s`、`NOMINMAX`；新增 `fotufilm_halide_shutdown()` |
| `Sources/FotufilmHalide/FotufilmHalide.cpp` 等 4 个 TU | 整体包进 `#if !defined(FOTUFILM_HALIDE_LINUX_AOT)`，避免与 AOT 核重复定义 |
| `Sources/FotufilmHalide/Pipeline/Gpu.h` | 新增 `windows_aot_target(DeviceAPI)`：Windows + X86/64 + AVX2 + Vulkan |
| `Sources/FotufilmHalide/include/FotufilmHalide.h` | 导出 `fotufilm_halide_shutdown` |
| `Sources/FotufilmHost/HostPlatform.swift`、`HostPlatform+Windows.swift`（新增） | 平台分派；Windows 走 `HalideGPUDeveloper` |
| `Sources/FotufilmHost/HostDeveloper+HalideGPU.swift`、`CInterface.swift` | GPU 路径接线、引擎销毁时释放设备 |
| `Package.swift` | vcpkg（`x64-windows-static-md`）与 Halide 探测、AOT 核自动发现、`_USE_MATH_DEFINES` |
| `tools/generate_halide_ios.cpp` | 增加 `--windows-vulkan` 平台，生成 Windows AOT 核 |

## 二、构建与打包工具（新增）

| 文件 | 用途 |
|---|---|
| `tools/generate-halide-aot-windows.ps1` | 生成 46 个 Halide AOT 变体 |
| `flutter/tool/prepare.ps1` | 从 `web/src` 与字体源生成 `flutter/assets/generated/`（210 个文件，**构建期产物，不入库**） |

## 三、Windows 编辑器（新增 18 个文件）

`flutter/windows/` 整棵目录由 `flutter create --platforms=windows` 生成后修改：

- `runner/main.cpp`：窗口标题「Fotufilm 胶片暗房」、默认尺寸 1560×980
- `runner/Runner.rc`：ProductName 与 FileDescription 为「Fotufilm for Windows (unofficial)」，版本串由构建脚本写入
- 其余为 Flutter 模板文件，逻辑未改

## 四、简体中文本地化（84 个文件）

`flutter/lib/` 下 84 个文件被改写，分两类：

**1. 文案替换** —— 界面字面量换成中文，由 `tools/apply-zh.cjs` 按 `zh-ui.json` 与词表批量改写。

**2. 代码钩子**（6 处，非纯文案）：

- `model/catalogue.dart`：`Catalogue.load()` 后统一本地化控件目录的 `title`/`label`/`name`/`detail`/`hint`；
  `profileControl()` 对胶片自带的菜单再做一次（`unit`、`field`、`id` 等机器标识不动）
- `model/editor.dart`：检查器四个页签的标题
- `ui/inspector/grade_deck.dart`：色带名与轴名保持英文（它们是引擎参数键的一部分），只在显示处翻译
- `model/edit_history.dart`：`historyTitle()` 出口统一翻译
- `model/pipeline.dart`：`stageName()` 出口统一翻译
- `app/host_window.dart`：Windows 宿主能力分派

新增文件：

| 文件 | 用途 |
|---|---|
| `flutter/lib/i18n/zh.dart` | 中英对照词表（约 730 条）与 `t()` |
| `flutter/lib/app/host_windows.dart` | 用 `ShellExecuteW` / `SHFileOperationW` 实现打开链接、打开文件、在资源管理器中显示、移到回收站（上游走 macOS 原生通道） |
| `flutter/lib/app/build_info.dart` | 版本与构建日期，构建时写入 |
| `flutter/lib/ui/workspace/about_dialog.dart` | 关于对话框：移植版本、上游版本、构建日期、许可 |
| `flutter/test/catalogue_test.dart` | 控件目录回归测试 |

## 五、其它

- `flutter/pubspec.yaml`：版本号改为 `1.14.0+1`
- `flutter/.metadata`：Windows 平台登记
- `flutter/lib/engine/fotufilm_ffi.dart`：Windows 下的 DLL 文件名（`libfotufilm.dll`）

## 许可

- 本移植新增/修改的代码：**Apache-2.0**
- 上游代码：**Apache-2.0**，版权归 MUAStudio Inc.
- 47 个胶片配置与编辑器字形：**CC BY-SA 4.0**，版权归 MUAStudio Inc.，**原样分发，未修改**；署名 Fotufilm（https://fotufilm.com）

完整条款见 `LICENSE`、`NOTICE`、`LICENSING.md`、`THIRD_PARTY_NOTICES.md` 与 `licenses/`。
