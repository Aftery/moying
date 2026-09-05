// Book 模型时间字段单元测试：createdAt 必填 / sentinel 置空 / readingDays 计算
import 'package:flutter_test/flutter_test.dart';

import 'package:moying/models/book.dart';

Book _book({DateTime? startedAt, DateTime? finishedAt}) => Book(
      id: 't1',
      title: '测试书',
      author: '测试作者',
      totalPages: 100,
      createdAt: DateTime(2026, 1, 10),
      startedAt: startedAt,
      finishedAt: finishedAt,
    );

void main() {
  group('Book · 时间字段', () {
    test('省略 copyWith 参数保留原时间字段', () {
      final b = _book(
        startedAt: DateTime(2026, 2, 1),
        finishedAt: DateTime(2026, 2, 20),
      );
      final updated = b.copyWith(title: '新标题');
      expect(updated.startedAt, b.startedAt);
      expect(updated.finishedAt, b.finishedAt);
    });

    test('copyWith 显式传 null 可清空完成时间', () {
      final b = _book(
        startedAt: DateTime(2026, 2, 1),
        finishedAt: DateTime(2026, 2, 20),
      );
      final cleared = b.copyWith(finishedAt: null);
      expect(cleared.finishedAt, isNull);
      expect(cleared.startedAt, isNotNull); // 不影响开始时间
    });

    test('copyWith 显式传 null 可清空开始时间', () {
      final b = _book(startedAt: DateTime(2026, 2, 1));
      expect(b.copyWith(startedAt: null).startedAt, isNull);
    });

    test('readingDays：同天读完计 1 天', () {
      final b = _book(
        startedAt: DateTime(2026, 2, 1, 23, 0),
        finishedAt: DateTime(2026, 2, 1, 9, 0), // 开始晚于完成仍按同日 1 天
      );
      expect(b.readingDays, 1);
    });

    test('readingDays：跨天按自然日差 + 1（凌晨时刻不吞天数）', () {
      final b = _book(
        startedAt: DateTime(2026, 2, 1, 22, 0),
        finishedAt: DateTime(2026, 2, 3, 6, 0), // 原始时刻差仅 1.3 天
      );
      expect(b.readingDays, 3); // 归一化到日：2/1 → 2/3 = 2 天 + 1
    });

    test('readingDays：缺开始或完成任一返回 0', () {
      expect(_book(startedAt: DateTime(2026, 2, 1)).readingDays, 0);
      expect(_book(finishedAt: DateTime(2026, 2, 20)).readingDays, 0);
      expect(_book().readingDays, 0);
    });

    test('阅读进度 100% 且无完成时间也可存在（旧数据兼容）', () {
      final b = Book(
        id: 't2',
        title: '旧书',
        author: '作者',
        totalPages: 100,
        currentPage: 100,
        status: BookStatus.finished,
        createdAt: DateTime(2025, 1, 1),
      );
      expect(b.progress, 1.0);
      expect(b.finishedAt, isNull); // 字段本身安全为 null
    });
  });
}
