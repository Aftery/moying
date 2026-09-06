# 墨影 MoYing 🎬📚

一个**深浅双主题**的书籍与电影记录应用（Flutter 跨平台，数据本地持久化，离线优先——联网检索为可选增强）。

底部四标签导航：**仪表盘 / 书籍 / 电影 / 个人**。

- **仪表盘**：统计双卡（阅读平均进度环 + 观影均分徽章）、当前任务横滑区、阅读列表与我的电影网格（各 4 条，可跳转全量）
- **书籍 / 电影**：搜索 + 动态筛选 + 列表/网格切换，卡片单击进详情、长按进编辑
- **个人**：昵称 / 签名 / 头像编辑、深浅主题三选（深色 / 浅色 / 跟随系统）、数据统计、数据源管理

首次启动以内置种子数据（12 本书 / 8 部电影）初始化，此后增删改全部持久化到本地。

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
flutter build web     # 编译验证（无需移动端 SDK）
```

打包 Android 安装包：

```bash
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

## 目录结构

```
lib/（52 个 .dart 文件）

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
│   ├── mock_data.dart            # 种子数据（12 本书 / 8 部电影；演员由演员表派生）
│   ├── persistence.dart          # 平台门面（条件导入）
│   ├── persistence_io.dart       # 手机 / 桌面实现（dart:io + path_provider）
│   └── persistence_stub.dart     # Web 回退（内存存储）
├── providers/
│   ├── data_source_provider.dart # 联网检索状态（防抖搜索 / 结果缓存 / 错误兜底）
│   ├── library_provider.dart     # 书影库状态（ChangeNotifier 单一数据源）
│   └── sync_provider.dart        # 同步状态与动作（上传 / 恢复 / 自动同步）
├── services/
│   ├── data_source_interface.dart # BookDataSource / MovieDataSource 抽象 + ConfigField
│   ├── data_source_manager.dart  # 数据源注册表（预设 / 默认源 / 配置与凭据存取）
│   ├── data_sources/
│   │   ├── tmdb_data_source.dart # TMDB 影视源（搜索 / 详情 / 测连，API Key 走安全存储）
│   │   └── google_books_data_source.dart # Google Books 图书源（免密钥）
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
│   └── personal_stats_screen.dart # 个人数据统计
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
    └── placeholder_view.dart     # 空态视图
```

`test/` 下另有 18 个测试文件，共 195 个用例，覆盖模型序列化、存储层、Provider 持久化、
图片管线、备份往返与 WebDAV 交互、数据源配置与检索回填、个人档案与主题、以及关键 UI 流程
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
- **数据同步 / 备份（P5）**：WebDAV 云同步（坚果云 / Nextcloud 等标准网盘）——4 项服务器配置 +
  测试连接、立即备份 / 从云端恢复（恢复前二次确认 + 本地快照兜底）、启动时自动同步（可限 Wi-Fi、
  节流 1 小时）、备份可选包含本地图片（JSON 单文件 / 含图 ZIP）；本地导出改为弹「保存位置选择器」
  由用户自选落盘路径（含图开关跟随同步偏好，开 → ZIP、关 → JSON），断网环境的保底手段。
  凭据存系统安全存储（Keystore / Keychain），`settings.json` 不含密码；Web 平台隐藏该功能入口
- **联网信息补全（可选）**：个人中心「数据源管理」——影视源（内置 TMDB）与图书源（内置 Google Books）
  可添加多个并单选默认，支持连接测试与配置编辑；书籍 / 电影编辑页顶部「快速检索」输入名称即
  联网搜索（500ms 防抖），点选结果自动回填表单（图书含 ISBN 与封面，电影含导演 / 主演 / 片长 /
  类型 / 海报），保存时记录溯源 `source`。TMDB 的 API Key 存系统安全存储；数据源配置随
  `data_sources.json` 一并纳入备份 / 恢复（schemaVersion 2，向后兼容），云端恢复后自动重载
  并提示缺失凭据的源。未配置或断网时检索块自动隐藏，不影响手动录入

## 路线图（未实现）

- [ ] 更多数据源：豆瓣（用户自行配置）、Bangumi、OpenBD 等内置预设接入
- [ ] 年度目标设定与图表统计（当前「数据统计」页为数字汇总 + 进度环）
- [ ] 仪表盘顶栏搜索 / 通知按钮接上功能（当前为空实现）

## 开发约定

- **取色**：一律 `context.colors.xxx`，禁止静态常量色（主题切换时 const 子树不会重绘）。
- **格式门禁**：CI 中的 `dart format --set-exit-if-changed` 默认注释；如需开启，先在本机执行
  `dart format .` 再取消 `.github/workflows/ci.yml` 中对应步骤的注释。

## 开源许可

本项目基于 [MIT License](./LICENSE) 开源，Copyright (c) 2026 Afyery。
