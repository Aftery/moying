// 三段式仪表盘统计聚合纯函数测试
//
// 覆盖：热力图去重规则（同实体同日 1 次 / 不同实体累加 / 范围外剔除）、
// 类型占比、评分分布、在读进度、年度指标与年报亮点。

import 'package:flutter_test/flutter_test.dart';
import 'package:moying/data/statistics.dart';
import 'package:moying/models/book.dart';
import 'package:moying/models/movie.dart';

Book _book({
  required String id,
  DateTime? createdAt,
  DateTime? startedAt,
  DateTime? finishedAt,
  BookStatus status = BookStatus.finished,
  double? rating,
  String? category,
  int totalPages = 300,
  int currentPage = 0,
}) {
  return Book(
    id: id,
    title: '书$id',
    author: '作者$id',
    totalPages: totalPages,
    currentPage: currentPage,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    status: status,
    rating: rating,
    category: category,
    startedAt: startedAt,
    finishedAt: finishedAt,
  );
}

Movie _movie({
  required String id,
  DateTime? watchDate,
  double? rating,
  int? duration,
}) {
  return Movie(
    id: id,
    title: '影$id',
    year: 2024,
    watchDate: watchDate,
    rating: rating,
    duration: duration,
  );
}

void main() {
  group('buildHeatmap 去重规则', () {
    test('同一实体同一天多个时间点只计 1 次', () {
      final d = DateTime(2026, 3, 10);
      final data = buildHeatmap(
        [('b1', [d, d.add(const Duration(hours: 2))])],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
      );
      expect(data['2026-03-10'], 1);
    });

    test('不同实体同一天累加', () {
      final d = DateTime(2026, 3, 10);
      final data = buildHeatmap(
        [('b1', [d]), ('b2', [d]), ('m1', [d])],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
      );
      expect(data['2026-03-10'], 3);
    });

    test('范围外日期剔除', () {
      final data = buildHeatmap(
        [('b1', [DateTime(2026, 2, 1)])],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
      );
      expect(data, isEmpty);
    });
  });

  group('activityDates', () {
    test('书聚合 createdAt/startedAt/finishedAt', () {
      final b = _book(
        id: '1',
        createdAt: DateTime(2026, 3, 1),
        startedAt: DateTime(2026, 3, 2),
        finishedAt: DateTime(2026, 3, 8),
      );
      expect(bookActivityDates(b).length, 3);
    });

    test('电影只有 watchDate', () {
      final m = _movie(id: '1', watchDate: DateTime(2026, 3, 5));
      expect(movieActivityDates(m).length, 1);
    });
  });

  group('categoryDistribution', () {
    test('按本数聚合并降序', () {
      final list = categoryDistribution([
        _book(id: '1', category: '科幻'),
        _book(id: '2', category: '科幻'),
        _book(id: '3', category: '科幻'),
        _book(id: '4', category: '悬疑'),
        _book(id: '5'), // 无分类不计
      ]);
      expect(list.first.category, '科幻');
      expect(list.first.count, 3);
      // 3 本科幻 / 4 本有分类的书（第 5 本无分类不计）
      expect(list.first.percent, closeTo(0.75, 1e-9));
      expect(list.length, 2);
    });

    test('空列表返回空', () {
      expect(categoryDistribution([]), isEmpty);
    });
  });

  group('ratingDistribution', () {
    test('四舍五入分桶', () {
      final dist = ratingDistribution(
        books: [
          _book(id: '1', rating: 5),
          _book(id: '2', rating: 4.4), // → 4
        ],
        movies: [
          _movie(id: 'm1', rating: 1.5), // → 2
          _movie(id: 'm2'), // 无评分
        ],
      );
      expect(dist.star5, 1);
      expect(dist.star4, 1);
      expect(dist.star2, 1);
      expect(dist.total, 3);
    });
  });

  group('readingProgressList', () {
    test('只取在读状态', () {
      final list = readingProgressList([
        _book(
          id: '1',
          status: BookStatus.reading,
          currentPage: 150,
          totalPages: 300,
        ),
        _book(id: '2', status: BookStatus.finished),
        _book(id: '3', status: BookStatus.planToRead),
      ]);
      expect(list.length, 1);
      expect(list.first.progress, closeTo(0.5, 1e-9));
    });
  });

  group('annualStats / annualHighlights', () {
    test('只统计当年完成的书与看过的电影', () {
      final s = computeAnnualStats(
        year: 2026,
        books: [
          _book(
            id: '1',
            status: BookStatus.finished,
            finishedAt: DateTime(2026, 5, 1),
            totalPages: 300,
          ),
          _book(
            id: '2',
            status: BookStatus.finished,
            finishedAt: DateTime(2025, 5, 1), // 去年
          ),
          _book(id: '3', status: BookStatus.reading), // 未完成
        ],
        movies: [
          _movie(id: 'm1', watchDate: DateTime(2026, 6, 1), duration: 120),
          _movie(id: 'm2', watchDate: DateTime(2024, 6, 1)),
        ],
      );
      expect(s.booksRead, 1);
      expect(s.pagesRead, 300);
      expect(s.moviesWatched, 1);
      expect(s.minutesWatched, 120);
      expect(s.hoursWatched, 2);
    });

    test('最晚读完 + 最快一周 + 打破偏好', () {
      final h = computeAnnualHighlights(
        year: 2026,
        books: [
          _book(
            id: '1',
            status: BookStatus.finished,
            finishedAt: DateTime(2026, 5, 1, 10),
            category: '科幻',
            totalPages: 400,
          ),
          _book(
            id: '2',
            status: BookStatus.finished,
            finishedAt: DateTime(2026, 8, 12, 23, 47), // 最晚
            category: '科幻',
            totalPages: 500,
          ),
          _book(
            id: '3',
            status: BookStatus.finished,
            finishedAt: DateTime(2026, 6, 15), // 早于书 2，不抢最晚
            category: '诗歌', // 打破偏好
          ),
        ],
        movies: [],
      );
      expect(h.latestFinishedBook?.id, '2');
      expect(h.topCategory, '科幻');
      expect(h.breakthroughBook?.id, '3');
      expect(h.fastestReadingWeek, contains('读了 500 页'));
    });

    test('空数据不崩溃', () {
      final h = computeAnnualHighlights(
          year: 2026, books: [], movies: []);
      expect(h.latestFinishedBook, isNull);
      expect(h.fastestReadingWeek, isNull);
      expect(h.topCategory, isNull);
    });
  });
}