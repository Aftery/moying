# 墨影（moying）· 全量 Dart 代码审查报告

**审查日期**：2026-09-20
**审查范围**：`lib/` 全部 Dart 源码（排除 `*.g.dart` / `generated/`，实际项目中这两类**均不存在**，故为全量）
**代码规模**：94 个文件 / 23,412 行

| 分层 | 行数 | 文件数 |
|---|---|---|
| `screens/` | 10,651 | 25 |
| `services/` | 4,302 | 25 |
| `widgets/` | 3,233 | 20 |
| `providers/` | 1,733 | 3 |
| `models/` | 1,543 | 9 |
| `data/` | 1,348 | 7 |
| `config/` | 382 | 4 |
| `main.dart` | 220 | 1 |

**基线校验**：`flutter analyze` → `No issues found!`（7.3s，flutter_lints 4.0 + `unawaited_futures` + `prefer_const_constructors` 族全开）

> **重要前提**：项目已开启 `prefer_const_constructors` / `prefer_const_constructors_in_immutables` / `prefer_const_literals_to_create_immutables` / `unawaited_futures` 四条 lint，且 analyze 为 0 issue。因此**第 4 维度的「const 缺失」与「未 await 的 Future」在本项目中已被工具链强制保证**，本报告不再重复罗列，只在工具覆盖不到的地方给结论。

---

> **修复记录（2026-09-20 补）**：第八节建议的 1–4 项已修复，提交 `c8d6289`；1–3 项有新增回归测试，
> 且逐条在旧实现上验证过判别力（并发用例在旧实现下 40 条日志只剩 1 行）。全量 414/414、analyze 0 issue。
> **其中 M-1 的原始修改建议被证伪**（详见该节）——按原建议实现会抛 `used after being disposed`。
>
> **修复记录（第二批）**：M-9（AppLogger 继承 ChangeNotifier + problem/warning 增量计数 + entries
> 返回 UnmodifiableListView + 日志页 ListenableBuilder 订阅）、L-1（debugPrint 按 kDebugMode 收口）、
> L-3（platform 映射可读名）、L-6（FlutterError.onError 委托 presentError）已修复。
> 新增 6 条回归测试（逐出递减计数 / 清空归零 / 记录与清空触发通知 / 历史载入重算 / 只读视图），
> 全量 420/420、analyze 0 issue。L-2（空 catch 注释）经复核为有意容错、注释已说明，不改；
> L-5（mock_data 进包）留待架构专项。

---

## 一、结论总览

| 严重等级 | 数量 | 说明 |
|---|---|---|
| **Critical** | **0** | 未发现导致崩溃/数据丢失/安全风险的问题 |
| **High** | 2 | 架构规范系统性偏离；日志落盘并发写竞态 |
| **Medium** | 9 | 控制器未释放、色板重复、超长函数/文件、列表未 lazy、魔法数字 |
| **Low** | 8 | 注释失准、空 catch、性能微损、包体与 seed 数据 |

**总体评价**：这是一个**工程质量显著高于平均水平**的 Flutter 项目。资源生命周期管理近乎完备（详见第六节「已核实无问题项」），异常处理有明确的设计意图且写进了注释，缓存与重试链路有可注入时钟/依赖以便测试。本报告的问题集中在**架构分层命名**与**表现层代码组织**，以及少数几处细节疏漏——**没有发现任何会伤害终端用户的问题**。

---

## 二、Critical（0 条）

无。

明确排除的误报（已逐条实证，避免后续重复排查）：

| 疑似问题 | 位置 | 实测结论 |
|---|---|---|
| `switch` 分支无 `break`，会 fallthrough 导致「选封面后又被移除」 | `book_edit_screen.dart:1617-1630`、`movie_edit_screen.dart:749-762` | **非缺陷**。Dart 3.0 起 `break` 可省略且**语言层面不存在 fallthrough**。已用等价代码在本地 Dart SDK 实测：4 个分支各只执行自身。 |
| `await` 后直接 `setState`，无 `mounted` 守卫（共 13 处疑似） | 多处 | **非缺陷**。逐处读代码确认，守卫均存在（如 `book_edit_screen.dart:408` `if (picked == null \|\| !mounted) return;`）。初筛脚本的正则未覆盖 `a \|\| !mounted` 形式导致误报。 |
| `notifyListeners()` 在 dispose 后调用 | `providers/*.dart` | **非缺陷**。全仓 0 处直接调用 `notifyListeners()`，统一走 `_notifyIfAlive()` 守卫（3 个 Provider 一致）。 |

---

## 三、High

### H-1 · 架构未遵循 `flutter-architecture` 四层组件化 + Page/View 命名规范

**维度**：规范 / 架构
**位置**：`lib/` 顶层结构、`lib/screens/`（25 文件）、`lib/widgets/`（20 文件）、9 个 `*_widgets.dart`

**现状与规范的差距**：

| 规范要求 | 项目现状 | 符合 |
|---|---|---|
| `app → business → component → foundation` 四层单向依赖 | `config / data / models / providers / screens / services / widgets` 平铺 7 目录 | ✗ |
| 业务模块内 `page/ view/ view_model/ model/ repository/` | 无 `view_model/`、无 `repository/`；`screens/` 扁平 25 文件 | ✗ |
| page 文件 `xxx_page.dart` → 类 `XxxPage` | **14 个** `*_screen.dart` → `XxxScreen`（`XxxPage` 0 个） | ✗ |
| **严禁使用 `widget` 关键字** | **9 个** `*_widgets.dart`（part 文件）+ 顶层 `lib/widgets/` 目录 + 60+ 个 `*Widget` 类 | ✗ |
| 同级业务不互相 import | `screens/` 内直接 import 兄弟页面（如 `profile_screen` → `data_source_screen`） | ✗ |

**影响**：不是运行时缺陷，而是**长期可维护性成本**：
- 层级无约束 → 依赖方向可以任意生长（当前 `screens/` 直接 import `services/`、`providers/`、`data/`、`models/`、`widgets/` 五层，缺少防腐边界）；
- 命名偏离 → 新人按规范找不到 `page`，也分不清 `screens/xxx_screen.dart` 与 `screens/xxx_widgets.dart` 的职责差别；
- 无 `view_model/` → ViewModel 职责被 `providers/` 承担，而 Provider 同时还在做 Repository 的事（见 H-1 附注）。

**修改建议**（渐进式，不建议一次性重构）：

阶段一（低风险，仅新增不改名）——建立目标骨架，新代码按规范落位：

```
lib/
├── app/
│   ├── config/            # 从 lib/config/ 迁入
│   └── pages/
├── business/
│   ├── library/           # 书影库
│   │   ├── page/          # books_page.dart / movies_page.dart
│   │   ├── view/
│   │   ├── view_model/
│   │   ├── model/
│   │   └── repository/
│   ├── data_source/
│   ├── stats/
│   └── sync/
├── component/             # 通用能力：media_cover / chart / form
└── foundation/            # 底层：network / storage / logger
    ├── network/
    ├── storage/
    └── logger/
```

阶段二（改名，一次一个模块）——`XxxScreen` → `XxxPage`，`*_screen.dart` → `*_page.dart`：

```bash
# 逐模块执行，每步跑一次 analyze + test
git mv lib/screens/books_screen.dart lib/business/library/page/books_page.dart
# 随后全局改名类与引用
```

阶段三（消除 `widget` 关键字）——`*_widgets.dart` 的 part 文件按职责拆到模块 `view/`：

```dart
// 现状：lib/screens/movie_detail_widgets.dart
part of 'movie_detail_screen.dart';
class _InfoChip extends StatelessWidget { ... }

// 目标：lib/business/library/view/movie_detail/movie_info_chip.dart
class MovieInfoChip extends StatelessWidget { ... }  // 提升为公开类，私有前缀去掉
```

> **关于 `part` 的取舍**：当前用 `part`/`part of` 切分（上一轮重构引入）是**在「不改公开 API」约束下最保守的做法**，flutter_lints 不报错。但它与四层组件化的目标结构是**冲突**的——`part` 把文件绑成同一个库，无法跨模块复用。建议在阶段三把它替换为公开类 + 正常 import。若短期内不做全量重构，至少应停止新增 `part` 文件。

**H-1 附注 · Provider 承担了 ViewModel + Repository + Store 三重职责**

| 文件 | 行数 | 混入的职责 |
|---|---|---|
| `providers/library_provider.dart` | 626 | 直接 `import 'package:http/http.dart'`（网络）、`import 'package:path/path.dart'`（路径拼接）、持有 `LibraryStore`（持久化）、`ImagePickService`（平台能力） |
| `providers/data_source_provider.dart` | 723 | 缓存策略（TTL/LRU）、请求节流、结果合并、异常语义归一 |
| `providers/sync_provider.dart` | 384 | WebDAV 客户端构造、`Connectivity` 探测、导出落盘 |

按 MVVM 规范，网络与持久化应下沉到 `repository/`，Provider 只暴露状态与意图方法：

```dart
// 现状（library_provider.dart）：Provider 内直接发请求 + 拼路径 + 写盘
Future<void> _fetchAndCacheCover(String url) async {
  final res = await http.get(Uri.parse(url));          // 网络
  final path = p.join(dir.path, 'images', name);       // 路径
  await File(path).writeAsBytes(res.bodyBytes);        // 文件
  _notifyIfAlive();
}

// 目标：Provider 只调 Repository，不碰 http / File
class LibraryViewModel extends ChangeNotifier {
  LibraryViewModel(this._repo);
  final LibraryRepository _repo;

  Future<void> refreshCover(String url) async {
    await _repo.cacheImage(url);      // 网络+落盘都在 repository 内
    _notifyIfAlive();
  }
}
```

---

### H-2 · 日志落盘（`FileLogSink.append`）存在并发写竞态，会丢日志

**维度**：潜在 bug（并发）/ 数据完整性
**位置**：`lib/services/log_sink_io.dart:49-62`，触发点在 `lib/services/app_logger.dart:276`

**问题**：`append()` 内部有「检查大小 → 读全文 → 截断重写 → 追加」四步，**全程无串行保护**；而调用方是 `unawaited(_persist(entry))`，即**每条日志都并发触发一次**。

```dart
// app_logger.dart:276
unawaited(_persist(entry));        // 无 await、无队列 → 多个 append 同时在飞

// log_sink_io.dart:49-62
Future<void> append(String line) async {
  final f = _file;
  if (f == null) return;
  try {
    if (await f.exists() && await f.length() > maxBytes) {
      final content = await f.readAsString();               // ← 读
      await f.writeAsString(content.substring(content.length ~/ 3));  // ← 非 append，截断全量重写
    }
    await f.writeAsString('$line\n', mode: FileMode.append, flush: false);
  } on Object catch (_) { }
}
```

**竞态后果**（按严重度递增）：

1. **丢行**：A 读到 2MB 全文，B 同时 `FileMode.append` 写入；A 随后 `writeAsString` 截断重写 → B 那行被覆盖删除。
2. **触发滚动时丢一批**：两个 append 同时判定超限，各自读全文、各自截断重写，后写者覆盖先写者，中间所有行丢失。
3. **`content.substring(content.length ~/ 3)` 按 UTF-16 码元切分**，若切点落在代理对（emoji / 生僻字）中间，会产生孤立代理项，写回时编码为 `U+FFFD` 替换字符，日志尾部出现 `�`。

**影响边界**：**仅影响诊断日志的完整性，不涉及任何业务数据**。且只有在「日志文件已达 2MB 且高频写日志」时才触发。故定为 High 而非 Critical——但用户导出日志报障时，恰恰需要的是完整日志。

**修改建议**：给 sink 加写链（项目在 `library_store.dart:293` 已有同款成熟模式，直接照搬），并把截断点对齐到换行边界：

```dart
class FileLogSink implements LogSink {
  /// 写链：新请求排在上一次之后，天然串行不交错
  /// （与 LibraryStore._writeChain 同一模式）
  Future<void> _tail = Future.value();

  Future<void> append(String line) {
    final next = _tail.then((_) => _appendNow(line));
    _tail = next.then((_) {}, onError: (_) {});   // 吞异常，避免断链
    return next;
  }

  Future<void> _appendNow(String line) async {
    final f = _file;
    if (f == null) return;
    try {
      if (await f.exists() && await f.length() > maxBytes) {
        final content = await f.readAsString();
        // 按换行边界截断，避免切断 UTF-16 代理对 / 半行
        final cut = _alignToLineStart(content, content.length ~/ 3);
        await f.writeAsString(content.substring(cut), flush: true);
      }
      await f.writeAsString('$line\n', mode: FileMode.append, flush: false);
    } on Object catch (_) {
      // 落盘失败不影响主流程
    }
  }

  /// 把截断点右移到下一个换行之后；找不到则退回原文（宁可不清）
  static int _alignToLineStart(String s, int at) {
    final nl = s.indexOf('\n', at);
    return nl == -1 ? 0 : nl + 1;
  }
}
```

> 说明：`_tail` 保证串行后，「丢行」与「丢一批」两个竞态即消除。代理对问题由 `_alignToLineStart` 消除（在合法字符 `\n` 之后切分）。若还想更稳，可把滚动改成「重命名为 `.1` 备份 + 新建文件」，但会多占一份磁盘，对日志场景不划算。

---

## 四、Medium

### M-1 · `_promptTextDialog` 创建的 `TextEditingController` 从不释放

**维度**：内存泄漏
**位置**：`lib/screens/book_edit_screen.dart:1203`
**调用点**：`:1264`（出版社）、`:1275`（年份）、`:1294`（ISBN）、`:1697`（封面 URL）

```dart
Future<String?> _promptTextDialog({...}) {
  var value = initial;
  final ctrl = TextEditingController(text: initial)      // ← 每次调用 new 一个
    ..selection = TextSelection.collapsed(offset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: TextField(controller: ctrl, ...),
      // ...
    ),
  );
  // ← 返回处无 dispose，也没有 .then((_) => ctrl.dispose())
}
```

**影响评估（如实说明，不夸大）**：`TextEditingController` 是纯 Dart 的 `ChangeNotifier`，**不持有原生资源**；对话框销毁时 `EditableTextState.dispose()` 会摘掉自己注册的监听，controller 随后失去可达引用、可被 GC 回收。所以**这不是无限增长的泄漏**。它违反的是 Flutter 的 `dispose` 契约：在启用 leak tracking（`flutter test --dart-define=...` 或 DevTools Memory）时会被标记，且一旦未来该 controller 被挂上 `addListener` 到长生命周期对象，就会真的泄漏。定为 Medium 是因为它是**当前唯一一处明确的 dispose 契约违反**，修复成本极低。

**修改建议（⚠️ 本节原建议已被实测证伪，以下是修正后的方案）**：

原建议是「用 `await` 包一层，在 future 落地后释放（try/finally）」。**这条建议是错的**：
`showDialog` 的 future 在路由 pop 那一刻就完成了，而对话框此时仍处于**退场动画**中，
`TextField` 会重建并重新 `addListener`，于是 dispose 之后立刻抛
`A TextEditingController was used after being disposed.`
（按该建议实现后被 `test/media_pipeline_test.dart` 的「URL 封面」用例当场测出。）

正确做法是**把 controller 的所有权交给对话框自身**，让释放时机落在子树真正 unmount 之后：

```dart
// lib/widgets/edit_form_widgets.dart
class _TextPromptDialogState extends State<TextPromptDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial)
      ..selection = TextSelection.collapsed(offset: widget.initial.length);
  }

  @override
  void dispose() {
    _ctrl.dispose(); // 交互结束后 route 子树 unmount 时才走这里，安全
    super.dispose();
  }
  // build 返回 AlertDialog(content: TextField(controller: _ctrl, ...))
}
```

调用侧（`_promptTextDialog`）退化为 `showDialog(builder: (_) => TextPromptDialog(...))` 的薄封装（70 行 → 23 行）。

> **另更正一处事实**：本报告原文称 `movie_edit_screen.dart:773` 的 `_promptPosterUrl` 也建了 controller、需同样补 dispose
> —— 实际它用局部 `var url` + `onChanged` 承接输入，**根本没有 controller**。已 grep 全仓确认：对话框内建 controller 仅 `_promptTextDialog` 一处。

---

### M-2 · 图表色板在多处重复定义，且与 `AppPalette` 数值重叠

**维度**：规范（硬编码颜色 / 单一数据源）
**位置**：`lib/widgets/chart_widgets.dart:91-98`、`lib/screens/personal_stats_screen.dart:272-276`

```dart
// chart_widgets.dart:91-98 —— 8 色
Color(0xFF7C8CF8), Color(0xFF764BA2), Color(0xFF11998E), Color(0xFFFFC94D),
Color(0xFFFFB020), Color(0xFF38EF7D), Color(0xFF667EEA), Color(0xFFFF6B6B)

// personal_stats_screen.dart:272-276 —— 同一序列的前 5 个，逐字重复
Color(0xFF7C8CF8), Color(0xFF764BA2), Color(0xFF11998E), Color(0xFFFFC94D), Color(0xFFFFB020)
```

同时这些值与 `app_palette.dart` 已定义的语义色**完全相同**：`accent=0xFF7C8CF8`、`readingEnd=0xFF764BA2`、`movieStart=0xFF11998E`、`star=0xFFFFC94D`、`warning=0xFFFFB020`、`movieEnd=0xFF38EF7D`、`readingStart=0xFF667EEA`、`danger=0xFFFF6B6B`。

**影响**：主题微调时需改 3 处（色板 + 图表 + 统计页），漏改即视觉不一致。这是**典型的「改了 A 忘了 B」隐患**。

**修改建议**：在 `app_palette.dart` 收敛为唯一来源，图表只引用：

```dart
// app_palette.dart —— 新增图表分类色板（放这里，与语义色同源）
class AppPalette {
  /// 图表分类色板：用于多分类环图/柱图的扇区着色。
  /// 顺序即默认分配顺序，新增分类会从头循环取用。
  static const List<Color> chartSeries = <Color>[
    Color(0xFF7C8CF8), // = accent
    Color(0xFF764BA2), // = readingEnd
    Color(0xFF11998E), // = movieStart
    Color(0xFFFFC94D), // = star
    Color(0xFFFFB020), // = warning
    Color(0xFF38EF7D), // = movieEnd
    Color(0xFF667EEA), // = readingStart
    Color(0xFFFF6B6B), // = danger
  ];
}

// chart_widgets.dart / personal_stats_screen.dart —— 改为引用
import '../config/app_palette.dart';
// final colors = AppPalette.chartSeries;
```

> 注意：`app_palette.dart` 里深浅两套主题的语义色**取值不同**（如 `accent` 深色 `0xFF7C8CF8` / 浅色 `0xFF6B7BE8`）。若图表希望随主题变化，应把 `chartSeries` 做成 `AppPalette` 的**实例字段**而非 `static const`，由 `context.colors.chartSeries` 取用；若希望分类色恒定（图表配色通常要求恒定以便对照），保持 `static const` 即可。**这一点需你按设计意图拍板**。

---

### M-3 · 全项目 0 处使用 `ListView.builder`，长列表全量构建

**维度**：性能
**位置**：`lib/widgets/cast_bottom_sheet.dart:196-206`、`lib/screens/actor_detail_screen.dart:209,297`、`lib/screens/data_source_screen.dart:36,124`

**先澄清做对的部分**：主库列表**已正确使用 lazy 构建** —— `books_screen.dart:155` 与 `library_screens.dart:131` 都用 `GridView.builder` + `SliverGridDelegateWithFixedCrossAxisCount`。书/影库这两个「真正会变长」的列表没有问题。

**问题在次级列表**——它们用 eager 的 `ListView(children: [...])`：

```dart
// cast_bottom_sheet.dart:196-206 —— 演职员表，演员数可达 50~100+
ListView(
  children: [
    if (directors.isNotEmpty) ...directors.map(_buildRow),   // 全部立即构建
    ...actors.map(_buildRow),                                // 全部立即构建
  ],
)

// actor_detail_screen.dart:297 —— 作品年表，同样 .map 展开
...works.map((m) => _WorkTile(...)),
```

**影响**：`ListView(children:)` 会**一次性构建全部 child**，滚动时无回收。一个 80 人演职员表 = 80 个 Row + 头像 `Image.network` 全部同时进入渲染树。对中低端机是明显的滚动掉帧与内存峰值。演职员表和作品年表是**用户可感知长**的列表，值得修。

**修改建议**（演职员表已有 `directors` / `actors` 两段，用 `itemCount` 拼平即可）：

```dart
// cast_bottom_sheet.dart —— 改为 lazy
final rows = <CastItem>[
  ...directors,
  ...actors,
];

ListView.builder(
  controller: scrollController,
  itemCount: rows.length,
  itemBuilder: (_, i) => _buildRow(rows[i]),
)
```

```dart
// actor_detail_screen.dart:297 —— 作品年表
ListView.builder(
  shrinkWrap: true,              // 嵌套在既有 SingleChildScrollView 内时保留
  physics: const NeverScrollableScrollPhysics(),
  itemCount: works.length,
  itemBuilder: (_, i) => _WorkTile(movie: works[i]),
)
```

> 注意：`shrinkWrap: true` + `NeverScrollableScrollPhysics` 是嵌套场景的权宜之计，它仍会构建全部 child（只是不再嵌套滚动），**性能收益有限**。彻底解法是把外层 `SingleChildScrollView` 换成 `CustomScrollView` + `SliverList.builder`。若只想快速止血，可先做 `cast_bottom_sheet`（它是独立滚动容器，无嵌套问题，收益最直接）。

另外，`data_source_screen.dart:124` 的 `...sources.map((s) => _SourceTile(...))` 无需改——数据源数量是人手配置的，量级在个位到十几，eager 完全合理。

---

### M-4 · 33 个成员函数超过 80 行，最长 `build()` 达 194 行

**维度**：规范（超长函数）
**超标 Top 10**：

| 文件:行 | 函数 | 行数 |
|---|---|---|
| `personal_stats_screen.dart:34` | `build()` | **194** |
| `profile_widgets.dart:320` | `build()` | 178 |
| `movie_edit_screen.dart:992` | `_buildGenreSection()` | 149 |
| `actor_detail_screen.dart:165` | `build()` | 143 |
| `actor_detail_widgets.dart:132` | `build()` | 137 |
| `library_screens.dart:42` | `build()` | 134 |
| `data_source_widgets.dart:447` | `build()` | 133 |
| `cast_bottom_sheet.dart:83` | `build()` | 132 |
| `movie_edit_screen.dart:1323` | `_buildActorField()` | 132 |
| `books_screen.dart:51` | `build()` | 129 |

（完整 33 条见附录 A）

**判断**：其中 `_buildGenreSection` / `_buildActorField` / `_buildHeaderCard` 这类**已是抽出的子方法**，属「方法内部 widget 树」的正常形态，机械拆分收益低。真正值得拆的是**根 `build()` 超过 150 行**的两处——它们通常混了「数据准备 + 布局 + 条件分支」三段职责。

**修改建议**（以 `personal_stats_screen.dart:34` 的 194 行 `build()` 为例）：

```dart
// 现状：build() 内一口气做 分区标题 / 环图 / 热力图 / Top5 / 年度回顾 五块
Widget build(BuildContext context) {
  final stats = context.select<LibraryProvider, BookStats>((p) => p.bookStats);
  return Scaffold(
    body: ListView(children: [
      // ... 194 行
    ]),
  );
}

// 目标：build 只留编排，各分区降级为同级私有方法（零行为变化）
Widget build(BuildContext context) {
  final stats = context.select<LibraryProvider, BookStats>((p) => p.bookStats);
  return Scaffold(
    backgroundColor: context.colors.background,
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _buildOverviewSection(stats),
        _buildCategoryDonut(stats),      // 原 100-170 行
        _buildHeatmapSection(stats),
        _buildTop5Section(stats),        // 原 65-150 行
        _buildAnnualSection(stats),
      ],
    ),
  );
}
```

---

### M-5 · 两个编辑页超大（1,738 / 1,721 行），体量集中在单个 State 类

**维度**：规范（文件组织）
**位置**：`lib/screens/book_edit_screen.dart`（1,738）、`lib/screens/movie_edit_screen.dart`（1,721）

**现状**：两文件合计 3,459 行，占 `screens/` 层的 32%。体量集中在 `_BookEditScreenState`（约 20 个 `_buildXxx()` + 表单状态 + 校验 + 保存编排 + 联网检索），与 State 字段强耦合。

**为什么不能套用上一轮的 `part` 切分**：`part` 切分要求「私有类连续位于文件尾部」可整块抽取。这两个文件的私有类只有 `_MetaChip` / `ActorSlot` 等少量尾部类，主体是**一个巨型 State 类**，按类切不动；按方法切需要跨库传递几十个 State 字段，可读性反而恶化。

**修改建议**：抽 `EditController`（ChangeNotifier）承载表单状态与校验，State 只留 Widget 构建。这是**架构级改动**，建议单独立项：

```dart
// lib/screens/book_edit/controller/book_edit_controller.dart
class BookEditController extends ChangeNotifier {
  BookEditController({Book? initial}) : _book = initial { _initControllers(); }

  final Book? _book;
  late final TextEditingController titleCtrl;
  late final TextEditingController authorCtrl;
  // ... 其余 10 个 controller 迁入

  double rating = 0;
  bool saving = false;
  String? errorText;

  /// 表单 → Book，含校验；返回 null 表示校验失败（errorText 已填）
  Book? buildBook();

  /// 保存编排（原 _doSave 的职责）
  Future<bool> save(LibraryProvider lib) async { ... }

  @override
  void dispose() { /* 统一释放全部 controller */ }
}

// View 侧瘦身为纯渲染
class BookEditScreen extends StatefulWidget { ... }
class _BookEditScreenState extends State<BookEditScreen> {
  late final _c = BookEditController(initial: widget.book);
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) =>
      ChangeNotifierProvider.value(value: _c, child: const _BookEditBody());
}
```

> 收益：编辑器逻辑可脱离 Widget 树做单元测试（当前只能写 widget test，慢且脆）。代价：约 1,700 行代码位移 + 回归风险。**建议排在 H-2 / M-1 之后**。

---

### M-6 · 327 处字面量字号，缺失设计 token 层

**维度**：规范（魔法数字）
**位置**：全仓；分布高度集中在下表

| 字号 | 出现次数 | 语义（推定） |
|---|---|---|
| 13 | 63 | 次要正文 |
| 12 | 63 | 辅助说明 |
| 14 | 53 | 正文 |
| 11 | 35 | 极小标注 |
| 15 | 32 | 强调正文 |
| 16 | 15 | 小标题 |
| 10 | 13 | 徽标 |
| 17 | 10 | 卡片标题 |
| 18 | 7 | 页面标题 |
| 20 / 22 / 24 | 5 / 5 / 5 | 大标题 / 数值 |

**影响**：5 种字号（11/12/13/14/15）承担了 246 处（75%）的使用，彼此只差 1px，**视觉层级几乎无法区分**——这通常说明字号是逐处手调的，而非按层级选取。改动任一层级需全仓搜索替换。

**修改建议**：在 `app_theme.dart` 或新建 `lib/config/app_typography.dart` 定义层级，样式表统一取值：

```dart
// lib/config/app_typography.dart
import 'package:flutter/material.dart';

/// 排版层级 —— 全项目字号唯一来源
///
/// 层级对应关系（避免再出现 12/13 混用）：
/// display  24  页面主数值 / 年度报告大数字
/// title    18  页面标题（AppBar）
/// heading  17  卡片标题
/// subhead  15  强调正文 / 表单分区标题
/// body     14  正文 / 输入框
/// label    12  列表项副标题 / 按钮
/// caption  11  辅助说明 / 时间戳
/// micro    10  徽标 / 角标
abstract final class AppType {
  static const double display = 24;
  static const double title = 18;
  static const double heading = 17;
  static const double subhead = 15;
  static const double body = 14;
  static const double label = 12;
  static const double caption = 11;
  static const double micro = 10;
}

// 使用处
Text('出版社', style: TextStyle(fontSize: AppType.label, color: c.textMuted))
```

> 迁移策略：先只用于**新代码**，旧代码在后续触碰时顺手替换，不做一次性全仓替换（327 处手工替换风险高于收益，且会污染 diff）。可保留一份映射表指导逐处归并：`13 → label(12)` 或 `caption(11)`（按实际层级判断），`15 → subhead`。

---

### M-7 · 886 处硬编码中文文案，无集中文案层

**维度**：规范（硬编码字符串）
**位置**：全仓；Top 分布

| 文件 | 处数 | 说明 |
|---|---|---|
| `data/mock_data.dart` | 115 | 演示数据标题/简介——**属预期，非问题** |
| `screens/book_edit_screen.dart` | 61 | 表单标签、提示、校验文案 |
| `screens/movie_edit_screen.dart` | 51 | 同上 |
| `services/data_sources/custom_data_source.dart` | 36 | **异常消息**——最值得抽 |
| `services/data_sources/tmdb_data_source.dart` | 30 | 异常消息 + 语言参数 |
| `screens/data_sync_screen.dart` | 30 | 同步流程文案 |
| `services/webdav_client.dart` | 25 | **异常消息** |

**判断**：这是一个**纯中文单语应用**，没有 i18n 需求。因此「硬编码文案」本身**不是缺陷**，套用 `flutter_localizations` + ARB 属于过度工程。真正值得处理的是其中**两处有实际收益**的部分：

**建议 1（有明确收益）—— 异常消息集中化**。`custom_data_source` / `webdav_client` / `backup_service` 的异常文本散落各处，且**被逻辑判断依赖**。实例：`data_source_manager.dart:289-292` 靠**匹配消息文本**推断状态：

```dart
// data_source_manager.dart:289-292 —— 用中文文案做控制流，脆弱
} on DataSourceException catch (e) {
  final msg = e.message.toLowerCase();
  status = msg.contains('超时') || msg.contains('timeout')
      ? DataSourceStatus.timeout
      : DataSourceStatus.error;
```

改一个字（如「超时」→「请求超时」之外的其他措辞）就会静默失效。**建议改为结构化字段**：

```dart
// data_source.dart —— 用枚举承载语义，消息仅用于展示
enum DataSourceErrorKind { timeout, network, format, auth, unknown }

class DataSourceException implements Exception {
  DataSourceException(this.message, {this.silent = false, this.kind = DataSourceErrorKind.unknown});
  final String message;
  final bool silent;
  final DataSourceErrorKind kind;   // ← 新增：控制流靠它，不靠文本
}

// 抛出侧
throw DataSourceException('连接超时，请检查网络', kind: DataSourceErrorKind.timeout);

// 判断侧（不再匹配中文）
status = switch (e.kind) {
  DataSourceErrorKind.timeout => DataSourceStatus.timeout,
  DataSourceErrorKind.auth    => DataSourceStatus.authFailed,
  _                           => DataSourceStatus.error,
};
```

**建议 2（有明确收益）—— 跨页复用的文案抽常量**。如「未配置书籍数据源」「保存失败」等在多处重复出现，抽到 `lib/config/app_strings.dart` 可避免措辞漂移：

```dart
// lib/config/app_strings.dart
abstract final class S {
  static const noBookSource   = '未配置书籍数据源，无法联网查找封面';
  static const saveFailed     = '保存失败，请重试';
  static const networkTimeout = '连接超时，请检查网络';
}
```

**不建议做**：引入完整 i18n 框架。当前无多语言需求，收益为零、成本显著。

---

### M-8 · `writeFileAtomic` 未纳入写链，与常规保存存在窄窗口竞态

**维度**：潜在 bug（并发）/ 数据完整性
**位置**：`lib/data/library_store.dart:106-111`，调用点 `lib/services/backup_service.dart:292,298`

```dart
// library_store.dart:106-111 —— 公开方法，不参与 _writeChain
Future<void> writeFileAtomic(String name, List<int> bytes) async {
  await dataDir.create(recursive: true);
  final tmp = File(_join('$name.tmp'));
  await tmp.writeAsBytes(bytes);
  await tmp.rename(_join(name));
}
```

**现状分析**：常规保存走 `_writeChain`（`_enqueueSave` → 串行冲刷，`:301-310`），`saveSettings` 另有一条 `_settingsTail` 串行队列，注释明确写了「避免固定 .tmp 文件并发 rename 冲突（H3-M4）」——说明项目**已经识别并修复过这一类问题**，但 `writeFileAtomic` 漏了。

**竞态路径（窄，但真实）**：`sync_provider.dart:257-258` 的恢复流程是

```dart
await _library.flush();                                    // ① 排空写链
await BackupService(store: store).restoreBackup(pending.bytes);  // ② 内部走 writeFileAtomic
```

① 只保证「**此前**已入队的写」落盘。若用户在**恢复进行中**触发一次新的保存（编辑页滑杆实时保存、删除条目等），该写会排在 `_writeChain` 上，与 ② 的 `writeFileAtomic` **并发写同一文件**：
- 两者共用固定 tmp 名 `$name.tmp` → 交错写 tmp 产生损坏内容，再 rename 覆盖目标；
- 恢复的第二个集合与保存的第一个集合交错 → 落盘出现**混合版本**（books 是备份的、movies 是本地新的）。

**影响边界**：需要用户在恢复过程中同时编辑才触发；发生时有回滚机制（`backup_service.dart:343-346` 的 `_rollbackDataFiles`）兜底，但**根因未除**。

**修改建议**：让 `writeFileAtomic` 复用 `_writeChain`，顺序自然串行；并把 tmp 名加上唯一后缀，彻底消除同文件 tmp 冲突：

```dart
/// 原子覆盖写数据目录下的 JSON 文件（tmp + rename，与集合写同契约）
///
/// 与常规保存共用 [_writeChain]，避免恢复备份与用户编辑并发写同一文件；
/// tmp 名带序号，杜绝同文件并发导致的 tmp 内容交错。
Future<void> writeFileAtomic(String name, List<int> bytes) {
  final done = _writeChain.then((_) => _writeFileAtomicNow(name, bytes));
  _writeChain = done.then((_) {}, onError: (_) {});
  return done;
}

Future<void> _writeFileAtomicNow(String name, List<int> bytes) async {
  await dataDir.create(recursive: true);
  final tmp = File(_join('$name.$_tmpSeq.tmp'));   // _tmpSeq 为自增 int 字段
  await tmp.writeAsBytes(bytes);
  await tmp.rename(_join(name));
}
```

> 需人工确认：`restoreBackup` 是否已在 UI 层禁用编辑入口（`_isSyncing` 期间）。若确实已禁用且无法绕过，本条降级为 Low；从代码看 `_isSyncing` 只驱动同步页的按钮态，**未拦截编辑页**，故维持 Medium。

---

### M-9 · `AppLogger` 的统计 getter 各遍历一次缓冲，`entries` 每次复制整表

**维度**：性能
**位置**：`lib/services/app_logger.dart:180-191`

```dart
List<LogEntry> get entries => List<LogEntry>.unmodifiable(_buffer);   // 每次调用复制整表（最多 500 条）
int get totalCount   => _buffer.length;
int get problemCount => _buffer.where((e) => e.level.isProblem).length;      // 全遍历
int get warningCount => _buffer.where((e) => e.level == LogLevel.warning).length;  // 全遍历
```

`error_log_screen.dart` / `error_log_widgets.dart` 在 build 中调用这些 getter；每次 rebuild 会**复制一次列表 + 遍历两次**。500 条上限下量级不大（微秒级），故定 Medium 而非 High；但 `entries` 的复制语义还带来一个正确性隐患：**页面的 `_entries` 是一份快照，新日志不会自动出现在已打开的页面上**（需手动刷新）。

**修改建议**：缓存统计量，改为增量维护；`entries` 提供两种访问方式：

```dart
class AppLogger extends ChangeNotifier {   // ← 继承 ChangeNotifier，让页面可订阅
  int _problemCount = 0;
  int _warningCount = 0;

  /// 只读视图，不复制（调用方不得修改；内部已保证 _buffer 不可外部触碰）
  List<LogEntry> get entries => UnmodifiableListView(_buffer);
  int get totalCount   => _buffer.length;
  int get problemCount => _problemCount;   // O(1)
  int get warningCount => _warningCount;   // O(1)

  void _record(LogEntry entry) {
    _buffer.add(entry);
    if (entry.level.isProblem) _problemCount++;
    if (entry.level == LogLevel.warning) _warningCount++;
    if (_buffer.length > maxBufferEntries) {
      final dropped = _buffer.removeAt(0);           // 逐出时同步减计数
      if (dropped.level.isProblem) _problemCount--;
      if (dropped.level == LogLevel.warning) _warningCount--;
    }
    notifyListeners();                               // 日志页可自动刷新
  }
}
```

配套把 `error_log_screen.dart:22` 的 `List<LogEntry> _entries` 快照改为 `context.watch`/`ListenableBuilder` 订阅，`_refresh()` 可删。

> 注：`clear()` / `init()` / `debugReset()` 里同步把两个计数器归零。

---

## 五、Low

### L-1 · `debugPrint` 在 release 并非 no-op，注释失准

**维度**：规范（注释正确性）/ 性能
**位置**：`lib/services/app_logger.dart:274-275`

```dart
// 开发期仍在控制台可见；生产 release 下 debugPrint 是 no-op   ← 此断言不成立
debugPrint('[${level.label}][$tag] $message');
```

**实证**：Flutter SDK `packages/flutter/lib/src/foundation/print.dart:49` —

```dart
DebugPrintCallback debugPrint = debugPrintThrottled;   // 顶层变量，无 kReleaseMode 守卫
```

全文件 grep `kReleaseMode` **无命中**。`debugPrint` 在 release 下**照常输出**（仅 `flutter_test` 会把它替换为 no-op）。因此每条日志在生产环境都会写一次控制台，且 `debugPrintThrottled` 带**节流与丢弃**逻辑（高频日志会被采样丢弃）。

**修改建议**（注释 + 行为一起修，避免误导后来者）：

```dart
// 开发期在控制台可见；release 下 debugPrint 仍会输出，故按 kDebugMode 显式收口，
// 生产只落盘不进控制台（省一次平台通道调用，也避免刷屏）
if (kDebugMode) {
  debugPrint('[${level.label}][$tag] $message');
}
```

> 需在文件头补 `import 'package:flutter/foundation.dart';`（`kDebugMode` 来源，`app_logger.dart` 当前应已引入 foundation，确认即可）。

---

### L-2 · 空 `catch` 块（3 处），其中 1 处可优化

**维度**：规范
**位置**：`lib/services/log_exporter_io.dart:23-25`、`lib/services/backup_service.dart:230-232`、`lib/services/app_logger.dart:321-323`

```dart
// log_exporter_io.dart:23 —— 临时文件清理
} on Object catch (_) {
  // 忽略
}
```

**判断**：这三处**都是有意的容错**且都写了说明（`backup_service` 的注释是「单条损坏跳过，与 LibraryStore 逐条隔离策略一致」），属于**正确的设计**，不是反模式。仅建议在 `log_exporter_io` 处补一句「为何可忽略」，与另外两处保持一致：

```dart
} on Object catch (_) {
  // 临时文件清理失败可忽略：不占业务路径，残留文件由系统临时目录策略回收
}
```

---

### L-3 · `Environment` 描述与平台取值未处理 `fuchsia`

**维度**：规范
**位置**：`lib/services/app_logger.dart:195`

```dart
final platform = kIsWeb ? 'Web' : defaultTargetPlatform.name;
```

`defaultTargetPlatform` 在非 Web 下可能返回 `fuchsia`（Flutter 的枚举包含它，尽管实际设备罕见）。当前写法会导出 `fuchsia` 这种对报障无意义的字符串。建议映射为可读中文：

```dart
final platform = kIsWeb
    ? 'Web'
    : switch (defaultTargetPlatform) {
        TargetPlatform.android => 'Android',
        TargetPlatform.iOS     => 'iOS',
        TargetPlatform.macOS   => 'macOS',
        TargetPlatform.windows => 'Windows',
        TargetPlatform.linux   => 'Linux',
        TargetPlatform.fuchsia => 'Fuchsia',
      };
```

---

### L-4 · `_SourceEditSheet` 的 `late final` 字段在 `dispose()` 中无条件访问

**维度**：潜在 bug（`late` 未初始化）
**位置**：`lib/screens/data_source_widgets.dart:184-190`（声明）、`:246-255`（dispose）

```dart
late final DataSourceConfig _config = widget.config;          // :184
late final Map<String, TextEditingController> _secretCtrls;   // :190，在 initState 内赋值

@override
void dispose() {
  _nameCtrl.dispose();
  for (final c in _plainCtrls.values) c.dispose();
  for (final c in _secretCtrls.values) { c.dispose(); }       // ← 若 initState 中途抛异常，这里 LateInitializationError
  super.dispose();
}
```

**影响**：`initState`（`:197-243`）若在 `_secretCtrls = {...}` 之前抛异常（例如 `_ds.configFieldsOf(_config.type)` 对未知类型抛错），`dispose()` 会二次抛出 `LateInitializationError` 并**掩盖原始异常**，让排查方向跑偏。定为 Low 是因为触发前提较苛刻（需 `configFieldsOf` 对已存在的配置抛错）。

**修改建议**：改为可空字段 + 空安全遍历，或先赋值再做事：

```dart
Map<String, TextEditingController>? _secretCtrls;

@override
void initState() {
  super.initState();
  // 先建空容器：即便后续取值抛异常，dispose 也能安全执行
  _plainCtrls = <String, TextEditingController>{};
  _secretCtrls = <String, TextEditingController>{};

  _fields = _ds.configFieldsOf(_config.type);   // 可能抛错，但在容器就绪之后
  for (final f in _fields) { ... }
}

@override
void dispose() {
  _nameCtrl.dispose();
  for (final c in _plainCtrls?.values ?? const <TextEditingController>[]) c.dispose();
  for (final c in _secretCtrls?.values ?? const <TextEditingController>[]) c.dispose();
  super.dispose();
}
```

---

### L-5 · `mock_data.dart`（381 行）进入生产构建并被 Provider 引用

**维度**：规范 / 包体
**位置**：`lib/data/mock_data.dart`、`lib/providers/library_provider.dart:9,52,55`

```dart
// library_provider.dart:9
import '../data/mock_data.dart';
// :52
List<Book> _books = List.of(kAllBooks);      // 构造期即复制全量 seed
// :55
List<Movie> _movieList = List.of(kMovieList);
```

**判断**：这是**有意的双模式设计**（注释 `:21-24` 说明：不传 `store` 即内存模式，供 UI 预览 / 测试 / Web 使用）。生产路径 `main.dart:49-56` 传入了持久化 store，`init()` 会覆盖 seed。但有两点副作用：

1. **构造期无谓复制**：生产启动时先 `List.of(kAllBooks)` 复制一份 seed，随后 `init()` 立刻丢弃换成磁盘数据——一次纯浪费的分配；
2. **演示数据随包发布**：`kAllBooks` / `kMovieList` 的文案（115 条中文字符串）会进入 release APK。若 seed 中含虚构作者/出版社名，属于可接受；若含真实版权作品的简介则需评估。

**修改建议**：生产路径延迟 seed 构造，仅在内存模式下才复制：

```dart
class LibraryProvider extends ChangeNotifier {
  LibraryProvider({LibraryStore? store, ImagePickService? picker})
      : _store = store,
        _picker = picker,
        // 内存模式（无 store）才载入 seed；持久模式留空，由 init() 从盘填充
        _books = store == null ? List.of(kAllBooks) : <Book>[],
        _movieList = store == null ? List.of(kMovieList) : <Movie>[],
        _actors = store == null ? List.of(kActors) : <Actor>[];
}
```

> 需连带确认 `books_screen` / `library_screens` 在 `init()` 完成前不会渲染空态（`main.dart:49` 已 `await bootstrapApp()`，故生产下渲染前必已填充）。此改动会触碰 3 个列表的初始值，**建议先跑全量测试确认 409 项无回归**。

---

### L-6 · `FlutterError.onError` 覆盖后未调用 `presentError`，丢失框架默认上报

**维度**：潜在 bug（开发期可观测性）
**位置**：`lib/main.dart:31-42`

```dart
FlutterError.onError = (details) {
  debugPrint('[FlutterError] ${details.exception}');   // 自己打印
  AppLogger.instance.fatal('flutter', 'Flutter 框架错误', ...);  // 落盘
  // ← 未调用 FlutterError.presentError(details)
};
```

**影响**：覆盖 `onError` 而不委托给 `presentError` 会**替换掉** Flutter 的默认错误展示。默认实现除了打印完整诊断（含 widget 树、错误上下文）外，在 debug 下还会触发红屏。现在只保留了自己那行 `debugPrint`（仅打印 `exception`，**不含 `details.informationCollector` 的诊断信息**），排查布局/构建错误时信息量骤降。

**影响边界**：这是**开发期体验问题**，生产环境下 `presentError` 也主要是控制台输出，故定 Low。

**修改建议**：保留默认行为，附加自己的落盘：

```dart
FlutterError.onError = (details) {
  // 保留 Flutter 默认上报（完整 widget 树诊断 + debug 红屏）
  FlutterError.presentError(details);
  // 再补一份落盘，供用户导出报障
  AppLogger.instance.fatal(
    'flutter',
    'Flutter 框架错误',
    error: details.exception,
    stack: details.stack,
    meta: {if ((details.library ?? '').isNotEmpty) 'library': details.library!},
  );
};
```

> `PlatformDispatcher.instance.onError` 的 `return true`（`:46`）同理：它吞掉所有未捕获异步异常。项目选择「永不完全崩溃」是产品决策，注释已写明，**建议保留**；但要注意它会让编程错误（`TypeError` / `StateError`）在开发期静默。现在有了 `AppLogger.fatal` 落盘 + 错误日志页，这个取舍是成立的。

---

### L-7 · `stats_card.dart` 等渐变卡组件内 16 处 `Colors.white` 硬编码

**维度**：规范（硬编码颜色）
**位置**：`lib/widgets/stats_card.dart:62,79,93,94,96,122,139,164,174,181,201,210,230,231,240,248`

**判断**：这些 `Colors.white` / `Colors.white70` 用在**彩色渐变背景之上**（`linear-gradient` + 白字 + 半透明白边框），语义上「永远是白的」是**正确的**，不属于「该用主题色却写死」的错误。同一情况见 `profile_widgets.dart:479`、`book_list_card.dart:167,193`、`placeholder_view.dart:33`。

**唯一实际问题**：`Colors.white.withOpacity(0.18)` / `0.16` / `0.22` / `0.35` 这组**透明度魔法数字**（`:201,230,231,93`）散落且相近，语义（分隔线 / 卡片底 / 描边）靠猜。

**修改建议**：抽成组件级常量，把「语义」命名出来：

```dart
// stats_card.dart 顶部
/// 渐变卡上的白色叠加层不透明度 —— 语义化命名，避免 0.16/0.18/0.22 靠猜
abstract final class _OnGradient {
  static const double trackFill  = 0.22;   // 进度环底槽
  static const double softSurface = 0.18;  // 次级卡片底
  static const double chipFill    = 0.16;  // 小徽标底
  static const double chipBorder   = 0.35; // 小徽标描边
}

// 使用处
trackColor: Colors.white.withOpacity(_OnGradient.trackFill),
```

---

### L-8 · `_lookupCoverOnline` 未处理流派数据源返回空封面时的重试/兜底提示

**维度**：规范（提示文案）
**位置**：`lib/screens/book_edit_screen.dart:1669-1674`

```dart
if (url == null || url.isEmpty) {
  messenger.showSnackBar(const SnackBar(
    content: Text('没找到合适的封面，可改用「粘贴网络图片链接」'),
  ));
  return;
}
```

**判断**：**这段代码本身是对的**（异步守卫、messenger 提前捕获、`finally` 里 `hideCurrentSnackBar` 都规范）。唯一摩擦点是查不到时的提示未区分两种成因——「数据源没返回」vs「返回了但该源本身无封面图」。用户会反复重试却始终失败。

**修改建议**（可选）：把成因写进提示，减少无效重试：

```dart
if (url == null || url.isEmpty) {
  messenger.showSnackBar(SnackBar(
    content: Text(
      isbn.isEmpty
          ? '按书名没找到封面，填上 ISBN 再试会更准'
          : '这个 ISBN 在数据源里没有封面图，可改用「粘贴网络图片链接」',
    ),
  ));
  return;
}
```

---

## 六、维度 6：pubspec 依赖专项

**文件**：`pubspec.yaml`（13 个生产依赖 + 2 个开发依赖）

### 6.1 未使用依赖检查 → **0 个未使用**

逐一核对 `package:<name>/` 的实际 import：

| 依赖 | 声明 | 解析版本 | import 位置 | 结论 |
|---|---|---|---|---|
| `provider` | `^6.1.2` | 6.1.5+1 | 16 处 | 使用中 |
| `path_provider` | `^2.1.4` | 2.1.5 | `log_sink_io`、`persistence_io` | 使用中 |
| `path` | `^1.9.0` | 1.9.0 | `library_store`、`library_provider`、`backup_service` | 使用中 |
| `image_picker` | `^1.1.2` | 1.1.2 | `image_pick_service` | 使用中 |
| `http` | `^1.2.0` | 1.6.0 | `webdav_client`、4 个数据源、`http_retry`、`library_provider` | 使用中 |
| `flutter_secure_storage` | `^9.2.2` | 9.2.4 | `secure_storage_service` | 使用中 |
| `archive` | `^3.6.1` | 3.6.1 | `backup_service` | 使用中 |
| `share_plus` | `^10.0.0` | 10.1.4 | `log_exporter_io`、`log_exporter_stub`、`sync_provider` | 使用中 |
| `file_picker` | `^8.0.0` | 8.3.7 | `data_sync_screen` | 使用中 |
| `connectivity_plus` | `^6.0.5` | 6.1.5 | `sync_provider` | 使用中 |
| `image` | `^4.2.0` | 4.3.0 | `image_compress_service` | 使用中 |
| `flutter_markdown` | `^0.7.7` | 0.7.7+1 | `data_source_guide_sheet` | 使用中 |
| `url_launcher` | `^6.3.0` | 6.3.1 | `data_source_guide_sheet` | 使用中 |
| `flutter_lints` (dev) | `^4.0.0` | 4.0.0 | `analysis_options.yaml` | 使用中 |

> `markdown` 7.3.0 出现在 lock 中但**未声明为直接依赖**，是 `flutter_markdown` 的传递依赖——这是**正确做法**（不直接 import 就不该声明，避免版本约束冲突）。项目注释亦已说明。

### 6.2 版本区间合理性

**结论：整体合理**，采用 `^`（caret）上界宽松策略，对应用类项目是恰当的取舍。以下为需注意的点：

| 项 | 评估 | 建议 |
|---|---|---|
| `sdk: '>=3.5.0 <4.0.0'` | **偏松**。代码使用了 Dart 3 pattern matching、`if-case`、`switch` 表达式等 3.0+ 特性，`3.5.0` 下界合理；`<4.0.0` 是惯例写法 | 保持。若要严格，可收紧到 `>=3.5.0 <3.7.0` 以匹配已验证的 SDK |
| `flutter_secure_storage: ^9.2.2` | **需关注**。解析到 9.2.4，仍在 9.x 主版本内，`^` 不会越到 10.x。9.x 已知有 Android `EncryptedSharedPreferences` 在部分机型上的兼容讨论 | **需人工确认**：在目标 minSdk 与真机上验证凭据读写是否稳定。我未核对上游 issue 跟踪，不做结论 |
| `share_plus: ^10.0.0` | 解析 10.1.4。10.x 相对 9.x 有 API 变更（`Share.shareXFiles` 签名）。项目已按 10.x API 使用 | 保持 |
| `file_picker: ^8.0.0` | 解析 8.3.7。`^8.0.0` 允许 `8.x` 全部小版本，无主版本跃迁风险 | 保持 |
| `image: ^4.2.0` | 解析 4.3.0。纯 Dart 包，无平台耦合 | 保持 |
| `flutter_markdown: ^0.7.7` | 解析 0.7.7+1。**注意：`flutter_markdown` 上游已宣布进入维护状态**（推荐迁移 `flutter_markdown_plus` 等社区分支） | **需人工确认**：短期无风险；若未来需 Flutter 大版本升级，此包可能成为阻塞项。建议在 README 记录技术债 |
| `connectivity_plus: ^6.0.5` | 解析 6.1.5 | 保持 |
| `http: ^1.2.0` | 解析 1.6.0，跨度较大但均在 1.x，API 稳定 | 保持 |

### 6.3 已知冲突

**未发现**依赖冲突：`flutter pub get` 正常完成，lock 文件无版本回退告警，且 `flutter analyze` 与全量测试（409 项）均通过。项目**无 `dependency_overrides`**，说明依赖图本身是自洽的。

需要人工确认的两项（**我不做结论**）：

1. **`flutter_secure_storage` 9.x 在目标 Android API 上的行为**——需真机验证 WebDAV 凭据的读写与卸载重装后的残留；
2. **`flutter_markdown` 的维护状态**——上游活跃度需你在升级 Flutter 大版本前复查。

### 6.4 一条既有构建告警（非依赖声明问题）

`flutter_plugin_android_lifecycle` 要求 `compileSdk 35`，而 `android/app/build.gradle` 当前为 `34`。**能正常构建**（Gradle 会自动下载 SDK Platform 35 化解告警），不影响产物。若想消除告警：

```gradle
// android/app/build.gradle
android {
    compileSdk 35   // 由 34 提升；需确认本机已装 SDK Platform 35（已装）
    // ...
}
```

---

## 七、已核实「无问题」项（避免后续重复排查）

以下项目经**逐处读码 + 实证**确认无缺陷，建议不再作为审查议题重复投入：

### 7.1 内存泄漏维度 —— 生命周期管理近乎完备

| 检查项 | 结果 |
|---|---|
| `AnimationController` | **全仓 0 处**（不存在相关泄漏风险） |
| `PageController` | **全仓 0 处** |
| `StreamSubscription` | **全仓 0 处**（项目用回调式 API，未引入 Stream 订阅） |
| `TabController` | 1 处（`movie_stills_screen.dart:38`），已在 `:52-55` 正确 `dispose` |
| `Timer` | 2 处（`book_edit_screen.dart:93`、`movie_edit_screen.dart:115`），均在 `dispose` 中 `?.cancel()` |
| `FocusNode` | 全部（`_categoryFocus`、`_genreFocus`、`_directorFocus`、`ActorSlot.focus`）均 dispose |
| `TextEditingController` | **26 处，25 处正确 dispose**；唯一遗漏见 M-1（`_promptTextDialog`） |
| `ActorSlot` 动态增删 | **正确**。`_applyDirectorSync`（`movie_edit_screen.dart:232-238`）与删除回调（`:1288-1289`）都在移除槽位前 `slot.dispose()`；`State.dispose`（`:189-191`）遍历释放全部 |
| `http.Client` | 4 个数据源实现 + `WebDavClientHttp` 均提供 `close()`，由 `DataSourceManager.close()`（`:305-315`）统一释放，挂在 `DataSourceProvider.dispose()`（`:699`） |
| Provider `_disposed` 守卫 | **3/3 完备**，全仓 0 处裸 `notifyListeners()` |

### 7.2 状态管理维度（Provider）

项目使用 **Provider 6.1.5**（`ChangeNotifierProvider` + `Provider.of` 家族），用法**成熟且正确**：

| 检查项 | 结果 |
|---|---|
| 订阅粒度 | `context.select` **23 处** / `context.watch` **2 处** / `context.read` **41 处** — 说明作者**主动区分**了「订阅」与「取值」，而非一律 `watch` |
| `Consumer` 使用 | **0 处**。这是**合理选择**：`context.select` 已能达成同样的精确订阅，混用会降低一致性 |
| `Selector` 使用 | 0 处（Provider 特有 API，`context.select` 是等价且更简洁的替代） |
| `watch` 位置 | 仅 2 处，且均不在事件回调中（无「callback 中 watch」的经典反模式） |
| dispose 后通知 | 已防护（`_notifyIfAlive`） |
| Provider 嵌套 | `MultiProvider` 单层（`main.dart:143-150`），`_AppShell` 下沉主题订阅，`main.dart:141-142` 注释明确说明「本层 context 在 Provider 之上不能 watch」——**作者对 Provider 的 context 层级语义理解到位** |
| rebuild 收敛 | `main.dart:203` 用 `context.select<LibraryProvider, String>((p) => p.themeMode)` 避免整棵 `MaterialApp` 重建；`books_screen.dart:56`、`library_screens.dart:47` 同样用 `select` 只订阅列表引用 |

**唯一的架构级建议**是 H-1 附注（Provider 承职过多），属设计取向而非用法错误。

### 7.3 性能维度（除 M-3 外）

| 检查项 | 结果 |
|---|---|
| `build` 内 new 对象 | 仅 2 处（`dashboard_widgets.dart:124,285` 的 `final tiles = <Widget>[]`）——均为**每次 build 必须重建的局部列表**，属正常写法，非缓存缺失 |
| null-aware / late 收口 | 未发现 `late` 在 dispose 中被无条件访问的普遍问题（仅 L-4 一处，且触发条件苛刻） |
| 缓存 | `TtlCache`（`ttl_cache.dart`）**LRU 语义正确**：`get` 先 remove 再 re-insert 到队尾（`:41-45`），`put` 先 remove 旧位再插（`:55-56`），逐出取队首 = 最久未使用（`:57-59`）。时钟可注入，便于测试 |
| 网络容错 | `http_retry.dart` 分层超时（首跳 6s + 重试 9s）仅对 `Timeout/Socket/ClientException` 重试，**不对 4xx/5xx 重试**——语义正确 |
| 两跳压一跳 | `bookDetailIsRedundant`（`data_source_provider.dart:715`）在搜索响应已含全部详情字段时跳过详情请求，注释完整说明了判定边界（「任何一项缺失都仍然值得发那次请求」） |

### 7.4 潜在 bug 维度

| 检查项 | 结果 |
|---|---|
| `mounted` 守卫 | **完备**（13 处初筛疑似全部有守卫，见第二节误报表） |
| `setState` 在 dispose 后 | 未发现。所有异步路径（日期选择、相册、URL 弹窗、联网找封面）均在 `await` 后先判 `mounted` |
| `ScaffoldMessenger` 跨 async | **规范**。`book_edit_screen.dart:1655`、`error_log_screen.dart:36` 等均在 `await` **之前**捕获 messenger 实例，符合 `use_build_context_synchronously` 的正确解法 |
| `unawaited` 使用 | **8 处全部显式标注**且 5 处附带 `.catchError`（`library_provider.dart:241,251,261,271`、`main.dart:115`）——`unawaited_futures` lint 已开启，无遗漏 |
| 数据写入原子性 | `_writeChain` 串行 + tmp/rename 原子写（`library_store.dart:106-111, 293-310`），集合写与 settings 写各有串行队列。唯一遗漏见 M-8 |
| 异常归一 | `backup_service.dart:363-368` 用 `on BackupException { rethrow }` + `on Object catch` 兜底，把未归一化的 `TypeError`/`ArgumentError` 转成业务异常，注释说明了原因——**这是好实践** |

---

## 八、修复优先级建议

| 顺序 | 条目 | 风险 | 工作量 | 收益 |
|---|---|---|---|---|
| 1 | **H-2** 日志写链串行化 + 截断对齐换行 | 低 | ~20 行 | 报障日志不再丢行/乱码 |
| 2 | **M-1** `_promptTextDialog` 补 `dispose` | 低 | ~10 行 | 消除唯一 dispose 契约违反 |
| 3 | **M-8** `writeFileAtomic` 纳入写链 + tmp 唯一化 | 低 | ~10 行 | 消除恢复期混合版本风险 |
| 4 | **M-2** 色板收敛到 `AppPalette` | 低 | ~15 行 | 主题改动单一数据源 |
| 5 | **M-3** 演职员表 / 作品年表改 `ListView.builder` | 低 | ~20 行 | 长列表滚动流畅度 |
| 6 | **M-9** `AppLogger` 计数增量维护 + 可订阅 | 中 | ~40 行 | 日志页自动刷新 + O(1) 统计 |
| 7 | **M-7 建议 1** 异常语义结构化（`kind` 枚举） | 中 | ~60 行 | 消除「改文案即失效」的脆弱控制流 |
| 8 | **M-4** 两个 150 行以上的根 `build()` 拆分 | 低 | ~80 行 | 可读性 |
| 9 | **M-6** 新建 `AppType` 排版层级（仅新代码用） | 低 | ~20 行 | 遏制字号继续发散 |
| 10 | **L-1 / L-6** 注释修正 + `presentError` 委托 | 低 | ~10 行 | 减少对代码的误读 |
| 11 | **H-1** 架构分层与命名对齐 | **高** | 大 | 长期可维护性——**建议单独立项、增量推进** |
| 12 | **M-5** 编辑页抽 `BookEditController` | **高** | 大 | 逻辑可单测——**建议单独立项** |

**建议本轮先做 1–4**（合计约 55 行改动，全部为低风险局部修改，可直接跑 409 项测试验证）。第 11、12 项涉及大规模代码位移，不宜与前述修改混在同一次提交中。

---

## 附录 A · 超长函数完整清单（33 项，>80 行）

| 文件:行 | 函数 | 行数 |
|---|---|---|
| `screens/personal_stats_screen.dart:34` | `build()` | 194 |
| `screens/profile_widgets.dart:320` | `build()` | 178 |
| `screens/movie_edit_screen.dart:992` | `_buildGenreSection()` | 149 |
| `screens/actor_detail_screen.dart:165` | `build()` | 143 |
| `screens/actor_detail_widgets.dart:132` | `build()` | 137 |
| `screens/library_screens.dart:42` | `build()` | 134 |
| `screens/data_source_widgets.dart:447` | `build()` | 133 |
| `widgets/cast_bottom_sheet.dart:83` | `build()` | 132 |
| `screens/movie_edit_screen.dart:1323` | `_buildActorField()` | 132 |
| `screens/books_screen.dart:51` | `build()` | 129 |
| `widgets/grid_item_card.dart:52` | `build()` | 115 |
| `screens/movie_edit_screen.dart:465` | `build()` | 111 |
| `widgets/book_list_card.dart:30` | `build()` | 111 |
| `services/backup_service.dart:240` | `restoreBackup()` | 109 |
| `screens/book_edit_screen.dart:469` | `build()` | 103 |
| `screens/movie_edit_screen.dart:1586` | `_buildActions()` | 103 |
| `screens/data_source_widgets.dart:9` | `build()` | 102 |
| `screens/movie_detail_screen.dart:51` | `build()` | 101 |
| `screens/book_detail_screen.dart:106` | `_buildHeaderCard()` | 100 |
| `screens/annual_report_screen.dart:23` | `build()` | 99 |
| `screens/profile_screen.dart:117` | `_showProfileInfo()` | 99 |
| `screens/movie_detail_screen.dart:155` | `_buildHeaderCard()` | 97 |
| `screens/dashboard_screen.dart:31` | `build()` | 94 |
| `screens/book_edit_screen.dart:598` | `_buildHeaderCard()` | 91 |
| `screens/error_log_widgets.dart:178` | `build()` | 89 |
| `screens/movie_detail_screen.dart:476` | `_buildReviewCard()` | 86 |
| `screens/profile_screen.dart:28` | `build()` | 86 |
| `screens/movie_edit_screen.dart:313` | `_doSave()` | 85 |
| `screens/movie_edit_screen.dart:1229` | `_buildCastEditor()` | 85 |
| `screens/book_edit_screen.dart:713` | `_buildCategoryChipField()` | 83 |
| `widgets/media_tile.dart:48` | `build()` | 104 |
| `screens/data_sync_widgets.dart:32` | `build()` | 80 |
| `widgets/quick_search_panel.dart:73` | `build()` | 80 |

> 已按要求排除 `*.g.dart` 与 `generated/`（项目中均为 0 个文件）。

---

## 附录 B · 硬编码颜色完整清单（非色板文件）

除 `config/app_palette.dart`（色板定义本身，37 处，**正确**）外的全部硬编码颜色：

| 文件 | 处数 | 性质 |
|---|---|---|
| `widgets/stats_card.dart` | 16 | 渐变卡上白字/白框 —— **语义正确**，仅不透明度魔法数字可抽（L-7） |
| `screens/movie_edit_screen.dart` | 13 | 多为 `Colors.transparent`（AppBar 透明）+ 滑杆/遮罩上的白色 —— 正确 |
| `screens/movie_detail_widgets.dart` | 6 | 占位图渐变 `Color(0xFF565664)` 等 —— **建议抽常量**（见下） |
| `screens/personal_stats_screen.dart` | 5 | 图表色板 —— **见 M-2** |
| `screens/personal_stats_widgets.dart` | 5 | 选中态 `Colors.white` —— 正确 |
| `config/app_theme.dart` | 3 | `onPrimary: Colors.white` / `transparent` —— 正确 |
| `widgets/chart_widgets.dart` | 8 | 图表色板 —— **见 M-2** |
| `widgets/cast_bottom_sheet.dart` | 3 | 头像占位渐变，与 `movie_detail_widgets` **重复**（见下） |
| 其余 10 个文件 | 各 1–4 | 均为 `Colors.transparent` 或渐变卡白字 —— 正确 |

**一处新发现的重复**（与 M-2 同类）：头像占位渐变在 `movie_detail_widgets.dart:66-67` 与 `cast_bottom_sheet.dart:338-339` **逐字重复**：

```dart
// 两处完全相同
? const [Color(0xFF565664), Color(0xFF33333F)]
: const [Color(0xFFD4D4DE), Color(0xFFAEAEBB)],
color: isDark ? const Color(0xFFD8D8E2) : const Color(0xFF5A5A6A),
```

建议与 `cover_placeholder.dart` 的占位样式一并在 `AppPalette` 中收敛为 `placeholderGradient(bool isDark)` + `placeholderGlyph(bool isDark)`。
