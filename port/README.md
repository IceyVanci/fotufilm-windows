# The port layer

这个目录只放"相对上游额外加的那一层"，不含任何上游代码。

| 目录 | 内容 | 同步时怎么用 |
|---|---|---|
| `overlay/` | 移植自己写或自己改定的文件，按仓库内相对路径摆放（`flutter/…`、`Sources/…`、`tools/…`） | 直接覆盖到工作树 |
| `patches/` | 相对上游 tag 的 unified diff，一个文件一个补丁 | `git apply` |
| `i18n/` | 汉化词表与重写器 | 在覆盖与打补丁之后跑一次 |

## 重放顺序

```
vendor/upstream  (clone 上游 tag)
      │  复制成 work/<版本>/
      ▼
1. 铺 overlay/          新文件与原样保留的文件
2. git apply patches/*  对上游文件的改动
3. node i18n/apply-zh.cjs --root work/<版本> --apply
4. node i18n/check-zh.cjs --root work/<版本>
      ▼
work/<版本>/  →  scripts/build.ps1
```

## 三条规矩

**① overlay 优先。** `i18n/overlay.txt` 列出 overlay 里那些已经写着中文的文件；重写器会跳过它们，
所以重放不会把成品改回去。

**② 上游动过谁，就把谁从 overlay 挪出来。** 跟随新版本时，如果上游也改了这个文件，
直接覆盖会丢掉上游的改动。做法是：删掉 `overlay/` 里的那份，让 `patches/` 和 `apply-zh`
在下一次重放里重新生成它。1.15 同步时，13 个这样的文件全部按这条处理。

**③ 键不翻译。** `c.sliders()` 的分组名、`profileControls()` 的字段表、`grade$band$axis`
里的色带名与轴名、`palette.systemColors` 的颜色令牌、`module['…']` 的键——这些是引擎读回去的标识。
重写器按调用位置保护它们，`check-zh.cjs` 断言这一点，任何一条被翻成中文都会让构建前的检查失败。
