# 墨影 MoYing 🎬📚

一个**深浅双主题**的书籍与电影记录应用（Flutter 跨平台，数据本地持久化，离线优先——联网检索为可选增强）。

底部四标签导航：**仪表盘 / 书籍 / 电影 / 个人**。

- **仪表盘**：统计双卡（阅读平均进度环 + 观影均分徽章）、当前任务横滑区、阅读列表与我的电影网格（各 4 条，可跳转全量）
- **书籍 / 电影**：搜索 + 动态筛选 + 列表/网格切换，卡片单击进详情、长按进编辑；详情页含演职员表、剧照全量页，演员页可反查参演作品
- **个人**：昵称 / 签名 / 头像编辑、深浅主题三选（深色 / 浅色 / 跟随系统）、数据统计、数据源管理、数据同步、错误日志

v0.9.0 起首启为**空库**，由用户自行录入；此后增删改全部持久化到本地。
（演示种子数据仅保留在测试中）

## 运行

```bash
# 本仓库在 Flutter 3.24.x 验证（含 3.24.5）
flutter pub get
flutter run            # 选择目标设备（Android / iOS / macOS）
```

> 国内网络可配置镜像后运行：
> ```bash
> export PUB_HOSTED_URL=https://pub.flutter-io.cn
> export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
> ```

打包 Android 安装包：

```bash
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

## 验证

```bash
flutter analyze       # 静态分析（CI 以 --fatal-infos 运行，期望 0 issue）
flutter test          # 单元与 widget 测试（当前 420 个用例）
```

CI（`.github/workflows/ci.yml`）在 `main` 的 push / PR 上依次执行
`flutter analyze --fatal-infos` → `flutter test` → `flutter build web`。

> **平台支持**：**Android / iOS / macOS 是主要目标**——持久化、图片管理、备份与 WebDAV
> 同步都依赖 `dart:io` 的本地文件系统。
> Web 目标**可以编译**（CI 会构建），但缺少本地文件系统：`persistence_stub.dart` 回退为
> 纯内存存储（刷新即丢），日志落盘与导出（`log_sink_stub.dart` / `log_exporter_stub.dart`）
> 降级为 no-op，图片 / 备份 / 同步等入口按平台隐藏或降级。
> 即「能跑起来看 UI，不能当正式使用平台」。

## 版本历史

- **v0.9.3**（当前开发版，尚未打 tag）：
  - **架构重构**：按四层组件化 + MVVM 规范重整工程——96 个文件归入
    `app / business / component / foundation`，`XxxScreen` → `XxxPage`、`*_screen.dart` → `*_page.dart`，
    消除 9 组 `part` 与全部 `widget` 关键字命名，**反向依赖 61 → 0 处**。纯结构迁移，无行为变化。
  - **错误日志**：新增应用日志中枢 `AppLogger`（info/warn/error/fatal 分级、内存环形缓冲 500 条、
    落盘滚动 2MB、写链串行化）+ 全局异常兜底（`FlutterError.onError` / `PlatformDispatcher.onError`），
    埋点覆盖网络请求重试、数据源取数、同步与备份失败；个人中心新增「错误日志」页
    （分级统计、列表、导出系统分享 / 复制全部 / 清空）。**纯本地，不上传任何数据。**
  - **电影详情**：接入 TMDB 演员真头像与真实剧照，新增**演职员表弹层**（导演 / 演员分组、可搜索）
    与**剧照与海报全量页**（Tab 切换、Sliver 懒构建），剧照落盘缓存、进全量页不再发网络请求。
  - **联网检索增强**：数据源页新增「自建部署指南」入口（Markdown 教程，含 GitHub + Render
    免费托管示例）；图书检索改多源聚合（结果去重合并 + 中文分类映射）；自定义源适配豆瓣系接口
    （`pubdate` / 嵌套 `rating` / HTML 剥离）；封面请求补 Referer、镜像回退、两级缓存、
    分层超时 + 一次重试（弱网下首跳建连单独设超时）。
  - **同步**：新增记录级 **LWW 合并引擎**（按 id 并集、`updatedAt` 新者胜）与**同步前本地快照兜底**
    （滚动保留最近数份，合并出问题可回退）。
  - **图片**：新增单图压缩与上限（magic bytes 探活 → 等比缩放到长边上限 → 重编码，控制在 5MB 内落盘）。
  - **编辑页**：评分只由用户手动打（取消自动填充）；星级选择器支持拖动打分 + 跨档触感反馈；
    手动录入的书支持「联网自动找封面」；电影详情头部改水平卡片布局，个人模块弹窗高度统一。
  - **性能**：演职员表与演员作品年表由 eager 全量构建改 `CustomScrollView` + `SliverList.builder`
    懒构建；`prefer_const_constructors` 系列 lint 全量落地。
- **v0.9.2**：图书详情/编辑页 UI 重构——详情页改为封面 + 评分卡 + 双列信息卡 + 简介/感悟的卡片式布局；编辑页改为顶栏取消/保存胶囊 + 分组卡片表单，阅读进度由滑杆改为「已读页数 / 总页数」输入（0 页自动想读、填满自动完成），底部删除按钮仅编辑模式显示。新增 `publisher`（出版社）字段并接入联网检索回填。修复保存时序缺陷：回退阅读进度的二次确认原在 loading 态之后触发，导致按钮先转圈再弹确认框，已前置到 loading 之前。
- **v0.9.1**：修复图书/影视删除后返回列表页不刷新的 bug（UnmodifiableListView 动态视图导致 context.select 误判无变化）；个人资料编辑弹窗统一为 BottomSheet 风格；图书数据源联网补全增强：新增 BookDataSource.getBookDetail 详情接口，Google Books/OpenLibrary 支持分类/页数/简介回填，搜索结果填充后自动收起列表并显示「已填充」状态，自定义数据源支持 detailUrlTemplate 配置（未填时优雅降级）；自定义影视数据源同步支持详情接口配置。
- **v0.9.0**：个人统计页三段式仪表盘重构——年度指标栏 + GitHub 风格打卡热力图（30 天/季度/年度切换）、类型偏好环形图 + 评分分布柱状图（纯 CustomPainter）、在读进度条 + 年度五星封面墙；年度报告页（最晚读完 / 最快阅读周 / 打破偏好的那本）。移除内置演示种子数据：首启为空库，由用户自行录入（测试与 Web 预览仍用 mock 数据）。
- **v0.8.2**：自定义数据源智能解析（支持用户自行添加接口配置）；图片本地缓存（避免重复下载）；WebDAV 兼容性修复
- **v0.8.1**：优化个人页档案展示弹层体验；电影编辑页片长输入框回显修复；数据源全局请求节流防 429；图书默认源从 Google Books 换为 OpenLibrary（免 Key 无速率限制）；OpenLibrary 数据源实现；图书/电影编辑页公共组件去重（M4/M5）；代码审查报告收尾（规范细节/依赖清理/测试隔离）。
- **v0.8.0**：深浅双主题、离线优先、书籍电影双轨记录、WebDAV 云同步、联网信息补全。

## 架构

采用**四层组件化 + MVVM**。依赖方向严格单向——**上层可依赖下层，反之禁止**：

```
app (3)  →  business (2)  →  component (1)  →  foundation (0)
```

| 层 | 职责 | 可依赖 |
|---|---|---|
| `app/` | 主工程层：全局配置（主题 / 转场）与根容器 | 以下各层 |
| `business/` | 业务层：按**业务模块**拆分，模块内 MVVM 分层 | `component` / `foundation` |
| `component/` | 功能组件层：跨模块复用的 UI 组件与设计令牌 | `foundation` |
| `foundation/` | 基础层：日志 / 网络 / 存储 / 工具，**不认识任何业务模型** | 无 |

**硬规则**：

1. **page 命名**：固定 `xxx_page.dart` → 类 `XxxPage`。
2. **view 命名**：按功能命名（`xxx_card.dart` / `xxx_sheet.dart` / `xxx_picker.dart`），
   **禁止用 `widget` 关键字**命名文件或类。
3. **设计令牌**位于 `component/theme/app_palette.dart`——它被 40+ 个下层文件引用，
   放 `app/` 会造成大面积反向依赖。
4. `foundation/` 不得 import 任何 `business/` 符号（含 model）。若某文件需要业务模型，
   说明它是业务仓储 / 服务，应移入对应 business 模块。
5. `component/` 不得 import `business/`。需要业务能力时，在组件层声明**契约 + InheritedWidget**，
   由 app 层在 `MaterialApp` 之上注入（参考 `component/media/local_media_scope.dart`）。
6. business 模块之间应尽量解耦。当前仍有跨模块引用（根因：`LibraryProvider` + `LibraryStore`
   承担了 ViewModel + Repository + Store 三重职责），**新代码不要再增加跨模块引用**。

## 目录结构

```
lib/（96 个 .dart 文件）

├── main.dart                          # 入口：Provider 装配 + 全局异常兜底 + 主题与转场接线
│
├── app/                               # ① 主工程层
│   ├── config/
│   │   ├── app_theme.dart             # 由色板生成 ThemeData（Material 3）
│   │   └── fade_slide_transitions.dart # 全局页面转场：淡入 + 微上浮
│   └── pages/
│       └── root_page.dart             # 根容器：底部导航（仪表盘 / 书籍 / 电影 / 个人）
│
├── business/                          # ② 业务层 —— 按模块拆分
│   ├── library/                       # 书影库（31 文件）
│   │   ├── model/
│   │   │   ├── book.dart              # Book + BookStatus + kBookCategories（含 isbn）
│   │   │   ├── movie.dart             # Movie + MovieStatus + kMovieCategories（含片长 / 剧照 / 演员）
│   │   │   ├── actor.dart             # Actor 实体（独立集合 actors.json）
│   │   │   ├── cast_item.dart         # 演员展示条目（统一「Movie.cast 快照」与「本地 Actor 实体」）
│   │   │   ├── edit_result.dart       # 编辑页返回结果标识
│   │   │   └── mock_data.dart         # 演示种子（12 书 / 8 影）：仅测试与预览使用，生产首启为空库
│   │   ├── repository/
│   │   │   ├── library_store.dart     # JSON 存储：原子写 / 合并写 / schemaVersion / 图片管理
│   │   │   ├── persistence.dart       # 启动装配门面（条件导入）
│   │   │   ├── persistence_io.dart    # 手机 / 桌面实现（dart:io + path_provider）
│   │   │   └── persistence_stub.dart  # Web 回退（内存存储）
│   │   ├── page/
│   │   │   ├── books_page.dart        # 图书库列表（搜索 + 分类 / 状态筛选，列表 / 网格切换）
│   │   │   ├── movies_page.dart       # 电影库列表
│   │   │   ├── book_detail_page.dart  # 图书详情（封面 + 评分卡 + 信息卡 + 简介 / 感悟）
│   │   │   ├── book_edit_page.dart    # 图书新增 / 编辑（快速检索回填、ISBN、分类联想、阅读进度）
│   │   │   ├── movie_detail_page.dart # 电影详情（头部水平卡 + 演职员 + 剧照）
│   │   │   ├── movie_edit_page.dart   # 电影新增 / 编辑（检索回填、演员 / 类型联想、评分、海报）
│   │   │   ├── movie_stills_page.dart # 剧照与海报全量页（Tab：全部 / 剧照 / 海报）
│   │   │   └── actor_detail_page.dart # 演员详情（简介 + 参演作品反查）
│   │   ├── view/
│   │   │   ├── book_detail_view.dart  # 详情页组件（EditPill / 评分卡 / 简介感悟折叠）
│   │   │   ├── movie_detail_view.dart # 详情页组件（CastAvatar / 剧照横滑条 / 信息卡）
│   │   │   ├── actor_detail_view.dart # 演员页组件（头像编辑 / 作品条目）
│   │   │   ├── cast_bottom_sheet.dart # 演职员表弹层（分组 + 搜索，Sliver 懒构建）
│   │   │   ├── detail_common.dart     # 详情页公共组件（InfoChip / ExpandableSynopsis）
│   │   │   ├── edit_form_view.dart    # 编辑页公共表单（分组标题 / 文本框 / 文本提示弹层）
│   │   │   ├── quick_search_panel.dart # 编辑页「快速检索」结果列表
│   │   │   ├── filter_dropdown.dart   # 通用筛选下拉（候选动态取自已有数据）
│   │   │   ├── book_list_card.dart    # 图书列表卡（竖版封面 + 状态徽标 + 进度角标）
│   │   │   ├── search_bar_view.dart   # 暗色圆角搜索栏
│   │   │   ├── rating_stars.dart      # 五星评分展示（支持小数）
│   │   │   └── star_rating_picker.dart # 交互式评分选择器（拖动打分 + 跨档触感）
│   │   └── view_model/
│   │       └── library_provider.dart  # 全局书影库状态（ChangeNotifier 单一数据源）
│   │
│   ├── data_source/                   # 联网信息补全（15 文件）
│   │   ├── model/
│   │   │   ├── data_source.dart       # 数据源配置 / 搜索结果 / 详情模型（JSON 往返）
│   │   │   └── deploy_guide.dart      # 「自建部署指南」Markdown 文案常量
│   │   ├── page/
│   │   │   └── data_source_page.dart  # 数据源管理（影视 / 图书两区，默认源单选、连接测试）
│   │   ├── service/
│   │   │   ├── data_source_interface.dart       # BookDataSource / MovieDataSource 抽象 + ConfigField
│   │   │   ├── data_source_manager.dart         # 数据源注册表（预设 / 默认源 / 配置与凭据存取）
│   │   │   ├── data_source_secure_credentials.dart # 数据源凭据安全存储
│   │   │   ├── book_result_merger.dart          # 多源聚合的搜索结果去重 / 合并
│   │   │   ├── book_category_mapper.dart        # 书籍分类中文化映射
│   │   │   └── data_sources/
│   │   │       ├── tmdb_data_source.dart        # TMDB 影视源（搜索 / 详情 / 演职员 / 剧照）
│   │   │       ├── open_library_data_source.dart # OpenLibrary 图书源（免 Key 无速率限制，默认）
│   │   │       ├── google_books_data_source.dart # Google Books 图书源
│   │   │       └── custom_data_source.dart      # 自定义数据源（用户接口配置 + 智能解析）
│   │   ├── view/
│   │   │   ├── data_source_view.dart  # 源列表项 / 配置弹层
│   │   │   └── data_source_guide_sheet.dart # 自建部署指南弹层（Markdown 渲染）
│   │   └── view_model/
│   │       └── data_source_provider.dart # 联网检索状态（防抖 / 结果缓存 / TTL+LRU / 错误兜底）
│   │
│   ├── stats/                         # 统计与图表（11 文件）
│   │   ├── model/
│   │   │   ├── stats.dart             # BookStats / MovieStats（聚合指标，无 mock 默认值）
│   │   │   └── statistics.dart        # 三段式仪表盘聚合：热力图 / 类型占比 / 评分分布 / 年度指标与年报亮点
│   │   ├── page/
│   │   │   ├── dashboard_page.dart    # 仪表盘主页（统计 + 当前任务 + 阅读 / 观影网格）
│   │   │   ├── personal_stats_page.dart # 个人统计（三段式仪表盘）
│   │   │   └── annual_report_page.dart  # 年度报告（最晚读完 / 最快阅读周 / 打破偏好）
│   │   ├── view/
│   │   │   ├── stats_card.dart        # 统计双卡（阅读渐变环 / 观影均分徽章，等高对齐）
│   │   │   ├── heatmap_calendar.dart  # GitHub 风格打卡热力图（周列 × 星期行，四级着色）
│   │   │   ├── chart_view.dart        # DonutChart 环形图 + RatingBarChart 柱状图（纯 CustomPainter）
│   │   │   ├── personal_stats_view.dart # 统计页组件（年度指标栏 / 在读进度 / 封面墙）
│   │   │   ├── dashboard_view.dart    # 仪表盘组件（区块标题 / 空态卡 / 网格）
│   │   │   └── section_header.dart    # 区块标题（trailing 支持点击跳转）
│   │
│   ├── sync/                          # 云同步与备份（9 文件）
│   │   ├── model/
│   │   │   └── sync_settings.dart     # SyncSettings（WebDAV 地址 / 自动同步偏好，不含密码）
│   │   ├── page/
│   │   │   └── data_sync_page.dart    # 数据同步（WebDAV 云同步 + 本地导出导入）
│   │   ├── service/
│   │   │   ├── webdav_client.dart     # WebDAV 最小客户端（PROPFIND / MKCOL / PUT / GET，可注入 fake）
│   │   │   ├── backup_service.dart    # 备份打包 / 还原（JSON 单文件 / 含图 ZIP；含 data_sources.json）
│   │   │   ├── merge_engine.dart      # 记录级 LWW 合并引擎（纯函数，可单测）
│   │   │   ├── snapshot_service.dart  # 同步前本地快照兜底（滚动保留最近数份）
│   │   │   └── secure_storage_service.dart # WebDAV 凭据安全存储（Keystore / Keychain）
│   │   ├── view/
│   │   │   └── data_sync_view.dart    # 同步页组件（配置卡 / 操作卡 / 合并摘要）
│   │   └── view_model/
│   │       └── sync_provider.dart     # 同步状态与动作（上传 / 恢复 / 自动同步）
│   │
│   └── profile/                       # 个人中心与日志（5 文件）
│       ├── model/
│       │   └── user_profile.dart      # UserProfile（昵称 / 签名 / 头像 / 主题偏好）
│       ├── page/
│       │   ├── profile_page.dart      # 个人中心（档案 / 主题三选 / 统计·数据源·同步·日志入口）
│       │   └── error_log_page.dart    # 错误日志（分级统计 / 列表 / 导出 / 复制 / 清空）
│       └── view/
│           ├── profile_view.dart      # 个人页组件（ProfileCard / StatSummary / SettingItem）
│           └── error_log_view.dart    # 日志页组件（SummaryHeader / HintBar / LogTile / ActionBar）
│
├── component/                         # ③ 功能组件层 —— 跨模块复用
│   ├── common/
│   │   ├── grid_item_card.dart        # 网格媒体卡（支持 onTap / onLongPress）
│   │   └── progress_ring.dart         # CustomPainter 圆形进度环（动画）
│   ├── media/
│   │   ├── model/media_ref.dart       # MediaRef（本地文件 / 网络图引用，双空即占位）
│   │   ├── media_cover.dart           # 媒体图三态展示（本地 / 网络 / 占位）
│   │   ├── media_tile.dart            # 当前任务横向卡片
│   │   ├── cover_placeholder.dart     # 离线封面（渐变 + 字标，无网络依赖）
│   │   └── local_media_scope.dart     # 本地图解析契约（组件层定义、app 层注入实现）
│   └── theme/
│       └── app_palette.dart           # 全局色板 ThemeExtension（dark / light）+ context.colors
│
└── foundation/                        # ④ 基础层 —— 不认识任何业务
    ├── logger/
    │   ├── app_logger.dart            # 日志中枢：分级 + 内存环形缓冲 + 增量计数 + 可订阅（ChangeNotifier）
    │   ├── log_sink.dart              # 落盘后端契约（按平台接线）
    │   ├── log_sink_io.dart           # 手机 / 桌面：写 logs/moying.log，写链串行化 + 2MB 滚动
    │   ├── log_sink_stub.dart         # Web：no-op（仅内存缓冲）
    │   ├── log_exporter.dart          # 导出契约（写本地 .txt 后交系统分享面板）
    │   ├── log_exporter_io.dart       # 手机 / 桌面实现
    │   └── log_exporter_stub.dart     # Web 实现（不落盘，直接交平台分享）
    ├── network/
    │   ├── cover_headers.dart         # 封面图请求的 Host 判定与 Referer 头生成
    │   └── http_retry.dart            # 分层超时（建连 / 首字节 / 整体）+ 一次重试
    ├── storage/
    │   └── secure_store.dart          # 凭据读写最小接口 + Keychain / Keystore 实现 + 内存 fake
    └── utils/
        ├── image_pick_service.dart    # 选图服务抽象（image_picker）
        ├── image_compress_service.dart # 单图压缩 / 上限（magic bytes 探活 → 缩放 → 重编码）
        └── ttl_cache.dart             # 进程内 TTL + LRU 缓存（检索结果复用）
```

## 测试

`test/` 下 **33 个测试文件、共 420 个用例**，覆盖：

- **模型与存储**：JSON 序列化往返、`LibraryStore` 原子写 / 合并写 / schemaVersion、图片管线与压缩上限
- **状态层**：`Provider` 持久化与并发写、日志中枢的环形缓冲 / 递增计数 / 写链并发 / 截断对齐
- **联网检索**：数据源配置与凭据、结果缓存（TTL+LRU）、多源聚合去重、自定义源智能解析、
  字段回填回归、弱网分层超时与重试、封面 Host 判定
- **同步**：备份往返（JSON / 含图 ZIP）、WebDAV PROPFIND、LWW 合并引擎、快照兜底
- **统计聚合**：热力图去重规则 / 类型占比 / 评分分桶 / 年报亮点
- **UI 流程**：联想输入、筛选恢复、卡片长按跳转、列表删除后刷新、仪表盘空态点击直达新增页、
  演职员表与剧照页、星级拖动、错误日志页，以及窄屏布局回归

## 特性说明

- **深浅双主题**：色板以 `ThemeExtension` 注入，取色统一走 `context.colors.xxx`；
  深色为原始设计（`#0F0F0F` 背景 / `#1A1A2E` 卡片），浅色为其反推（近白背景 / 纯白卡片 / 深灰文字）。
  主题偏好写入 `profile.json`，重启保持；可选「跟随系统」。
- **封面可降级**：支持本地图片与网络图，无封面或加载失败时回退到 HSL 渐变 + 字标占位，断网也不破版。
- **状态管理**：Provider（`ChangeNotifier`）作单一数据源，UI 只读 Provider，写操作由 Provider 统一落盘；
  列表页用 `context.select` 收窄订阅，避免无关 rebuild。
- **圆形进度环**：`CustomPainter` + `SweepGradient` + 900ms 缓动动画。
- **联想式录入**：书籍分类与电影剧情类型均为「候选点选 + 自由输入」的多选标签；
  电影导演失焦后自动挂到演员区首位。
- **错误日志**：分级记录 + 内存环形缓冲（500 条）+ 落盘滚动（2MB），启动时读回历史，
  「上次启动就崩」的问题下次启动仍能看到。**只记错误 / 警告 / 崩溃与请求失败，
  不记录浏览行为、不上传任何数据**；隐私约束见 `AppLogger` 文档注释。

## 已实现

- **本地持久化**：JSON 文件存储（`LibraryStore`），原子写入（`.tmp` + rename）、`schemaVersion` 校验、
  同一 tick 内的多次写操作自动合并、写链串行化避免并发覆盖；用户档案独立存于 `profile.json`
- **书籍 / 电影 / 演员全链路增删改查**：三套编辑页 + 详情页；删除演员时若仍被影片引用会拒绝删除并列出引用来源
- **搜索与筛选**：关键词搜索、分类 / 类型 / 状态下拉筛选（候选动态取自已有数据，含用户自定义项）、详情页点击作者即跳转并预填筛选条件
- **图片管理**：相册选图 / 粘贴网络链接 / 移除封面，图片复制进应用私有目录，压缩至上限内落盘，
  更换或删除时自动回收孤儿文件
- **演职员与剧照**：电影详情页「主创 / 演员」入口打开分组演职员表（可搜索）；
  「剧照 → 全部」进入剧照与海报全量页（Tab 切换），剧照落盘缓存、再次进入零网络请求；
  点击演员进演员页，可反查其全部参演作品
- **仪表盘真实数据联动**：统计双卡、当前任务、阅读与观影网格全部由书影数据实时计算，含空态兜底；
  书库 / 影库为空时，空态卡整卡可点击，直达「添加图书 / 添加电影」页；「查看全部」跳转对应 Tab
- **个人中心**：昵称 / 签名 / 头像编辑（头像卡片点击为只读展示，「编辑资料」行进入编辑）、数据统计页、主题三选
- **三段式仪表盘统计（个人统计页）**：顶部年度指标栏（年度读书 X 本 · 观影 Y 部 · 观影时长 Z 小时）+
  GitHub 风格打卡热力图（30 天 / 季度 / 年度切换，计数规则为「同一实体同一天去重 1 次、
  不同实体累加」，0 / 1 / 2 / 3+ 四级着色，聚合书 createdAt / startedAt / finishedAt 与
  电影 watchDate）；中部类型偏好环形图（Top5 + 百分比图例）与 1~5 星评分分布柱状图
  （均纯 `CustomPainter` 实现，零第三方依赖）；底部在读进度条（默认 3 本 + 底部弹层「查看全部」）、
  年度五星封面墙与年报入口；每个区块均有空态兜底文案
- **年度报告**：年度快照页（`annual_report_page.dart`）——年度总览渐变卡
  （读完本数 / 页数 / 观影时长 / 年度偏好分类）、最晚读完的一本书、阅读页数最多的一周、
  打破偏好的那一本（分类与整体最高频分类不同的当年完成书）；数据实时计算，记录变化即更新
- **数据同步 / 备份**：WebDAV 云同步（坚果云 / Nextcloud 等标准网盘）——4 项服务器配置 +
  测试连接、立即备份 / 从云端恢复（恢复前二次确认 + 本地快照兜底）、启动时自动同步（可限 Wi-Fi、
  节流 1 小时）、备份可选包含本地图片（JSON 单文件 / 含图 ZIP）；双端冲突走**记录级 LWW 合并**
  （按 id 并集、`updatedAt` 新者胜），合并前后各留一份本地快照可回退；本地导出改为弹「保存位置选择器」
  由用户自选落盘路径（含图开关跟随同步偏好，开 → ZIP、关 → JSON），断网环境的保底手段。
  凭据存系统安全存储（Keystore / Keychain），`settings.json` 不含密码；Web 平台隐藏该功能入口
- **联网信息补全（可选）**：个人中心「数据源管理」——影视源内置 TMDB，图书源内置 OpenLibrary（默认）
  与 Google Books。**接入第三方站点无需内置预设**：自定义数据源填 Base URL + API Key 即可，
  返回 JSON 由智能解析兜底（递归找数据列表 + 中英文字段别名映射，支持数组 / `{data:[…]}` /
  `{results:[…]}` 等常见结构），豆瓣、Bangumi 等站点走这条路径即可；页面内另附
  「自建部署指南」（Markdown 教程，含 GitHub + Render 免费托管示例）
  可添加多个并单选默认，支持连接测试与配置编辑；书籍 / 电影编辑页顶部「快速检索」输入名称即
  联网搜索（500ms 防抖 + TTL/LRU 结果缓存），点选结果自动回填表单（图书含 ISBN 与封面，
  电影含导演 / 主演 / 片长 / 类型 / 海报），保存时记录溯源 `source`。图书检索走**多源聚合**
  （结果去重合并 + 分类中文化）；封面请求按 Host 补 `Referer` 绕过防盗链，并带镜像回退、
  分层超时与一次重试。TMDB 的 API Key 存系统安全存储；数据源配置随 `data_sources.json`
  一并纳入备份 / 恢复（schemaVersion 2，向后兼容），云端恢复后自动重载并提示缺失凭据的源。
  未配置或断网时检索块自动隐藏，不影响手动录入
- **错误日志（个人 → 错误日志）**：分级 / 分类记录应用错误与请求失败，覆盖全局未捕获异常
  （框架异常 + 异步异常）、网络重试耗尽、数据源取数失败、同步与备份异常；页面提供分级统计、
  倒序列表、**导出**（写本地 `.txt` 后交系统分享面板）、**复制全部**（剪贴板）与**清空**（二次确认）。
  数据只在本机，用户主动导出后自行反馈给开发者

## 路线图（未实现）

- [ ] 年度目标设定：设定年度读书 / 观影目标并在统计仪表盘追踪完成度
  （图表统计与年报已实现，目标追踪尚未开始）
- [ ] 仪表盘顶栏搜索 / 通知按钮接上功能（当前为空实现）
- [ ] 业务模块解耦：拆分 `LibraryProvider` / `LibraryStore` 的 ViewModel + Repository + Store
  三重职责，消除跨业务模块引用；编辑页抽出独立 Controller 以便单测

## 开发约定

- **依赖方向**：严格遵守 `app → business → component → foundation` 单向依赖。
  提交前可跑架构自检脚本核对反向依赖、命名与 `part` 残留。
- **取色**：一律 `context.colors.xxx`，禁止静态常量色（主题切换时 const 子树不会重绘）。
- **命名**：页面 `XxxPage` / `xxx_page.dart`；视图组件按功能命名，禁用 `widget` 关键字。
- **同步改测试**：改动 `LibraryStore`、合并引擎、数据源解析等核心逻辑时同步补测试；
  查询类断言以 `flutter analyze`（0 issue）与全量 `flutter test` 全绿为准。
- **格式门禁**：CI 中的 `dart format --set-exit-if-changed` 默认注释；如需开启，先在本机执行
  `dart format .` 再取消 `.github/workflows/ci.yml` 中对应步骤的注释。

## 开源许可

本项目基于 [MIT License](./LICENSE) 开源，Copyright (c) 2026 Afyery。
