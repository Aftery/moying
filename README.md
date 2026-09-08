# 墨影 MoYing 🎬📚

一个**深浅双主题**的书籍与电影记录应用（Flutter 跨平台，数据本地持久化，离线优先——联网检索为可选增强）。

底部四标签导航：**仪表盘 / 书籍 / 电影 / 个人**。

- **仪表盘**：统计双卡（阅读平均进度环 + 观影均分徽章）、当前任务横滑区、阅读列表与我的电影网格（各 4 条，可跳转全量）
- **书籍 / 电影**：搜索 + 动态筛选 + 列表/网格切换，卡片单击进详情、长按进编辑
- **个人**：昵称 / 签名 / 头像编辑、深浅主题三选（深色 / 浅色 / 跟随系统）、数据统计、数据源管理

v0.9.0 起首启为**空库**，由用户自行录入；此后增删改全部持久化到本地。
（演示种子数据仅保留在测试中）

## 运行

```bash
# 本仓库在 Flutter 3.24.x 验证
flutter pub get
flutter run            # 选择目标设备（Android / iOS / macOS / Chrome）
```

> 国内网络可配置镜像后运行：
> ```bash
> export PUB_HOSTED_URL=https://pub.flutter-io.cn
> export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
> ```

## 验证

```bash
flutter analyze       # 静态分析（CI 以 --fatal-infos 运行，期望 0 issue）
flutter test          # 单元与 widget 测试
```

> 平台支持声明（H3）：本项目**仅支持移动端和桌面端**。
> 库代码直接依赖 `dart:io`（`File`/`Directory`），Web 目标
> 无法编译——**不要运行 `flutter build web`**，CI 也不做 Web 构建。
> `lib/data/persistence_stub` 等是历史遗留的内存回退桩，
> 不代表 Web 可运行；后续版本将逐步清理。

打包 Android 安装包：

```bash
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

## 版本历史

- **v0.9.2**：图书详情/编辑页 UI 重构——详情页改为封面 + 评分卡 + 双列信息卡 + 简介/感悟的卡片式布局；编辑页改为顶栏取消/保存胶囊 + 分组卡片表单，阅读进度由滑杆改为「已读页数 / 总页数」输入（0 页自动想读、填满自动完成），底部删除按钮仅编辑模式显示。新增 `publisher`（出版社）字段并接入联网检索回填。修复保存时序缺陷：回退阅读进度的二次确认原在 loading 态之后触发，导致按钮先转圈再弹确认框，已前置到 loading 之前。
- **v0.9.1**：修复图书/影视删除后返回列表页不刷新的 bug（UnmodifiableListView 动态视图导致 context.select 误判无变化）；个人资料编辑弹窗统一为 BottomSheet 风格；图书数据源联网补全增强：新增 BookDataSource.getBookDetail 详情接口，Google Books/OpenLibrary 支持分类/页数/简介回填，搜索结果填充后自动收起列表并显示「已填充」状态，自定义数据源支持 detailUrlTemplate 配置（未填时优雅降级）；自定义影视数据源同步支持详情接口配置。
- **v0.9.0**：个人统计页三段式仪表盘重构——年度指标栏 + GitHub 风格打卡热力图（30 天/季度/年度切换）、类型偏好环形图 + 评分分布柱状图（纯 CustomPainter）、在读进度条 + 年度五星封面墙；年度报告页（最晚读完 / 最快阅读周 / 打破偏好的那本）。移除内置演示种子数据：首启为空库，由用户自行录入（测试与 Web 预览仍用 mock 数据）。
- **v0.8.2**：自定义数据源智能解析（支持用户自行添加接口配置）；图片本地缓存（避免重复下载）；WebDAV 兼容性修复
- **v0.8.1**：优化个人页档案展示弹层体验；电影编辑页片长输入框回显修复；数据源全局请求节流防 429；图书默认源从 Google Books 换为 OpenLibrary（免 Key 无速率限制）；OpenLibrary 数据源实现；图书/电影编辑页公共组件去重（M4/M5）；代码审查报告收尾（规范细节/依赖清理/测试隔离）。
- **v0.8.0**：深浅双主题、离线优先、书籍电影双轨记录、WebDAV 云同步、联网信息补全。

## 目录结构

```
lib/（63 个 .dart 文件）

├── main.dart                     # 入口（Provider + 主题接线 + 状态栏 + 持久化）
├── config/
│   ├── app_palette.dart          # 色板 ThemeExtension（dark / light 两套）+ context.colors
│   └── app_theme.dart            # 由色板生成 ThemeData（Material 3）
├── models/
│   ├── actor.dart                # Actor
│   ├── book.dart                 # Book + BookStatus + kBookCategories（含 isbn）
│   ├── data_source.dart          # 数据源配置 / 搜索结果 / 详情模型（JSON 往返）
│   ├── media_ref.dart            # MediaRef（本地文件 / 网络图引用，双空即占位）
│   ├── movie.dart                # Movie + MovieStatus + kMovieCategories
│   ├── stats.dart                # BookStats / MovieStats（聚合指标，无 mock 默认值）
│   ├── sync_settings.dart        # SyncSettings（WebDAV 地址 / 自动同步偏好，不含密码）
│   └── user_profile.dart         # UserProfile（昵称 / 签名 / 头像 / 主题偏好）
├── data/
│   ├── library_store.dart        # JSON 存储：原子写 / 合并写 / schemaVersion / 图片管理
│   ├── mock_data.dart            # 演示种子（12 本书 / 8 部电影）：仅测试与 Web 内存预览使用，生产首启为空库
│   ├── persistence.dart          # 平台门面（条件导入）
│   ├── persistence_io.dart       # 手机 / 桌面实现（dart:io + path_provider）
│   ├── persistence_stub.dart     # Web 回退（内存存储）
│   └── statistics.dart           # 三段式仪表盘聚合：热力图 / 类型占比 / 评分分布 / 年度指标与年报亮点
├── providers/
│   ├── data_source_provider.dart # 联网检索状态（防抖搜索 / 结果缓存 / 错误兜底）
│   ├── library_provider.dart     # 书影库状态（ChangeNotifier 单一数据源）
│   └── sync_provider.dart        # 同步状态与动作（上传 / 恢复 / 自动同步）
├── services/
│   ├── data_source_interface.dart # BookDataSource / MovieDataSource 抽象 + ConfigField
│   ├── data_source_manager.dart  # 数据源注册表（预设 / 默认源 / 配置与凭据存取）
│   ├── data_sources/
│   │   ├── tmdb_data_source.dart # TMDB 影视源（搜索 / 详情 / 测连，API Key 走安全存储）
│   │   ├── open_library_data_source.dart # OpenLibrary 图书源（免 Key 无速率限制）
│   │   └── custom_data_source.dart # 自定义数据源（用户接口配置 + 智能解析）
│   ├── image_cache_service.dart  # 图片本地缓存（避免重复下载）
│   ├── image_pick_service.dart   # 选图服务抽象（image_picker）
│   ├── webdav_client.dart        # WebDAV 最小客户端（PROPFIND / MKCOL / PUT / GET，可注入 fake）
│   ├── backup_service.dart       # 备份打包 / 还原（JSON 单文件 / 含图 ZIP；含 data_sources.json）
│   └── secure_storage_service.dart # 凭据安全存储（Keystore / Keychain；WebDAV + 数据源 API Key）
├── screens/
│   ├── main_shell.dart           # 底部导航壳（IndexedStack 保持各 Tab 状态）
│   ├── dashboard_screen.dart     # 仪表盘主页（统计 + 当前任务 + 阅读 / 观影网格）
│   ├── books_screen.dart         # 图书库列表（搜索 + 分类 / 状态筛选）
│   ├── library_screens.dart      # 影库列表
│   ├── book_detail_screen.dart   # 书籍详情
│   ├── movie_detail_screen.dart  # 电影详情
│   ├── actor_detail_screen.dart  # 演员详情（含参演作品反查）
│   ├── book_edit_screen.dart     # 书籍新增 / 编辑（快速检索回填、ISBN、分类联想、阅读时间、封面）
│   ├── movie_edit_screen.dart    # 电影新增 / 编辑（快速检索回填、演员联想、类型联想、评分、海报）
│   ├── data_source_screen.dart   # 数据源管理（影视 / 图书两区，默认源单选、连接测试）
│   ├── profile_screen.dart       # 个人中心（资料编辑 / 主题三选 / 统计与数据源入口）
│   ├── data_sync_screen.dart     # 数据同步（WebDAV 云同步 + 本地导出导入）
│   ├── personal_stats_screen.dart # 个人统计（三段式仪表盘：热力图 / 偏好图表 / 在读进度）
│   └── annual_report_screen.dart # 年度报告（最晚读完 / 最快阅读周 / 打破偏好）
└── widgets/
    ├── media_cover.dart          # 媒体图三态展示（本地 / 网络 / 占位）
    ├── stats_card.dart           # 统计双卡（阅读渐变环 / 观影均分徽章，等高对齐）
    ├── progress_ring.dart        # CustomPainter 圆形进度环（动画）
    ├── rating_stars.dart         # 五星评分展示（支持小数）
    ├── star_rating_picker.dart   # 交互式评分选择器（编辑页）
    ├── media_tile.dart           # 当前任务横向卡片
    ├── book_list_card.dart       # 图书列表卡（竖版封面 + 状态徽标 + 进度角标）
    ├── grid_item_card.dart       # 网格媒体卡（支持 onTap / onLongPress）
    ├── cover_placeholder.dart    # 离线封面（渐变 + emoji，无网络依赖）
    ├── search_bar_widget.dart    # 圆角搜索栏
    ├── section_header.dart       # 区块标题（trailing 支持点击跳转）
    ├── heatmap_calendar.dart     # GitHub 风格打卡热力图（周列 × 星期行，四级着色）
    ├── chart_widgets.dart        # DonutChart 环形图 + RatingBarChart 评分柱状图（纯 CustomPainter）
    └── placeholder_view.dart     # 空态视图
```

`test/` 下另有 21 个测试文件，共 236 个用例，覆盖模型序列化、存储层、Provider 持久化、
图片管线、备份往返与 WebDAV 交互、数据源配置与检索回填、个人档案与主题、统计聚合
（热力图去重规则 / 类型占比 / 评分分桶 / 年报亮点）、三段式仪表盘渲染，以及关键 UI 流程
（联想输入、筛选恢复、卡片长按跳转、仪表盘空态点击直达新增页、本地导出落盘与含图分支、
片长输入净化等）。

## 特性说明

- **深浅双主题**：色板以 `ThemeExtension` 注入，取色统一走 `context.colors.xxx`；
  深色为原始设计（`#0F0F0F` 背景 / `#1A1A2E` 卡片），浅色为其反推（近白背景 / 纯白卡片 / 深灰文字）。
  主题偏好写入 `profile.json`，重启保持；可选「跟随系统」。
- **封面可降级**：支持本地图片与网络图，无封面或加载失败时回退到 HSL 渐变 + emoji 占位，断网也不破版。
- **状态管理**：Provider（`ChangeNotifier`）作单一数据源，UI 只读 Provider，写操作由 Provider 统一落盘。
- **圆形进度环**：`CustomPainter` + `SweepGradient` + 900ms 缓动动画。
- **联想式录入**：书籍分类与电影剧情类型均为「候选点选 + 自由输入」的多选标签；
  电影导演失焦后自动挂到演员区首位。

## 已实现

- **本地持久化**：JSON 文件存储（`LibraryStore`），原子写入（`.tmp` + rename）、`schemaVersion` 校验、同一 tick 内的多次写操作自动合并；Web 端自动降级为内存存储。用户档案独立存于 `profile.json`
- **书籍 / 电影 / 演员全链路增删改查**：三套编辑页 + 详情页；删除演员时若仍被影片引用会拒绝删除并列出引用来源
- **搜索与筛选**：关键词搜索、分类 / 类型 / 状态下拉筛选（候选动态取自已有数据，含用户自定义项）、详情页点击作者即跳转并预填筛选条件
- **图片管理**：相册选图 / 粘贴网络链接 / 移除封面，图片复制进应用私有目录，更换或删除时自动回收孤儿文件
- **仪表盘真实数据联动**：统计双卡、当前任务、阅读与观影网格全部由书影数据实时计算，含空态兜底；书库 / 影库为空时，空态卡整卡可点击，直达「添加图书 / 添加电影」页；「查看全部」跳转对应 Tab
- **个人中心**：昵称 / 签名 / 头像编辑（头像卡片点击为只读展示，「编辑资料」行进入编辑）、数据统计页、主题三选
- **三段式仪表盘统计（个人统计页）**：顶部年度指标栏（年度读书 X 本 · 观影 Y 部 · 观影时长 Z 小时）+
  GitHub 风格打卡热力图（30 天 / 季度 / 年度切换，计数规则为「同一实体同一天去重 1 次、
  不同实体累加」，0 / 1 / 2 / 3+ 四级着色，聚合书 createdAt / startedAt / finishedAt 与
  电影 watchDate）；中部类型偏好环形图（Top5 + 百分比图例）与 1~5 星评分分布柱状图
  （均纯 `CustomPainter` 实现，零第三方依赖）；底部在读进度条（默认 3 本 + 底部弹层「查看全部」）、
  年度五星封面墙与年报入口；每个区块均有空态兜底文案
- **年度报告**：年度快照页（`annual_report_screen.dart`）——年度总览渐变卡
  （读完本数 / 页数 / 观影时长 / 年度偏好分类）、最晚读完的一本书、阅读页数最多的一周、
  打破偏好的那一本（分类与整体最高频分类不同的当年完成书）；数据实时计算，记录变化即更新
- **数据同步 / 备份（P5）**：WebDAV 云同步（坚果云 / Nextcloud 等标准网盘）——4 项服务器配置 +
  测试连接、立即备份 / 从云端恢复（恢复前二次确认 + 本地快照兜底）、启动时自动同步（可限 Wi-Fi、
  节流 1 小时）、备份可选包含本地图片（JSON 单文件 / 含图 ZIP）；本地导出改为弹「保存位置选择器」
  由用户自选落盘路径（含图开关跟随同步偏好，开 → ZIP、关 → JSON），断网环境的保底手段。
  凭据存系统安全存储（Keystore / Keychain），`settings.json` 不含密码；Web 平台隐藏该功能入口
- **联网信息补全（可选）**：个人中心「数据源管理」——影视源内置 TMDB、图书源内置 OpenLibrary（默认）
  与 Google Books。**接入第三方站点无需内置预设**：自定义数据源填 Base URL + API Key 即可，
  返回 JSON 由智能解析兜底（递归找数据列表 + 中英文字段别名映射，支持数组 / `{data:[…]}` /
  `{results:[…]}` 等常见结构），豆瓣、Bangumi 等站点走这条路径即可
  可添加多个并单选默认，支持连接测试与配置编辑；书籍 / 电影编辑页顶部「快速检索」输入名称即
  联网搜索（500ms 防抖），点选结果自动回填表单（图书含 ISBN 与封面，电影含导演 / 主演 / 片长 /
  类型 / 海报），保存时记录溯源 `source`。TMDB 的 API Key 存系统安全存储；数据源配置随
  `data_sources.json` 一并纳入备份 / 恢复（schemaVersion 2，向后兼容），云端恢复后自动重载
  并提示缺失凭据的源。未配置或断网时检索块自动隐藏，不影响手动录入

## 路线图（未实现）

- [ ] 年度目标设定：设定年度读书 / 观影目标并在统计仪表盘追踪完成度
  （图表统计与年报已实现，目标追踪尚未开始）
- [ ] 仪表盘顶栏搜索 / 通知按钮接上功能（当前为空实现）

## 开发约定

- **取色**：一律 `context.colors.xxx`，禁止静态常量色（主题切换时 const 子树不会重绘）。
- **格式门禁**：CI 中的 `dart format --set-exit-if-changed` 默认注释；如需开启，先在本机执行
  `dart format .` 再取消 `.github/workflows/ci.yml` 中对应步骤的注释。

## 开源许可

本项目基于 [MIT License](./LICENSE) 开源，Copyright (c) 2026 Afyery。
