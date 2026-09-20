/// 书籍分类中文化映射（联网检索回填专用）
///
/// 背景：OpenLibrary / Google Books 返回的是英文主题词
/// （`Fiction` / `Science fiction` / `Biography`…），而本地书库的分类体系
/// 是 `models/book.dart` 中 [kBookCategories] 的中文标签（科幻 / 文学 / 传记…）。
/// 直接回填英文会让「分类筛选」按中文标签匹配时失效。
///
/// 约定：
/// - 映射只在**回填表单时**执行（见 book_edit_screen 的 `_applyBookResult`），
///   数据源层保持原始英文主题词不变，保留可溯源的真实数据；
/// - 规则自上而下按优先级匹配，**具体的先命中**
///   （如 `Science fiction` 命中「科幻」而不是兜底的「文学」）；
/// - 无法映射时返回原始主题词，交由用户手动改，不猜测。
library;

/// 英文主题词 → 本地中文分类的映射器
class BookCategoryMapper {
  const BookCategoryMapper._();

  /// 匹配规则（数组顺序即优先级，越靠前越优先命中）
  ///
  /// 全部目标值均取自 `kBookCategories`，由
  /// `test/book_fill_regression_test.dart` 断言一致性。
  static const List<_CategoryRule> _rules = <_CategoryRule>[
    _CategoryRule('反乌托邦', <String>[
      'dystopia',
      'dystopian',
      'utopia',
      'totalitarian',
    ]),
    _CategoryRule('魔幻现实主义', <String>['magic realism', 'magical realism']),
    _CategoryRule('传记', <String>[
      'biography',
      'autobiography',
      'memoir',
      'diaries',
    ]),
    _CategoryRule('悬疑', <String>[
      'mystery',
      'detective',
      'crime',
      'thriller',
      'suspense',
      'noir',
    ]),
    _CategoryRule('科幻', <String>[
      'science fiction',
      'sci-fi',
      'cyberpunk',
      'space opera',
      'speculative fiction',
    ]),
    _CategoryRule('奇幻', <String>['fantasy', 'fairy tale', 'mythology']),
    _CategoryRule('历史', <String>['history', 'historical', 'ancient']),
    _CategoryRule('经典', <String>['classic']),
    // 兜底：最泛的文学类 + 高频但本地体系无对应项的主题
    _CategoryRule('文学', <String>[
      'fiction',
      'literature',
      'novel',
      'prose',
      'short stor',
      'poetry',
      'adventure',
      'love stor',
      'romance',
      'young adult',
      'children',
    ]),
  ];

  /// 把原始英文主题词列表映射为本地中文分类。
  ///
  /// [subjects] 全空 → 返回 null（表单保持原值）；
  /// 命中任一规则 → 返回对应中文分类；
  /// 全部未命中 → 返回第一个非空原始主题词（不猜测，供用户手改）。
  static String? map(List<String> subjects) {
    for (final rule in _rules) {
      for (final subject in subjects) {
        final lower = subject.toLowerCase();
        if (rule.keywords.any((kw) => lower.contains(kw))) return rule.zh;
      }
    }
    for (final subject in subjects) {
      final trimmed = subject.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}

/// 单条规则：命中任一关键词 → 映射到 [zh]
class _CategoryRule {
  const _CategoryRule(this.zh, this.keywords);

  /// 目标中文分类（取值来自 `kBookCategories`）
  final String zh;

  /// 关键词（小写子串匹配）
  final List<String> keywords;
}
