import 'package:flutter/widgets.dart';

/// 本地图解析契约：**组件层定义、业务层注入**
///
/// [context] 是**调用点**的 context（位于 Provider 树之下），因此实现方
/// 可以直接 `context.read<LibraryProvider>()`，而组件层无需知道业务
/// Provider 的存在。这样 component 层保持对 business 层的零依赖。
///
/// 返回**绝对路径**而非 `File`，避免契约本身依赖 `dart:io`
/// （app 层接线时也就无需 import dart:io，Web 构建不受影响）。
typedef LocalMediaResolver = String? Function(
  BuildContext context,
  String? localFile,
);

/// 向组件层注入「本地图 → File」的解析能力
///
/// **为什么需要**：封面/头像组件（component 层）要展示本地已落盘的图片，
/// 而 images 目录的解析规则属于书库业务（`LibraryProvider`）。
/// 按四层依赖方向 `business → component`，组件层不能反向 import 业务。
/// 于是组件层只声明契约，由 app 层在**根容器**（`MaterialApp` 之上、
/// 因而覆盖全部路由与弹层）注入真实实现。
///
/// 未注入时（孤立预览、组件测试）取到 null，组件静默降级为网络图或占位，
/// 不会抛错。
class LocalMediaScope extends InheritedWidget {
  const LocalMediaScope({
    super.key,
    required this.resolver,
    required super.child,
  });

  /// 本地图解析实现；null 表示未接入（组件需自行降级）
  final LocalMediaResolver? resolver;

  static LocalMediaResolver? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LocalMediaScope>()?.resolver;

  @override
  bool updateShouldNotify(LocalMediaScope oldWidget) =>
      resolver != oldWidget.resolver;
}
