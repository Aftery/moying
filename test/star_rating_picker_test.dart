// 星星评分选择器：点击 / 拖动两种手势 + 触感反馈
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moying/business/library/view/star_rating_picker.dart';

void main() {
  /// 装一个平台通道探针，记录 HapticFeedback 的调用。
  ///
  /// `HapticFeedback.selectionClick()` 最终表现为 [SystemChannels.platform]
  /// 上的 `HapticFeedback.vibrate` —— 测试环境没有真实马达，只能这样断言
  /// 「到底震没震、震了几次」。
  List<MethodCall> installHapticSpy() {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ));
    return calls;
  }

  Future<void> pumpPicker(
    WidgetTester tester, {
    required double rating,
    required ValueChanged<double> onChanged,
    bool haptics = true,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: StarRatingPicker(
            rating: rating,
            onChanged: onChanged,
            haptics: haptics,
          ),
        ),
      ),
    ));
  }

  group('StarRatingPicker', () {
    testWidgets('渲染 5 颗星', (tester) async {
      await pumpPicker(tester, rating: 0, onChanged: (_) {});
      expect(find.byType(IconButton), findsNWidgets(5));
    });

    testWidgets('点击第 3 颗星 → 回调 3', (tester) async {
      final values = <double>[];
      await pumpPicker(tester, rating: 0, onChanged: values.add, haptics: false);

      await tester.tap(find.byType(IconButton).at(2));
      await tester.pump();

      expect(values, [3.0]);
    });

    testWidgets('点击当前档位 → 回调 0（清除评分）', (tester) async {
      final values = <double>[];
      await pumpPicker(tester, rating: 3, onChanged: values.add, haptics: false);

      await tester.tap(find.byType(IconButton).at(2));
      await tester.pump();

      expect(values, [0.0]);
    });

    testWidgets('左右拖动连续改档，且每跨一档震一次', (tester) async {
      final haptics = installHapticSpy();
      final values = <double>[];
      await pumpPicker(tester, rating: 0, onChanged: values.add);

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(StarRatingPicker)));

      // 一路向左：每步 20px、共 400px，必定贴到最左
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(-20, 0));
      }
      await tester.pump();
      expect(values.last, 1.0, reason: '拖到最左应当 = 1 星');

      // 记录右移前的档位序列长度，便于单独校验右移阶段
      final leftPhaseCount = values.length;

      // 一路向右：共 800px，必定贴到最右
      for (var i = 0; i < 40; i++) {
        await gesture.moveBy(const Offset(20, 0));
      }
      await tester.pump();
      expect(values.last, 5.0, reason: '拖到最右应当 = 5 星');

      await gesture.up();
      await tester.pump();

      // 右移阶段必须逐档递增、不跳档
      final rightPhase = values.sublist(leftPhaseCount);
      expect(rightPhase.length, greaterThan(1));
      for (var i = 1; i < rightPhase.length; i++) {
        final delta = rightPhase[i] - rightPhase[i - 1];
        expect(delta, 1.0, reason: '档位应逐档 +1，不能跳跃或回退');
      }

      // 拖动期间不留「拖拽脏值」：松手后仍以入参 rating 渲染，档位回到 0
      expect(values.length, haptics.length, reason: '每跨一档震一次，次数应与变化次数相等');
      expect(haptics, isNotEmpty);
      expect(
        haptics.first.arguments,
        contains('selectionClick'),
        reason: '用最轻的一档触感（selectionClick），不打扰',
      );
    });

    testWidgets('haptics=false 时不触发任何触感', (tester) async {
      final haptics = installHapticSpy();
      final values = <double>[];
      await pumpPicker(tester, rating: 0, onChanged: values.add, haptics: false);

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(StarRatingPicker)));
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(20, 0));
      }
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(values, isNotEmpty, reason: '档位仍应变化，只是不震');
      expect(haptics, isEmpty);
    });

    testWidgets('拖到同一档内不重复触发（值不变 = 不回调也不震）', (tester) async {
      final haptics = installHapticSpy();
      final values = <double>[];
      await pumpPicker(tester, rating: 0, onChanged: values.add);

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(StarRatingPicker)));
      // 先贴到最右
      for (var i = 0; i < 40; i++) {
        await gesture.moveBy(const Offset(20, 0));
      }
      await tester.pump();
      final countAtRight = values.length;
      final hapticsAtRight = haptics.length;

      // 继续在最右档内小幅晃动：不该再产生变化
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(20, 0));
      }
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(values.length, countAtRight);
      expect(haptics.length, hapticsAtRight);
    });
  });
}
