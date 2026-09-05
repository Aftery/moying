// 仪表盘统计卡片用数据类
//
// 字段全部 required：provider 计算 getter 必须显式聚合所有字段，
// 避免漏算导致 UI 显示与真实列表脱节（仪表盘「虚拟改真实」要点）。

/// 阅读统计聚合
///
/// - [total]：书库总藏书数
/// - [active]：在读书本数（status == reading）
/// - [finished]：已读完本数（status == finished）
/// - [pagesRead]：累计已读页数 = `finished` 的 `totalPages` 之和 + `reading` 的 `currentPage` 之和（想读不贡献）
/// - [progress]：在读 + 已读 书的 `progress` 算术平均（0.0 - 1.0；想读不参与，避免 0 拉低）
class BookStats {
  const BookStats({
    required this.total,
    required this.active,
    required this.finished,
    required this.pagesRead,
    required this.progress,
  });

  final int total;
  final int active;
  final int finished;
  final int pagesRead;
  final double progress;
}

/// 电影统计聚合
///
/// - [total]：电影库总收录数
/// - [watchlist]：想看数（status == watchlist）
/// - [rated]：已评分数（rating != null）
/// - [averageRating]：已评分电影的平均评分（0-5；无已评分时为 0）
class MovieStats {
  const MovieStats({
    required this.total,
    required this.watchlist,
    required this.rated,
    required this.averageRating,
  });

  final int total;
  final int watchlist;
  final int rated;
  final double averageRating;
}