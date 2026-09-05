# 墨影 MoYing 🎬📚

一个**现代暗色风格**的书籍与电影记录应用（Flutter UI 框架 Demo）。

对齐参考设计：底部四标签导航（仪表盘 / 书籍 / 电影 / 个人），
仪表盘包含**数据统计双卡**（阅读进度环 + 观影均分）与**当前任务**横向滚动区，
以及阅读 / 电影 2 列网格列表。当前全部使用虚拟数据初始化，无网络依赖。

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
lib/
├── main.dart                  # 入口（Provider + 暗色主题 + 状态栏）
├── config/
│   ├── app_colors.dart        # 全局色板（暗色背景/渐变/文字）
│   └── app_theme.dart         # Material 3 暗色主题
├── models/
│   ├── book.dart              # Book + BookStatus
│   └── movie.dart             # Movie + MovieStatus
├── providers/
│   └── library_provider.dart  # 书影库状态（ChangeNotifier）
├── data/
│   └── mock_data.dart         # 虚拟数据（14 本书 / 32 部电影 / 70% 目标进度）
├── screens/
│   ├── main_shell.dart        # 底部导航壳（仪表盘/书籍/电影/个人）
│   ├── dashboard_screen.dart  # 仪表盘主页（核心）
│   ├── library_screens.dart   # 书籍 / 电影列表页
│   └── profile_screen.dart    # 个人中心
└── widgets/
    ├── stats_card.dart        # 统计双卡（阅读渐变环 / 观影均分徽章）
    ├── progress_ring.dart     # CustomPainter 圆形进度环（动画）
    ├── rating_stars.dart      # 五星评分
    ├── media_tile.dart        # 当前任务横向卡片
    ├── grid_item_card.dart    # 网格媒体卡（封面渐变占位）
    ├── cover_placeholder.dart # 离线封面（渐变 + emoji，无网络依赖）
    ├── section_header.dart    # 区块标题
    └── placeholder_view.dart  # 空态视图
```

## 特性说明

- **暗色主题**：`#0F0F0F` 背景 / `#1A1A2E` 卡片，紫蓝（阅读）与青绿（观影）双渐变。
- **封面零网络依赖**：所有封面为 HSL 渐变 + emoji 占位，断网也不破版。
- **状态管理**：Provider（`ChangeNotifier`），数据与 UI 解耦，后续可平滑替换为本地库。
- **圆形进度环**：`CustomPainter` + `SweepGradient` + 900ms 缓动动画。

## 路线图（未实现）

- [ ] 本地持久化（Hive / SQLite）与增删改查
- [ ] 真实封面图与豆瓣 / TMDB 数据接入
- [ ] 书籍 / 电影详情页、搜索与筛选
- [ ] 年度目标动态计算与图表统计

## 开源许可

本项目基于 [MIT License](./LICENSE) 开源，Copyright (c) 2026 Afyery。
