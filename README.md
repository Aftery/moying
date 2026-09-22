# 墨影 MoYing 🎬📚

**简体中文** | [English](./README_EN.md) | [日本語](./README_JA.md)

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
flutter test          # 单元与 widget 测试（当前 35 个文件、490 个用例）
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
  - **架构重构**：按四层组件化 + MVVM 规范重整工程——文件归入
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
    （滚动保留最近数份，合并出问题可回退）；同步 / 恢复 / 导出全链路互斥 + 恢复前冲刷待写数据；
    JSON 云备份可见性修复（`.zip` / `.json` 双扩展名均可列出与恢复）。
  - **图片**：新增单图压缩与上限（magic bytes 探活 → 等比缩放到长边上限 → 重编码，控制在 5MB 内落盘）。
  - **编辑页**：评分只由用户手动打（取消自动填充）；星级选择器支持拖动打分 + 跨档触感反馈；
    手动录入的书支持「联网自动找封面」；电影详情头部改水平卡片布局，个人模块弹窗高度统一。
  - **性能**：演职员表与演员作品年表由 eager 全量构建改 `CustomScrollView` + `SliverList.builder`
    懒构建；`prefer_const_constructors` 系列 lint 全量落地。
  - **v0.9.3 后续开发批次**（同 tag 前追加）：
    - **模块解耦收口**：业务模块间同级引用 **49 → 0**——共享内核下沉 `business/shared/`
      （7 个跨模块 DTO + `LibraryStore` 共享仓储 + 分类映射器）、新增 `LibraryFacade` /
      `DataSourceFacade` 门面接口（其他模块只依赖接口、app 层注册同一实例）、
      跨模块跳页改集中路由（`AppRoutes` + `app/router.dart`）。
    - **编辑页抽 Controller**：`BookEditController` / `MovieEditController`（ChangeNotifier），
      编辑逻辑可在无 Widget 树前提下单测，新增 69 个单元测试。
    - **超长函数清零**：30 个 ≥80 行函数全部拆分（最长 194 → 44 行）。
    - **文案常量层**：`foundation/constants/app_strings.dart` 收敛 53 处跨页复用文案。
    - **排版层级**：`app/config/app_typography.dart` 定义 `AppType` 字号常量（新代码约定）。
    - **健壮性**：`Movie.copyWith` 的 emoji 改用哨兵（修复编辑保存丢占位符）；
      数据源异常语义结构化（`DataSourceErrorKind`，状态判定不再匹配中文文案）；
      备份解析边界归一（类型错误统一转 `BackupException`）；损坏的 settings / data_sources
      配置隔离并回退默认值。
    - **杂项**：6 处弹层拖拽指示条收敛为 `SheetGrabber`；渐变卡透明度语义化（`_OnGradient`）；
      封面查找失败提示按 ISBN 是否为空分流；延迟 seed（生产启动不再复制演示数据）；
      AppLogger 增量计数 + 日志页订阅。
- **v0.9.2**：图书详情/编辑页 UI 重构——详情页改为封面 + 评分卡 + 双列信息卡 + 简介/感悟的卡片式布局；编辑页改为顶栏取消/保存胶囊 + 分组卡片表单，阅读进度由滑杆改为「已读页数 / 总页数」输入（0 页自动想读、填满自动完成），底部删除按钮仅编辑模式显示。新增 `publisher`（出版社）字段并接入联网检索回填。修复保存时序缺陷：回退阅读进度的二次确认原在 loading 态之后触发，导致按钮先转圈再弹确认框，已前置到 loading 之前。
- **v0.9.1**：修复图书/影视删除后返回列表页不刷新的 bug（UnmodifiableListView 动态视图导致 context.select 误判无变化）；个人资料编辑弹窗统一为 BottomSheet 风格；图书数据源联网补全增强：新增 BookDataSource.getBookDetail 详情接口，Google Books/OpenLibrary 支持分类/页数/简介回填，搜索结果填充后自动收起列表并显示「已填充」状态，自定义数据源支持 detailUrlTemplate 配置（未填时优雅降级）；自定义影视数据源同步支持详情接口配置。
- **v0.9.0**：个人统计页三段式仪表盘重构——年度指标栏 + GitHub 风格打卡热力图（30 天/季度/年度切换）、类型偏好环形图 + 评分分布柱状图（纯 CustomPainter）、在读进度条 + 年度五星封面墙；年度报告页（最晚读完 / 最快阅读周 / 打破偏好的那本）。移除内置演示种子数据：首启为空库，由用户自行录入（测试与 Web 预览仍用 mock 数据）。
- **v0.8.2**：自定义数据源智能解析（支持用户自行添加接口配置）；图片本地缓存（避免重复下载）；WebDAV 兼容性修复
- **v0.8.1**：优化个人页档案展示弹层体验；电影编辑页片长输入框回显修复；数据源全局请求节流防 429；图书默认源从 Google Books 换为 OpenLibrary（免 Key 无速率限制）；OpenLibrary 数据源实现；图书/电影编辑页公共组件去重（M4/M5）；代码审查报告收尾（规范细节/依赖清理/测试隔离）。
- **v0.8.0**：深浅双主题、离线优先、书籍电影双轨记录、WebDAV 云同步、联网信息补全。

## 架构

采用**四层组件化 + MVVM**。依赖方向严格单向——**上层可依赖下层，反之禁止**：

```
app (5)  →  business {shared 内核} (75)  →  component (9)  →  foundation (16)
```

| 层 | 职责 | 可依赖 |
|---|---|---|
| `app/` | 主工程层：全局配置（主题 / 转场 / 排版）、根容器、**全局路由表** | 以下各层 |
| `business/` | 业务层：按**业务模块**拆分，模块内 MVVM 分层；`shared/` 为模块间共享内核 | `shared` / `component` / `foundation` |
| `component/` | 功能组件层：跨模块复用的 UI 组件与设计令牌 | `foundation` |
| `foundation/` | 基础层：日志 / 网络 / 存储 / 工具 / **路由名与文案常量**，不认识任何业务模型 | 无 |

**硬规则**：

1. **page 命名**：固定 `xxx_page.dart` → 类 `XxxPage`。
2. **view 命名**：按功能命名（`xxx_card.dart` / `xxx_sheet.dart` / `xxx_picker.dart`），
   **禁止用 `widget` 关键字**命名文件或类。
3. **设计令牌**位于 `component/theme/app_palette.dart`；字号层级位于
   `app/config/app_typography.dart`（`AppType`，新代码用、旧代码随触碰替换）。
4. `foundation/` 不得 import 任何 `business/` 符号（含 model）。
5. `component/` 不得 import `business/`。需要业务能力时，在组件层声明**契约 + InheritedWidget**，
   由 app 层在 `MaterialApp` 之上注入（参考 `component/media/local_media_scope.dart`）。
6. **业务模块之间零直接引用**（v0.9.3 达成）：模块间协作只允许两条路——
   - 依赖 `business/shared/` 共享内核：纯 DTO（`model/`）、共享仓储（`repository/library_store.dart`）、
     门面接口（`library_facade.dart` / `data_source_facade.dart`）与纯工具；
   - 跨模块跳页走 `Navigator.pushNamed(AppRoutes.xxx)`（路由名常量在
     `foundation/constants/app_routes.dart`），**页面构建集中在 `app/router.dart`**，
     禁止 import 兄弟模块的 Page 类。
7. **门面注册**：`LibraryProvider` / `DataSourceProvider` 分别实现 `LibraryFacade` /
   `DataSourceFacade`；app 层以 `ListenableProvider<门面>.value` 注册**同一实例**
   （用 `ListenableProvider` 而非 `Provider`，才会订阅通知、`context.select` 才会重建）。

## 目录结构

```
lib/（106 个 .dart 文件，约 25,000 行）

├── main.dart                          # 入口：Provider 装配（含门面双注册）+ 全局异常兜底 + 主题与转场接线
│
├── app/                               # ① 主工程层（5 文件）
│   ├── config/
│   │   ├── app_theme.dart             # 色板 → ThemeData（Material 3）
│   │   ├── app_typography.dart        # AppType 字号层级常量（排版唯一来源）
│   │   └── fade_slide_transitions.dart # 全局页面转场：淡入 + 微上浮
│   ├── pages/
│   │   └── root_page.dart             # 根容器：底部导航（仪表盘 / 书籍 / 电影 / 个人）
│   └── router.dart                    # 全局路由表：AppRoutes 各路由的页面构建集中于此
│
├── business/                          # ② 业务层 —— 按模块拆分 + 共享内核（75 文件）
│   ├── shared/                        # 共享内核（11 文件）：模块间唯一依赖点
│   │   ├── model/                     # 跨模块共享 DTO（7）：book / movie / actor / stats /
│   │   │                              #   user_profile / sync_settings / data_source
│   │   ├── repository/
│   │   │   └── library_store.dart     # JSON 存储：原子写 / 合并写 / schemaVersion / 图片管理
│   │   ├── library_facade.dart        # 书影库门面契约（stats / profile / sync 消费）
│   │   ├── data_source_facade.dart    # 数据源门面契约（library 编辑页 / sync 消费）
│   │   └── book_category_mapper.dart  # 书籍分类中文化映射（纯函数，零依赖）
│   │
│   ├── library/                       # 书影库（29 文件）
│   │   ├── model/                     # 模块内模型（3）：cast_item / edit_result / mock_data
│   │   ├── repository/                # 启动装配（3）：persistence{,_io,_stub}（条件导入，Web 回退内存）
│   │   ├── page/                      # 8 个页面：books / movies / book_detail / book_edit /
│   │   │                              #   movie_detail / movie_edit / movie_stills / actor_detail
│   │   ├── view/                      # 12 个视图组件：详情 / 编辑表单 / 弹层 / 卡片 / 评分等
│   │   └── view_model/                # library_provider（全局状态）+ book/movie_edit_controller
│   │
│   ├── data_source/                   # 联网信息补全（13 文件）
│   │   ├── model/deploy_guide.dart    # 「自建部署指南」Markdown 文案常量
│   │   ├── page/data_source_page.dart # 数据源管理（影视 / 图书两区，默认源单选、连接测试）
│   │   ├── service/                   # 接口抽象 / 注册表 / 凭据存储 / 结果合并 + 4 个实现
│   │   │                              #   （TMDB / OpenLibrary / Google Books / 自定义智能解析）
│   │   ├── view/                      # 源列表与配置弹层 / 部署指南弹层
│   │   └── view_model/                # data_source_provider：实现 DataSourceFacade 门面
│   │
│   ├── stats/                         # 统计与图表（10 文件）
│   │   ├── model/statistics.dart      # 三段式仪表盘聚合（热力图 / 类型占比 / 评分分布 / 年报）
│   │   ├── page/                      # dashboard / personal_stats / annual_report
│   │   └── view/                      # stats_card / heatmap_calendar / chart_view 等图表组件
│   │
│   ├── sync/                          # 云同步与备份（8 文件）
│   │   ├── page/data_sync_page.dart   # 数据同步（WebDAV 云同步 + 本地导出导入）
│   │   ├── service/                   # webdav_client（PROPFIND/MKCOL/PUT/GET）/ backup /
│   │   │                              #   merge_engine（LWW）/ snapshot / secure_storage
│   │   ├── view/data_sync_view.dart   # 同步页组件（配置卡 / 操作卡 / 合并摘要）
│   │   └── view_model/sync_provider.dart # 同步动作互斥执行（上传 / 恢复 / 自动同步）
│   │
│   └── profile/                       # 个人中心与日志（4 文件）
│       ├── page/                      # profile_page / error_log_page
│       └── view/                      # profile_view / error_log_view
│
├── component/                         # ③ 功能组件层 —— 跨模块复用（9 文件）
│   ├── common/                        # grid_item_card / progress_ring / sheet_grabber
│   ├── media/                         # media_cover / media_tile / cover_placeholder /
│   │                                  #   local_media_scope（契约注入）/ model/media_ref
│   └── theme/app_palette.dart         # 全局色板 ThemeExtension（dark / light）+ context.colors
│
└── foundation/                        # ④ 基础层 —— 不认识任何业务（16 文件）
    ├── constants/                     # app_routes（路由名）/ app_strings（跨页文案）
    ├── logger/                        # 日志中枢：分级 + 环形缓冲 + 写链串行化 + 滚动 2MB
    │                                  #   （io / stub 按平台接线）+ 导出（io / stub）
    ├── network/                       # cover_headers（Referer）/ http_retry（分层超时 + 重试）
    ├── storage/secure_store.dart      # 凭据读写最小接口 + Keychain / Keystore 实现
    └── utils/                         # date_format / image_pick / image_compress / ttl_cache
```

## 测试

`test/` 下 **35 个测试文件、共 490 个用例**，覆盖：

- **模型与存储**：JSON 序列化往返、`LibraryStore` 原子写 / 合并写 / schemaVersion、图片管线与压缩上限
- **状态层**：`Provider` 持久化与并发写、日志中枢的环形缓冲 / 递增计数 / 写链并发 / 截断对齐
- **编辑控制器**：`BookEditController` / `MovieEditController` 无 Widget 树单测
  （表单归一 / 导演↔演员联动 / 检索回填 / 哨兵语义）
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
  列表页用 `context.select` 收窄订阅，避免无关 rebuild。跨模块消费走门面接口
  （`LibraryFacade` / `DataSourceFacade`），依赖抽象而非兄弟实现。
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

## 开发约定

- **依赖方向**：严格遵守 `app → business → component → foundation` 单向依赖。
- **模块解耦**：业务模块间零直接引用——跨模块数据依赖走 `business/shared/`
  （DTO / 仓储 / 门面接口），跨模块跳页走 `AppRoutes` 路由名（页面构建集中在 `app/router.dart`）；
  禁止 import 兄弟模块的 page / view_model。
- **取色**：一律 `context.colors.xxx`，禁止静态常量色（主题切换时 const 子树不会重绘）；
  字号新代码用 `AppType` 常量。
- **命名**：页面 `XxxPage` / `xxx_page.dart`；视图组件按功能命名，禁用 `widget` 关键字。
- **同步改测试**：改动 `LibraryStore`、合并引擎、数据源解析等核心逻辑时同步补测试；
  查询类断言以 `flutter analyze`（0 issue）与全量 `flutter test` 全绿为准。
- **格式门禁**：CI 中的 `dart format --set-exit-if-changed` 默认注释；如需开启，先在本机执行
  `dart format .` 再取消 `.github/workflows/ci.yml` 中对应步骤的注释。

## 开源许可

本项目基于 [MIT License](./LICENSE) 开源，Copyright (c) 2026 Aftery。
