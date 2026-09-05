import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moying/models/media_ref.dart';
import 'package:moying/providers/library_provider.dart';
import 'package:moying/widgets/media_cover.dart';
import 'package:provider/provider.dart';

/// 1×1 透明 PNG
final List<int> kPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void main() {
  /// 有 provider 的壳（MediaCover 经 context 解析 localFile）
  Widget shell(LibraryProvider provider, Widget child) {
    return ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 120, child: child),
          ),
        ),
      ),
    );
  }

  Widget cover({
    MediaRef? media,
    File? pending,
    String emoji = '📚',
  }) {
    return MediaCover(
      media: media,
      pendingFile: pending,
      title: '三体',
      emoji: emoji,
      hue: 250,
    );
  }

  testWidgets('无图：渲染占位（emoji 首字符）', (tester) async {
    final p = LibraryProvider();
    await tester.pumpWidget(shell(p, cover()));
    await tester.pumpAndSettle();
    expect(find.text('📚'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('网络图：渲染 Image.network，加载失败由 errorBuilder 兜底不抛异常',
      (tester) async {
    final p = LibraryProvider();
    await tester.pumpWidget(shell(
      p,
      cover(media: MediaRef.network('https://example.com/x.jpg')),
    ));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    // 测试环境网络被禁（400）→ errorBuilder 吞错，无未处理异常
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    // 卸载组件取消加载中的图片流，避免 fake-async 下挂起
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('本地图不可解析（内存模式无 store）：回退占位', (tester) async {
    final p = LibraryProvider(); // 内存模式 → resolveLocalImage 恒 null
    await tester.pumpWidget(shell(
      p,
      cover(media: MediaRef.local('c1.png')),
    ));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('📚'), findsOneWidget);
  });

  // 注：可解析 localFile / pendingFile → 渲染 Image.file 的分支不做 widget 断言——
  // dart:io 文件读取在 fake-async 测试时钟里永不完成（FileImage 解码冻结，会挂死测试），
  // 属框架固有限制；该接线的正确性由 media_pipeline_test 的 resolveLocalImage /
  // attachImage 单测 + MediaCover 代码审查共同保障。

  testWidgets('圆形模式：无图渐变圆占位', (tester) async {
    final p = LibraryProvider();
    await tester.pumpWidget(shell(
      p,
      const MediaCover(
        circular: true,
        title: '周星驰',
        hue: 120,
        fontSize: 24,
      ),
    ));
    await tester.pump();
    // 首字占位可见
    expect(find.text('周'), findsOneWidget);
  });
}
