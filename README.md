# 墨影 MoYing 🎬📚

一个**现代暗色风格**的书籍与电影记录应用（Flutter 跨平台，数据本地持久化）。

对齐参考设计：底部四标签导航（仪表盘 / 书籍 / 电影 / 个人），
仪表盘包含**数据统计双卡**（阅读进度环 + 观影均分）与**当前任务**横向滚动区，
以及阅读 / 电影 2 列网格列表。首次启动以内置种子数据初始化，此后增删改全部持久化到本地，全程无网络依赖。

## 运行

```bash
# 首次运行前请确认本机已安装 Flutter SDK（本仓库在 3.24.x 验证）
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
flutter analyze       # 静态分析（期望 0 error）
flutter test          # 单元测试
flutter build web     # 编译验证（无需移动端 SDK）
```

## 目录结构

```
lib/（37 个 .dart 文件）

├── main.dart                     # 入口（Provider + 暗色主题 + 状态栏 + 持久化接线）
├── config/
│   ├── app_colors.dart           # 全局色板（暗色背景 / 渐变 / 文字）
│   └── app_theme.dart            # Material 3 暗色主题
├── models/
│   ├── actor.dart                # Actor
│   ├── book.dart                 # Book + BookStatus + kBookCategories
│   ├── media_ref.dart            # MediaRef（本地文件 / 网络图引用，双空即占位）
│   ├── movie.dart                # Movie + MovieStatus
│   └── stats.dart                # BookStats / MovieStats
├── providers/
│   └── library_provider.dart     # 书影库状态（ChangeNotifier）+ 持久化接线
├── data/
│   ├── library_store.dart        # JSON 存储：原子写 / 合并写 / schemaVersion / 图片管理
│   ├── mock_data.dart            # 种子数据（12 本书 / 8 部电影；演员由演员表派生）
│   ├── persistence.dart          # 平台门面（条件导入）
│   ├── persistence_io.dart       # 手机 / 桌面实现（dart:io + path_provider）
│   └── persistence_stub.dart     # Web 回退（内存存储）
├── services/
│   └── image_pick_service.dart   # 选图服务抽象（image_picker）
├── screens/
│   ├── main_shell.dart           # 底部导航壳（仪表盘 / 书籍 / 电影 / 个人）
│   ├── dashboard_screen.dart     # 仪表盘主页（核心）
│   ├── books_screen.dart         # 图书库列表（搜索 + 分类 / 状态筛选）
│   ├── library_screens.dart      # 影库列表
│   ├── book_detail_screen.dart   # 书籍详情
│   ├── movie_detail_screen.dart  # 电影详情
│   ├── actor_detail_screen.dart  # 演员详情（含参演作品反查）
│   ├── book_edit_screen.dart     # 书籍新增 / 编辑（分类联想、阅读时间、封面）
│   ├── movie_edit_screen.dart    # 电影新增 / 编辑（演员联想、评分、海报）
│   └── profile_screen.dart       # 个人中心（框架占位）
└── widgets/
    ├── media_cover.dart          # 媒体图三态展示（本地 / 网络 / 占位）
    ├── stats_card.dart           # 统计双卡（阅读渐变环 / 观影均分徽章）
    ├── progress_ring.dart        # CustomPainter 圆形进度环（动画）
    ├── rating_stars.dart         # 五星评分展示（支持小数）
    ├── star_rating_picker.dart   # 交互式评分选择器（编辑页）
    ├── media_tile.dart           # 当前任务横向卡片
    ├── book_list_card.dart       # 图书列表卡（竖版封面 + 状态徽标 + 进度角标）
    ├── grid_item_card.dart       # 网格媒体卡
    ├── cover_placeholder.dart    # 离线封面（渐变 + emoji，无网络依赖）
    ├── search_bar_widget.dart    # 暗色圆角搜索栏
    ├── section_header.dart       # 区块标题
    └── placeholder_view.dart     # 空态视图
```

`test/` 下另有 12 个测试文件，共 123 个用例，覆盖模型序列化、存储层、Provider 持久化、图片管线与关键 UI 流程。

## 特性说明

- **暗色主题**：`#0F0F0F` 背景 / `#1A1A2E` 卡片，紫蓝（阅读）与青绿（观影）双渐变。
- **封面可降级**：支持本地图片与网络图，无封面或加载失败时回退到 HSL 渐变 + emoji 占位，断网也不破版。
- **状态管理**：Provider（`ChangeNotifier`）作单一数据源，UI 只读 Provider，写操作由 Provider 统一落盘。
- **圆形进度环**：`CustomPainter` + `SweepGradient` + 900ms 缓动动画。

## 已实现

- **本地持久化**：JSON 文件存储（`LibraryStore`），原子写入（`.tmp` + rename）、`schemaVersion` 校验、同一 tick 内的多次写操作自动合并；Web 端自动降级为内存存储
- **书籍 / 电影 / 演员全链路增删改查**：三套编辑页 + 详情页；删除演员时若仍被影片引用会拒绝删除并列出引用来源
- **搜索与筛选**：关键词搜索、分类下拉筛选（候选动态取自已有数据）、详情页点击作者即跳转并预填筛选条件
- **图片管理**：相册选图 / 粘贴网络链接 / 移除封面，图片复制进应用私有目录，更换或删除时自动回收孤儿文件
- **仪表盘真实数据联动**：统计双卡、当前任务、阅读与观影网格全部由书影数据实时计算，含空态兜底

## 路线图（未实现）

- [ ] 联网信息补全：豆瓣 / TMDB 条目检索，自动填充真实封面与元数据
- [ ] 备份与恢复：本地文件导出 + WebDAV 同步
- [ ] 年度目标设定与图表统计（当前「个人」页仅展示四项数字汇总）
- [ ] 「个人」页设置项落地：编辑资料、数据统计、深色模式切换（当前为占位，开关不可交互）
- [ ] 仪表盘顶栏搜索 / 通知按钮接上功能（当前为空实现）

## 开源许可

本项目基于 [MIT License](./LICENSE) 开源，Copyright (c) 2026 Afyery。
