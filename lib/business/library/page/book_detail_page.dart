import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../component/theme/app_palette.dart';
import '../../../foundation/constants/app_strings.dart';
import '../model/edit_result.dart';
import '../model/book.dart';
import '../view_model/library_provider.dart';
import '../view/detail_common.dart';
import '../../../component/media/media_cover.dart';
import '../view/rating_stars.dart';
import 'book_edit_page.dart';
import 'books_page.dart';
import '../view/book_detail_view.dart';

/// 图书详情界面（v2 布局）
///
/// 布局对齐参考图 1：
/// - 顶部返回 / 编辑沿用系统 AppBar（与电影详情页保持一致）
/// - 封面居左，右侧标题 / 作者 / 我的评分卡 / 出版社与分类标签
/// - 阅读进度卡（百分比大字 + 进度条）
/// - 2×2 信息卡（阅读状态 / 出版年份 / 总页数 / ISBN）
/// - 内容简介（可折叠纯文本）→ 阅读感悟 & 划线卡（含「修改」入口）
class BookDetailPage extends StatelessWidget {
  const BookDetailPage({super.key, required this.bookId});

  final String bookId;

  Future<void> _openEditor(BuildContext context) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => BookEditPage(bookId: bookId),
      ),
    );
    // 编辑页里删除了这本书 → 详情页随之关闭
    if (result == kEditResultDeleted && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // H6/M6：select 只订阅书库列表引用；个人页/主题等无关变化不再触发重建
    final books = context.select<LibraryProvider, List<Book>>((p) => p.books);
    final matches = books.where((b) => b.id == bookId).toList();
    final book = matches.isEmpty ? null : matches.first;

    return Scaffold(
      backgroundColor: context.colors.background,
      // 头部与电影详情页统一：系统默认返回箭头 + 普通编辑图标按钮。
      // 此前这里用自绘圆底悬浮按钮，两页风格与尺寸都不一致，返回箭头也显突兀。
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '编辑',
            icon: Icon(Icons.edit_rounded, color: context.colors.textPrimary),
            onPressed: book == null ? null : () => _openEditor(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: book == null
          ? Center(
              child: Text(
                '这本书已从书库移除',
                style: TextStyle(color: context.colors.textMuted),
              ),
            )
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(context, book),
                    const SizedBox(height: 20),
                    _buildProgressCard(context, book),
                    // 阅读时间卡（无任何时间记录时隐藏）
                    ..._readingTimeCard(context, book),
                    const SizedBox(height: 14),
                    _buildInfoGrid(context, book),
                    const SizedBox(height: 24),
                    // ---------- 内容简介 ----------
                    if (book.description != null &&
                        book.description!.isNotEmpty) ...[
                      _sectionTitle(context, AppStrings.synopsis),
                      const SizedBox(height: 10),
                      ExpandableSynopsis(text: book.description!),
                      const SizedBox(height: 24),
                    ],
                    // ---------- 阅读感悟 & 划线 ----------
                    _sectionTitle(context, AppStrings.bookNotes),
                    const SizedBox(height: 10),
                    _buildNotesCard(context, book),
                  ],
                ),
              ),
            ),
    );
  }

  // ---------- 头部：封面 + 标题 / 作者 / 评分 / 标签 ----------

  Widget _buildHeader(BuildContext context, Book book) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 封面
        Container(
          width: 116,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MediaCover(
              media: book.cover,
              title: book.title,
              emoji: book.emoji ?? '',
              hue: book.coverHue,
              aspectRatio: 3 / 4,
              borderRadius: 0,
              fontSize: 40,
            ),
          ),
        ),
        const SizedBox(width: 16),
        // 右侧信息列
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              // 作者行可点：跳书库列表并带作者 query（复用现有搜索）
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        BooksPage(initialQuery: book.author),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          book.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Icon(Icons.manage_search_rounded,
                          size: 14, color: context.colors.textMuted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildRatingCard(context, book),
              const SizedBox(height: 12),
              // 出版社 / 分类标签
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (book.publisher != null &&
                      book.publisher!.trim().isNotEmpty)
                    InfoChip(label: book.publisher!.trim()),
                  if (book.category != null) InfoChip(label: book.category!),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- 我的评分卡 ----------

  Widget _buildRatingCard(BuildContext context, Book book) {
    final rating = book.rating;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: rating == null
          ? Row(
              children: [
                Icon(Icons.star_border_rounded,
                    size: 16, color: context.colors.textMuted),
                const SizedBox(width: 6),
                Text(
                  AppStrings.unrated,
                  style: TextStyle(color: context.colors.textMuted, fontSize: 12.5),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.myRating,
                  style: TextStyle(
                    color: context.colors.success,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    RatingStars(rating: rating, size: 19),
                    const SizedBox(width: 8),
                    Text(
                      rating.toStringAsFixed(1),
                      style: TextStyle(
                        color: context.colors.star,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  // ---------- 阅读进度卡 ----------

  Widget _buildProgressCard(BuildContext context, Book book) {
    final percent = book.progressPercent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(Icons.menu_book_rounded,
                  size: 15, color: context.colors.textSecondary),
              const SizedBox(width: 7),
              Text(
                '阅读进度',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '$percent%',
                style: TextStyle(
                  color: context.colors.accent,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '已读 ${book.currentPage} / ${book.totalPages} 页',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Container(
              height: 8,
              color: context.colors.surface,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (percent / 100).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: context.colors.accent,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 2×2 信息卡 ----------

  Widget _buildInfoGrid(BuildContext context, Book book) {
    final statusColor = switch (book.status) {
      BookStatus.reading => context.colors.success,
      BookStatus.finished => context.colors.star,
      BookStatus.planToRead => context.colors.accent,
    };
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.9,
      children: [
        InfoCell(
          context: context,
          icon: Icons.bookmark_rounded,
          color: statusColor,
          label: '阅读状态',
          value: book.status.label,
        ),
        InfoCell(
          context: context,
          icon: Icons.calendar_today_rounded,
          color: context.colors.accent,
          label: AppStrings.publishYear,
          value: book.year == null ? '—' : '${book.year}',
        ),
        InfoCell(
          context: context,
          icon: Icons.auto_stories_rounded,
          color: context.colors.textSecondary,
          label: '总页数',
          value: '${book.totalPages} 页',
        ),
        InfoCell(
          context: context,
          icon: Icons.tag_rounded,
          color: context.colors.accent,
          label: AppStrings.isbnLabel,
          value: (book.isbn == null || book.isbn!.isEmpty) ? '—' : book.isbn!,
        ),
      ],
    );
  }

  // ---------- 阅读时间信息卡（无任何时间记录时隐藏）----------

  List<Widget> _readingTimeCard(BuildContext context, Book book) {
    final start = book.startedAt;
    final finish = book.finishedAt;
    if (start == null && finish == null) return const [];

    final rows = <Widget>[];
    if (start != null) {
      rows.add(_timeRow(context,
        icon: Icons.play_circle_outline_rounded,
        label: AppStrings.readingStart,
        value: _fmtYmd(start),
      ));
    }
    if (finish != null) {
      rows.add(_timeRow(context,
        icon: Icons.check_circle_outline_rounded,
        label: AppStrings.readingFinished,
        value: _fmtYmd(finish),
        trailing: start != null ? '历时 ${book.readingDays} 天' : null,
      ));
    }

    return [
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: context.colors.surfaceHigh,
          borderRadius: BorderRadius.circular(18),
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

  Widget _timeRow(BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    String? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, size: 17, color: context.colors.readingStart),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: context.colors.readingStart.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              trailing,
              style: TextStyle(
                color: context.colors.readingStart.withOpacity(0.9),
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

  // ---------- 阅读感悟 & 划线卡 ----------

  Widget _buildNotesCard(BuildContext context, Book book) {
    final notes = book.notes;
    final hasNotes = notes != null && notes.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasNotes ? notes : '还没有写下感悟',
            style: TextStyle(
              color: hasNotes
                  ? context.colors.textSecondary
                  : context.colors.textMuted,
              fontSize: 14,
              height: 1.7,
              fontStyle: hasNotes ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: EditPill(onTap: () => _openEditor(context)),
          ),
        ],
      ),
    );
  }

  // ---------- 辅助 ----------

  Widget _sectionTitle(BuildContext context, String text) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 4,
          decoration: BoxDecoration(
            color: context.colors.accent,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// 「修改」胶囊按钮（感悟卡右下角）
