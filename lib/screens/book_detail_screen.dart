import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../models/book.dart';
import '../providers/library_provider.dart';
import '../widgets/media_cover.dart';
import '../widgets/rating_stars.dart';
import 'book_edit_screen.dart';
import 'books_screen.dart';

/// 图书详情界面
///
/// 布局对齐参考图 2：顶部大尺寸封面 → 标题/作者/元信息 →
/// 星级评分区 → 大型渐变进度条卡片 → 阅读感悟显示框。
/// AppBar 右上角提供「编辑」入口；从编辑页删除后自动返回上一页。
class BookDetailScreen extends StatelessWidget {
  const BookDetailScreen({super.key, required this.bookId});

  final String bookId;

  Future<void> _openEditor(BuildContext context) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => BookEditScreen(bookId: bookId),
      ),
    );
    // 编辑页里删除了这本书 → 详情页随之关闭
    if (result == kEditResultDeleted && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final matches = library.books.where((b) => b.id == bookId).toList();
    final book = matches.isEmpty ? null : matches.first;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_rounded, color: AppColors.textPrimary),
            onPressed: book == null ? null : () => _openEditor(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: book == null
          ? const Center(
              child: Text(
                '这本书已从书库移除',
                style: TextStyle(color: AppColors.textMuted),
              ),
            )
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ---------- 大封面 ----------
                    Center(
                      child: Container(
                        width: 190,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 22,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: MediaCover(
                            media: book.cover,
                            title: book.title,
                            emoji: book.emoji ?? '',
                            hue: book.coverHue,
                            aspectRatio: 3 / 4,
                            borderRadius: 0,
                            fontSize: 60,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    // ---------- 标题与作者 ----------
                    Text(
                      book.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 作者行可点：跳书库列表并带作者 query（复用现有搜索，零新增检索逻辑）
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              BooksScreen(initialQuery: book.author),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                book.author,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.manage_search_rounded,
                                size: 15, color: AppColors.textMuted),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 元信息行：分类 chip + 年份
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (book.category != null) ...[
                          _InfoChip(label: book.category!),
                          const SizedBox(width: 8),
                        ],
                        if (book.year != null)
                          Text(
                            '${book.year}',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    // ---------- 内容简介 ----------
                    if (book.description != null &&
                        book.description!.isNotEmpty) ...[
                      _sectionTitle(context, '内容简介'),
                      const SizedBox(height: 10),
                      _ExpandableSynopsis(text: book.description!),
                      const SizedBox(height: 26),
                    ],
                    // ---------- 评分区 ----------
                    _buildRatingArea(book),
                    const SizedBox(height: 22),
                    // ---------- 大型进度条 ----------
                    _buildProgressCard(book),
                    // ---------- 阅读时间信息卡（无任何时间记录时隐藏）----------
                    ..._readingTimeCard(book),
                    const SizedBox(height: 26),
                    // ---------- 阅读感悟显示框 ----------
                    _sectionTitle(context, '阅读感悟'),
                    const SizedBox(height: 10),
                    _buildNotesBox(book),
                    const SizedBox(height: 14),
                    Text(
                      '点击右上角编辑图标可更新评分、进度与感悟',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textMuted.withOpacity(0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // ---------- 评分区 ----------

  Widget _buildRatingArea(Book book) {
    final rating = book.rating;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outline, width: 0.7),
      ),
      child: Column(
        children: [
          if (rating != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text(
                    '/ 5',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            RatingStars(rating: rating, size: 30),
          ] else ...[
            const Icon(Icons.star_border_rounded,
                color: AppColors.textMuted, size: 40),
            const SizedBox(height: 6),
            const Text(
              '还没有评分',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  // ---------- 渐变进度大卡 ----------

  Widget _buildProgressCard(Book book) {
    final percent = book.progressPercent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        gradient: AppColors.readingGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.readingStart.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                '阅读进度',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$percent%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 细进度条（深色底 + 白色高光）
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 8,
              color: Colors.black.withOpacity(0.25),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (percent / 100).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.menu_book_rounded,
                  size: 14, color: Colors.white70),
              const SizedBox(width: 6),
              Text(
                '已读 ${book.currentPage} / ${book.totalPages} 页',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12.5,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  book.status.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 阅读时间信息卡 ----------

  /// 返回阅读时间卡片片段（开始/完成均无记录时返回空，整块隐藏）
  List<Widget> _readingTimeCard(Book book) {
    final start = book.startedAt;
    final finish = book.finishedAt;
    if (start == null && finish == null) return const [];

    final rows = <Widget>[];
    if (start != null) {
      rows.add(_timeRow(
        icon: Icons.play_circle_outline_rounded,
        label: '开始阅读',
        value: _fmtYmd(start),
      ));
    }
    if (finish != null) {
      rows.add(_timeRow(
        icon: Icons.check_circle_outline_rounded,
        label: '阅读完成',
        value: _fmtYmd(finish),
        // 完成 + 开始都存在时展示历时
        trailing: start != null ? '历时 ${book.readingDays} 天' : null,
      ));
    }

    return [
      const SizedBox(height: 26),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.outline, width: 0.7),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              rows[i],
            ],
          ],
        ),
      ),
    ];
  }

  Widget _timeRow({
    required IconData icon,
    required String label,
    required String value,
    String? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AppColors.readingStart),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.readingStart.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              trailing,
              style: TextStyle(
                color: AppColors.readingStart.withOpacity(0.9),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _fmtYmd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ---------- 感悟显示框 ----------

  Widget _buildNotesBox(Book book) {
    final notes = book.notes;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline, width: 0.7),
      ),
      child: notes == null || notes.isEmpty
          ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.edit_note_rounded,
                    size: 16, color: AppColors.textMuted),
                SizedBox(width: 6),
                Text(
                  '还没有写下感悟',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            )
          : Text(
              notes,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.7,
              ),
            ),
    );
  }

  // ---------- 辅助 ----------

  Widget _sectionTitle(BuildContext context, String text) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            gradient: AppColors.readingGradient,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// 分类小胶囊
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: AppColors.accent.withOpacity(0.35), width: 0.8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.accent,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 内容简介文本块（超过 4 行自动折叠，可展开/收起）
class _ExpandableSynopsis extends StatefulWidget {
  const _ExpandableSynopsis({required this.text});

  final String text;

  @override
  State<_ExpandableSynopsis> createState() => _ExpandableSynopsisState();
}

class _ExpandableSynopsisState extends State<_ExpandableSynopsis> {
  static const int _foldLines = 4;

  bool _expanded = false;
  bool _overflow = false;
  bool _measured = false;

  @override
  void didUpdateWidget(covariant _ExpandableSynopsis oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 简介内容变化（如编辑后返回）时重新测量折叠状态
    if (oldWidget.text != widget.text) {
      _measured = false;
      _overflow = false;
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline, width: 0.7),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!_measured) {
            _measured = true;
            const style = TextStyle(
              fontSize: 14,
              height: 1.7,
              color: AppColors.textSecondary,
            );
            final span = TextSpan(text: widget.text, style: style);
            final collapsed = TextPainter(
              text: span,
              maxLines: _foldLines,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: constraints.maxWidth);
            final full = TextPainter(
              text: span,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: constraints.maxWidth);
            // 完整高度 > 折叠行高 → 需要「展开」入口
            final needFold = full.height > collapsed.height + 1;
            if (needFold != _overflow) {
              _overflow = needFold;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            }
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.text,
                maxLines: _expanded ? null : _foldLines,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.7,
                  color: AppColors.textSecondary,
                ),
              ),
              if (_overflow)
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _expanded ? '收起' : '展开全部',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent,
                            ),
                          ),
                          Icon(
                            _expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 16,
                            color: AppColors.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
