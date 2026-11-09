# Changes from upstream

本文件是 Apache License 2.0 第 4(b) 条要求的变更声明：说明本次移植相对上游
[DhaliwalX/fotufilm-engine](https://github.com/DhaliwalX/fotufilm-engine) 修改了哪些文件、为什么。

> 上游代码版权归 MUAStudio Inc.。本移植与 MUAStudio Inc. 无隶属、授权或赞助关系。

## 基线

| 项 | 值 |
|---|---|
| 上游 | `DhaliwalX/fotufilm-engine` tag **v1.15**，commit `bcc776d9`（用 tag 标定：上游 `version.env` 在 v1.15 里仍是 `MARKETING_VERSION=1.14`，未随发布更新） |
| 移植版本 | `1.15.0-w1` |
| 工具链 | Swift 6.2（Windows）、Flutter 3.41.7、MSVC 14.50、Windows SDK 10.0.26100 |

## 规模

相对 v1.15：**修改 116 个文件、新增 28 个文件**（另有 `.dart_tool`、`.idea`、`flutter/assets/generated` 等构建期产物，不计入）。

本仓库不复制上游代码：改动以 `port/overlay/`（新增与原样保留的文件）与 `port/patches/`（补丁）两种形式保存。

## 一、引擎与平台层（14 个文件）

| 文件 | 改动 |
|---|---|
| `Sources/FotufilmCore/MappedBuffer.swift` | POSIX `mmap`/`pwrite`/`msync` 换成 `CreateFileMappingW`/`MapViewOfFile`/`WriteFile`/`FlushViewOfFile` |
| `Sources/CFotufilmCodecs/Thumbnail.cpp` | 局部变量 `small` 改名（与 `<rpcndr.h>` 的宏冲突） |
| `Sources/FotufilmHalide/FotufilmHalideLinux.cpp` | Windows 兼容层：`LoadLibraryA`/`GetProcAddress`、`vulkan-1.dll`、`_putenv_s`、`NOMINMAX`；新增 `fotufilm_halide_shutdown()` |
| `Sources/FotufilmHalide/FotufilmHalide.cpp`、`FotufilmFilmTileBuild.cpp`、`FotufilmNegativeScan.cpp`、`FotufilmTransport.cpp` | 整体包进 `#if !defined(FOTUFILM_HALIDE_LINUX_AOT)`，避免与 AOT 核重复定义 |
| `Sources/FotufilmHalide/Pipeline/Gpu.h` | 新增 `windows_aot_target(DeviceAPI)`：Windows + X86/64 + AVX2 + Vulkan |
| `Sources/FotufilmHalide/include/FotufilmHalide.h` | 导出 `fotufilm_halide_shutdown` |
| `Sources/FotufilmHost/HostPlatform.swift`、`HostPlatform+Windows.swift`（新增） | 平台分派；Windows 走 `HalideGPUDeveloper`，只接线静态图片相关的宿主服务 |
| `Sources/FotufilmHost/HostDeveloper+HalideGPU.swift`、`CInterface.swift` | GPU 路径接线、引擎销毁时释放设备 |
| `Sources/CFotufilmCodecs/Utf8Paths.h`（新增）与 11 个编解码 TU | 让 CRT 的窄字符文件 API 按 UTF-8 解析路径。Windows 用 ANSI 代码页（简体中文是 GBK）读窄文件名，而引擎收到的是 Dart 传来的 UTF-8，中文路径的图片因此打不开；模块加载时把字符区域设为 UTF-8 即可，见第六节 |
| `Package.swift` | vcpkg（`x64-windows-static-md`）与 Halide 探测、AOT 核自动发现、`_USE_MATH_DEFINES` |
| `tools/generate_halide_ios.cpp` | 增加 `--windows-vulkan` 平台，生成 Windows AOT 核 |

## 二、构建与打包工具（新增）

| 文件 | 用途 |
|---|---|
| `tools/generate-halide-aot-windows.ps1` | 生成 46 个 Halide AOT 变体 |
| `flutter/tool/prepare.ps1` | 从 `web/src` 与字体源生成 `flutter/assets/generated/`（**构建期产物，不入库**） |
| `packaging/launcher.cpp` 等 | 单文件启动器与压缩打包器（Windows Cabinet LZMS/XPRESS） |
| `scripts/sync-upstream.ps1`、`scripts/build.ps1` | 重放与构建 |

## 三、Windows 编辑器（新增 18 个文件）

`flutter/windows/` 整棵目录由 `flutter create --platforms=windows` 生成后修改：

- `runner/main.cpp`：窗口标题「Fotufilm 胶片暗房」、默认尺寸 1560×980
- `runner/Runner.rc`：ProductName 与 FileDescription 为「Fotufilm for Windows (unofficial)」，版本串由构建脚本写入
- 其余为 Flutter 模板文件，逻辑未改

## 四、简体中文本地化（84 个文件）

`flutter/lib/` 下 84 个文件被改写，分两类：

**1. 文案替换** —— 界面字面量换成中文，由 `port/i18n/apply-zh.cjs` 按词表重放。重写器只动展示位置，
引擎会读回去当键的字面量（`c.sliders()` 的分组名、`profileControls()` 的字段表、`grade$band$axis`
的色带／轴名、字形颜色令牌）一律不碰；`port/i18n/check-zh.cjs` 在每次构建前断言这一点。

**2. 代码钩子**（非纯文案）：

- `model/catalogue.dart`：`Catalogue.load()` 后统一本地化控件目录的 `title`/`label`/`name`/`detail`/`hint`；
  `profileControl()` 对胶片自带的菜单再做一次（`unit`、`field`、`id` 等机器标识不动）
- `model/editor.dart`：检查器四个页签的标题
- `ui/inspector/grade_deck.dart`：色带名与轴名保持英文（它们是 `grade$band$axis` 参数键的一部分），只在显示处翻译
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

- `flutter/pubspec.yaml`：版本号改为 `1.15.0+1`
- `flutter/.metadata`：Windows 平台登记
- `flutter/lib/engine/fotufilm_ffi.dart`：Windows 下的 DLL 文件名（`libfotufilm.dll`）

## 六、相对 1.14.0-w1 的变化

- 跟随上游 v1.15：色调曲线置于 Darkroom 标题之上、手机布局、影片格式与颗粒字形、
  阴影细节改用两端缓入缓出的曲线（`Print.h` 与 `PrintDetail.swift` 同步改动，46 个 AOT 核全部重生成）。
- 汉化从"逐文件手改"改为"按展示位置重放"，`t()` 手工钩子取消，改由重写器在改写时就地保护键位置。
- 修正 `ui/inspector/grade_deck.dart`：色带名与轴名上一版被误译成中文，导致 `grade$band$axis`
  参数键失配、调色盘写入无效。现恢复英文键，只在显示处翻译。
- 未接入的宿主服务（视频、插件、更新、社区胶片包）维持上游 `HostPlatform+Windows.swift` 的既有状态。

## 七、1.15.0-w2

- 修复：路径含中文的图片无法打开。`ffc_decode` 及其下层（fopen、LibRaw、libtiff、libheif、OpenEXR）在
  Windows 上用 ANSI 代码页解析窄文件名，而引擎从 Dart 拿到的是 UTF-8，于是中文目录下的照片被报成
  "Could not open"。`Utf8Paths.h` 在编解码模块加载时把 `LC_CTYPE` 设为 UTF-8；只改字符区域，
  数值区域（小数点在 printf 里的写法）保持 C 运行时的原样。
- 实测：同一个 JPEG，ASCII 路径两版都能打开；中文路径在 w1 报错、w2 打开并给出 6000×4000。

## 许可

- 本移植新增/修改的代码：**Apache-2.0**
- 上游代码：**Apache-2.0**，版权归 MUAStudio Inc.
- 47 个胶片配置与编辑器字形：**CC BY-SA 4.0**，版权归 MUAStudio Inc.，**原样分发，未修改**；署名 Fotufilm（https://fotufilm.com）

完整条款见 `LICENSE`、`NOTICE`、`LICENSING.md`、`THIRD_PARTY_NOTICES.md` 与 `licenses/`。

## 八、1.15.0-w3

打开 RAW 的三处改动，全部在移植层，不动上游的解码参数语义：

- **LibRaw 用 OpenMP 重编**。vcpkg 的 libraw 端口默认关掉 OpenMP（`"default-features": false`），
  原来的静态库一个线程跑去马赛克。改为 `libraw[openmp]:x64-windows-static-md` 后引擎链接 MSVC 的
  OpenMP 运行时，发行包随附 `vcomp140.dll`（208 KB，取自工具链的 VC++ 可再发行目录）。
- **RAW 先解工作副本**。`PortableImageDecoder` 原本只在 Android 上走 `working()`，现在 Windows 同样：
  先按长边 2560 解一份，全尺寸解码留给导出与放大（`decodeLarger`）。`FOTOFILM_RAW_WORKING_EDGE`
  可覆盖这个边长，`0` 表示按原尺寸解码。
- **放宽半尺寸阈值**。`half_size` 原来要求请求边长不超过原生的 1/4，现在 1/2 —— 2560 的预览请求
  在 6024 px 的机器上因此能用四分之一像素的去马赛克，再由既有的缩小步骤降到请求尺寸。

同一张 24 MP ARW（DSC04506.ARW），Ryzen 7 7700，8 核 16 线程，三次取热态最好值：

| 版本 | 全尺寸导入 | 默认导入（工作副本） |
|---|---|---|
| 1.15.0-w2 | 3734 ms | 3734 ms |
| 1.15.0-w3 | **953 ms** | **446 ms** |

JPEG 同场景作对照：约 883–1094 ms，未变。
