/// 轻量日期格式化工具。
///
/// 项目内多处需要「只比较到日」与 `yyyy-MM-dd` 展示（编辑页、详情页、同步页、
/// 年报等）。此前各文件各写一份 `padLeft(2, '0')`，措辞与对齐方式容易漂移，
/// 这里收敛为两个纯函数——无依赖、可单测、任何层都可用。
library;

/// 归一到「日」（丢弃时分秒）。
///
/// 用于「完成时间不能早于开始时间」这类**日期比较**：先归一再比，
/// 避免用户选同一天（时间戳不同）时被判定为逆序。
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// `yyyy-MM-dd`（例：2026-09-21）。
String formatDateYmd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
