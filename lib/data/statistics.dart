// 三段式仪表盘统计聚合纯函数
//
// 热力图计数规则（产品已确认）：
// - 同一实体（书/电影）同一天去重，只计 1 次；
// - 不同实体同一天累加；
// - count == 0 → 未打卡；count == 1 → 浅色微光；count >= 3 → 高亮。

import '../models/book.dart';
import '../models/movie.dart';

// ==================== 数据模型 ====================

/// 热力图时间范围
enum HeatmapRange { month30, quarter, year }

/// 热力图数据：Key=日期字符串 "yyyy-MM-dd"，Value=当日活动数
typedef HeatmapData = Map<String, int>;

/// 类型占比条目（按本数）
class CategoryEntry {
  const CategoryEntry({
    required this.category,
    required this.count,
    required this.percent,
  });
  final String category;
  final int count;
  final double percent; // 0.0 ~ 1.0
}

/// 评分分布（1~5 星各多少）
class RatingDistribution {
  const RatingDistribution({
    required this.star1,
    required this.star2,
    required this.star3,
    required this.star4,
    required this.star5,
  });
  final int star1;
  final int star2;
  final int star3;
  final int star4;
  final int star5;
  int get total => star1 + star2 + star3 + star4 + star5;
}

/// 在读进度条目
class ReadingProgress {
  const ReadingProgress({
    required this.id,
    required this.title,
    required this.author,
    required this.current,
    required this.total,
    required this.progress,
    this.coverHue,
    this.emoji,
  });
  final String id;
  final String title;
  final String author;
  final int current;
  final int total;
  final double progress; // 0.0 ~ 1.0
  final double? coverHue;
  final String? emoji;
}

/// 年度统计汇总
class AnnualStats {
  const AnnualStats({
    required this.booksRead,
    required this.pagesRead,
    required this.moviesWatched,
    required this.minutesWatched,
  });
  final int booksRead;
  final int pagesRead;
  final int moviesWatched;
  final int minutesWatched;
  int get hoursRead => pagesRead ~/ 60; // 折算阅读小时（按平均阅读速度估算）
  int get hoursWatched => minutesWatched ~/ 60;
}

/// 年度年报亮点
class AnnualHighlights {
  const AnnualHighlights({
    this.latestFinishedBook,
    this.fastestReadingWeek,
    this.breakthroughBook,
    required this.totalBooksRead,
    required this.totalMoviesWatched,
    required this.totalPagesRead,
    required this.totalMinutesWatched,
    this.topCategory,
  });
  final Book? latestFinishedBook;
  final String? fastestReadingWeek;
  final Book? breakthroughBook;
  final int totalBooksRead;
  final int totalMoviesWatched;
  final int totalPagesRead;
  final int totalMinutesWatched;
  final String? topCategory;
}

// ==================== 聚合纯函数 ====================

/// 把实体操作时间展开成「日期 → count」聚合，同一天同一实体去重。
///
/// [entities] 为 (id, dates) 列表；[from]/[to] 为闭区间。
/// 返回 { "yyyy-MM-dd": count }。
HeatmapData buildHeatmap(
  List<(String, List<DateTime>)> entities, {
  required DateTime from,
  required DateTime to,
}) {
  final counts = <String, int>{};
  final seen = <String>{};

  for (final (id, dates) in entities) {
    for (final d in dates) {
      final day = DateTime(d.year, d.month, d.day);
      final startDay = DateTime(from.year, from.month, from.day);
      final endDay = DateTime(to.year, to.month, to.day);
      if (day.isBefore(startDay) || day.isAfter(endDay)) continue;
      final dk = _dayKey(day);
      // 同一实体同一日期去重
      final key = '$id@$dk';
      if (seen.contains(key)) continue;
      seen.add(key);
      counts[dk] = (counts[dk] ?? 0) + 1;
    }
  }
  return counts;
}

/// 书的所有操作时间点（用于热力图）
List<DateTime> bookActivityDates(Book b) => [
      b.createdAt,
      if (b.startedAt != null) b.startedAt!,
      if (b.finishedAt != null) b.finishedAt!,
    ];

/// 电影的所有操作时间点（用于热力图）
List<DateTime> movieActivityDates(Movie m) =>
    [if (m.watchDate != null) m.watchDate!];

/// 类型占比（按本数）；只统计有分类的已完成/在读书
List<CategoryEntry> categoryDistribution(List<Book> books) {
  final counts = <String, int>{};
  var total = 0;
  for (final b in books) {
    final c = b.category;
    if (c == null || c.isEmpty) continue;
    counts[c] = (counts[c] ?? 0) + 1;
    total++;
  }
  if (total == 0) return const [];
  final list = counts.entries
      .map((e) => CategoryEntry(
            category: e.key,
            count: e.value,
            percent: e.value / total,
          ))
      .toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  return list;
}

/// 评分分布（1~5 星，四舍五入），书籍 + 电影各自聚合
RatingDistribution ratingDistribution({
  required List<Book> books,
  required List<Movie> movies,
}) {
  var s1 = 0, s2 = 0, s3 = 0, s4 = 0, s5 = 0;
  void add(double? r) {
    if (r == null) return;
    switch (r.round().clamp(1, 5)) {
      case 1: s1++;
      case 2: s2++;
      case 3: s3++;
      case 4: s4++;
      case 5: s5++;
    }
  }
  for (final b in books) {
    add(b.rating);
  }
  for (final m in movies) {
    add(m.rating);
  }
  return RatingDistribution(
      star1: s1, star2: s2, star3: s3, star4: s4, star5: s5);
}

/// 在读书籍 → 进度条目列表
List<ReadingProgress> readingProgressList(List<Book> books) => books
    .where((b) => b.status == BookStatus.reading)
    .map((b) => ReadingProgress(
          id: b.id,
          title: b.title,
          author: b.author,
          current: b.currentPage,
          total: b.totalPages,
          progress: b.progress,
          coverHue: b.coverHue,
          emoji: b.emoji,
        ))
    .toList();

/// 年度统计汇总
AnnualStats computeAnnualStats({
  required List<Book> books,
  required List<Movie> movies,
  required int year,
}) {
  var booksRead = 0, pages = 0, moviesWatched = 0, minutes = 0;
  for (final b in books) {
    if (b.status != BookStatus.finished) continue;
    final f = b.finishedAt;
    if (f == null || f.year != year) continue;
    booksRead++;
    pages += b.totalPages;
  }
  for (final m in movies) {
    final w = m.watchDate;
    if (w == null || w.year != year) continue;
    moviesWatched++;
    minutes += m.duration ?? 0;
  }
  return AnnualStats(
    booksRead: booksRead,
    pagesRead: pages,
    moviesWatched: moviesWatched,
    minutesWatched: minutes,
  );
}

/// 年度年报亮点
AnnualHighlights computeAnnualHighlights({
  required List<Book> books,
  required List<Movie> movies,
  required int year,
}) {
  // 最晚读完的书
  Book? latest;
  for (final b in books) {
    if (b.status != BookStatus.finished) continue;
    final f = b.finishedAt;
    if (f == null || f.year != year) continue;
    if (latest == null || f.isAfter(latest.finishedAt!)) latest = b;
  }

  // 阅读最快的一周（按周一聚合当年完成页数）
  String? fastestWeek;
  var bestPages = 0;
  final weekPages = <String, int>{};
  for (final b in books) {
    if (b.status != BookStatus.finished) continue;
    final f = b.finishedAt;
    if (f == null || f.year != year) continue;
    final monday = f.subtract(Duration(days: f.weekday - 1));
    final mk = _dayKey(monday);
    weekPages[mk] = (weekPages[mk] ?? 0) + b.totalPages;
  }
  weekPages.forEach((k, v) {
    if (v > bestPages) {
      bestPages = v;
      // 从 k 解析出月日
      final parts = k.split('-');
      fastestWeek = '${int.parse(parts[1])}月${int.parse(parts[2])}日那周读了 $v 页';
    }
  });

  // 打破偏好的书：分类与整体最高频分类不同的当年完成书
  final dist = categoryDistribution(books);
  final topCat = dist.isEmpty ? null : dist.first.category;
  Book? breakthrough;
  for (final b in books) {
    if (b.status != BookStatus.finished) continue;
    final f = b.finishedAt;
    if (f == null || f.year != year) continue;
    if (b.category != null && b.category != topCat) {
      breakthrough = b;
      break;
    }
  }

  final s = computeAnnualStats(books: books, movies: movies, year: year);
  return AnnualHighlights(
    latestFinishedBook: latest,
    fastestReadingWeek: fastestWeek,
    breakthroughBook: breakthrough,
    totalBooksRead: s.booksRead,
    totalMoviesWatched: s.moviesWatched,
    totalPagesRead: s.pagesRead,
    totalMinutesWatched: s.minutesWatched,
    topCategory: topCat,
  );
}

/// 日期归一化：yyyy-MM-dd（本地时区）
String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';