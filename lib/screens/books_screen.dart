import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_palette.dart';
import '../config/edit_results.dart';
import '../models/book.dart';
import '../providers/library_provider.dart';
import '../widgets/book_list_card.dart';
import '../widgets/filter_dropdown.dart';
import '../widgets/search_bar_widget.dart';
import 'book_detail_screen.dart';
import 'book_edit_screen.dart';

/// 图书库主页面（替换原占位页）
///
/// 对齐参考图 1：
/// - 顶部搜索栏（书名/作者实时过滤）
/// - 阅读进度 + 图书分类两个下拉筛选（可组合）
/// - 双排卡片网格（BookListCard）
/// - 单击 → 详情页；长按 → 编辑页
class BooksScreen extends StatefulWidget {
  const BooksScreen({super.key, this.initialQuery = ''});

  /// 初始搜索词：书籍详情点「作者」跳转时预填，进入即按作者过滤
  final String initialQuery;

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  late final TextEditingController _searchCtrl;
  late String _query;
  BookStatus? _statusFilter;
  String? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.initialQuery);
    _query = widget.initialQuery;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // H6/M6：select 只订阅书库列表引用（provider 侧有缓存），个人页/电影
    // 等无关变化不再触发本页 rebuild；过滤方法经 read 调用，数据同源。
    final library = context.read<LibraryProvider>();
    final allBooks =
        context.select<LibraryProvider, List<Book>>((p) => p.books);
    final books = library.getFilteredBooks(
      query: _query,
      status: _statusFilter,
      category: _categoryFilter,
      source: allBooks,
    );
    // 分类筛选候选：预设 ∪ 书库实际使用过的分类（自定义分类可筛）
    final categoryOptions = <String>{
      ...kBookCategories,
      ...library.usedCategories,
    }.toList();
    // 防御：当前筛选值因删书等原因不在候选中时补回，避免 Dropdown 值断言失败
    if (_categoryFilter != null && !categoryOptions.contains(_categoryFilter)) {
      categoryOptions.insert(0, _categoryFilter!);
    }

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          '书籍',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        // 唯一 heroTag：避免与电影列表页 FAB 在 IndexedStack 同一 Hero 子树中默认 tag 冲突
        heroTag: 'books-add-fab',
        backgroundColor: context.colors.readingStart,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          '添加图书',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---------- 搜索栏 ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: SearchBarWidget(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 12),
            // ---------- 筛选栏 ----------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  FilterDropdown<BookStatus?>(
                    icon: Icons.auto_stories_rounded,
                    value: _statusFilter,
                    items: [
                      const FilterItem(label: '全部状态', value: null),
                      for (final s in BookStatus.values)
                        FilterItem(label: s.label, value: s),
                    ],
                    onChanged: (v) => setState(() => _statusFilter = v),
                  ),
                  const SizedBox(width: 10),
                  FilterDropdown<String?>(
                    icon: Icons.category_rounded,
                    value: _categoryFilter,
                    items: [
                      const FilterItem(label: '全部分类', value: null),
                      for (final c in categoryOptions)
                        FilterItem(label: c, value: c),
                    ],
                    onChanged: (v) => setState(() => _categoryFilter = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // ---------- 结果计数行 ----------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                '共 ${books.length} 本',
                style:  TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 6),
            // ---------- 双排网格 ----------
            Expanded(
              child: books.isEmpty
                  ? _buildEmpty()
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.56,
                      ),
                      itemCount: books.length,
                      itemBuilder: (context, i) {
                        final book = books[i];
                        return BookListCard(
                          book: book,
                          onTap: () => _openDetail(book.id),
                          onLongPress: () => _openEditor(book.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 导航 ----------

  void _openDetail(String bookId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BookDetailScreen(bookId: bookId)),
    );
  }

  Future<void> _openEditor(String bookId) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => BookEditScreen(bookId: bookId)),
    );
    // 删除返回后无需额外处理：Provider 已移除该书，网格自动刷新
    if (result == kEditResultDeleted) {
      messenger.showSnackBar(const SnackBar(content: Text('图书已删除')));
    }
  }

  /// FAB 新增入口：不传 bookId → 编辑页自动进入新增模式
  Future<void> _openCreate() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BookEditScreen()),
    );
    if (result == kEditResultSaved && messenger.mounted) {
      messenger.showSnackBar(const SnackBar(content: Text('图书已添加')));
    }
  }

  // ---------- 空状态 ----------

  Widget _buildEmpty() {
    final hasFilter =
        _query.isNotEmpty || _statusFilter != null || _categoryFilter != null;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasFilter ? Icons.search_off_rounded : Icons.menu_book_rounded,
            size: 52,
            color: context.colors.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 14),
          Text(
            hasFilter ? '没有找到匹配的图书' : '书库空空如也',
            style:  TextStyle(
              color: context.colors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasFilter) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => setState(() {
                _query = '';
                _searchCtrl.clear();
                _statusFilter = null;
                _categoryFilter = null;
              }),
              child: const Text('清除筛选条件'),
            ),
          ],
        ],
      ),
    );
  }
}
