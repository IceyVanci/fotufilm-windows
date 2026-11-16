# 跟随上游

这个移植不 fork 上游，也不向上游提 PR。跟随的方式是**在新版本上重放移植层**。

```
scripts\sync-upstream.ps1 -Tag v1.15
  ├ vendor/upstream        克隆并检出该 tag（只读）
  ├ work/1.15              干净副本
  ├ 铺 port/overlay        移植自己写的文件
  ├ git apply port/patches 对上游文件的改动
  ├ node port/i18n/apply-zh.cjs --root work/1.15 --apply
  ├ node port/i18n/check-zh.cjs --root work/1.15
  └ 更新 upstream.lock
scripts\build.ps1 -Source work\1.15 -Version 1.15
```

## 一次同步要多久

按 1.15、1.16 与 1.17 三次的实测：

- **1.15**：上游 6 个提交、32 改 56 增，移植层第一次落地。
- **1.16**：上游 7 个提交、65 个文件、+4962 / −2053。9 个新文件全是手机画廊，与 Windows 无关；**`Sources/FotofilmHalide/`、控件目录、`Package.swift`、AOT 生成器全部零改动**，所以 AOT 核与桥接槽位都不用重生成。12 个冲突文件里 11 个的差异只是中文换英文，按规矩② 移出 overlay 即可，真正要人脑合并的只有 `host_window.dart`。
- **1.17**：上游 11 个提交、271 个文件、+35555 / −17895，是 1.16 的六倍多。三项连锁成本：① 引擎配置布局新增 19 个槽（含 `SCAN_BALANCE` 3×65），**全部 AOT 核作废**；② `aot-variants.json` 的变体表 46 → 52；③ 上游升到 Flutter 3.50 / Dart 3.14，`ListView.cacheExtent` 换成 `scrollCacheExtent`、Material 拆成 `package:material_ui`，**不升 SDK 就得把这些 API 改回去**。好消息是新增的 13 个 `Sources/` 文件全部不含 Apple-only 依赖，`Package.swift` 依然零改动。18 个 overlay 与 13 个补丁目标被上游改到，全部靠三方合并吸收。

每次都要额外付的：重放只产出**源码树**，不产出构建前置物。构建前必须先 `flutter pub get`，再跑 `flutter/tool/prepare.ps1`（生成 215 个字形与 `controls.json`），这两步要在**提权**会话里做，因为插件要建符号链接。1.17 起 SDK 与 pub 都走中国镜像（`FLUTTER_STORAGE_BASE_URL` / `PUB_HOSTED_URL`），`pub get` 不必再 `--offline`。

AOT 生成不要在 harness 的前台/后台任务里跑：任务会随会话重启被杀。用 `tools\aot-117-resume.ps1`，它以 `.lib` 是否存在决定跳过，杀掉也能续跑。


| 上游变更 | 需要做的 | 实测 |
|---|---|---|
| 文档、网页 | 重放一遍即可 | 10 分钟 |
| 界面文案 | 重放，扫描器列出没有的词条再补 | 30 分钟 |
| 新增控件 / 目录 | 补词条，可能补图标 | 1–2 小时 |
| 改 Halide 阶段（`Sources/FotufilmHalide/Stages/*.h`） | 重新生成全部 AOT 核 | 机器时间 30–60 分钟（52 变体、10 路并行） |
| 改引擎 C ABI | 改 Host 与 FFI | 半天起 |

## 最容易出事的三处

**① 键被翻译。** `c.sliders()` 的分组名、`grade$band$axis` 的色带与轴名、`palette.systemColors`
的颜色令牌都是引擎读回去的标识。1.14.0-w1 里 `grade_deck.dart` 的色带名被翻成中文，
参数键变成 `grade阴影暖度`，调色盘写入全部落空且不报错。现在 `port/i18n/check-zh.cjs`
在每次构建前断言这一点。

**② AOT 核没跟着重生成。** Halide 阶段的头文件变了、或 `config-layout.json` 动过，全部变体作废（1.17 是 52 个）；不重生成的话
Swift 用新常量、核里跑旧曲线，预览与导出不一致。`scripts/build.ps1` 会比较阶段头与
AOT 核的时间戳，旧了直接报错退出。

**③ 补丁漂移。** 上游改了我们也在改的文件时，`git apply` 会拒绝。这是必须付的成本，
但范围被压在 `port/patches` 里，看得见、改得动。处理办法见 [port/README.md](../port/README.md)。

## 版本号

上游的 `version.env` **不随发布更新**——v1.15 里它仍写着 `MARKETING_VERSION=1.14`。
所以版本一律从 tag 取，`upstream.lock` 记录当前携带的 tag 与 commit。
移植版本写作 `1.15.0-w1`：上游发布号 + `.0-w` + 移植修订号。
