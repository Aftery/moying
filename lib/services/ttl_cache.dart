import 'dart:collection';

/// 进程内 TTL + LRU 缓存
///
/// **为什么放在 Provider 而不是各个数据源实现里**：数据源实现有
/// 「不持有可变状态」的契约（见 [BookDataSource] 文档），缓存塞进去就破坏它，
/// 而且每个源都要写一遍。放在调用方（Provider）则所有源一次性受益。
///
/// 目标场景：国内访问 OpenLibrary / Google Books 常需 2–5s，自建代理首跳
/// 还可能撞上冷启动。同一关键词反复检索、同一本书反复取详情都属于重复劳动——
/// 缓存命中即省掉整次网络往返。
///
/// 语义：
/// - [get] 命中且未过期返回值；**已过期顺手逐出**并返回 null；
/// - 容量满时按 LRU 逐出最久未使用的一项；
/// - 时钟可注入（[clock]），测试不必真的等 TTL 到期。
class TtlCache<K, V> {
  TtlCache({
    required this.ttl,
    this.maxEntries = 64,
    DateTime Function()? clock,
  })  : assert(maxEntries > 0, '容量上限必须为正'),
        _clock = clock ?? DateTime.now;

  /// 条目存活时长
  final Duration ttl;

  /// 容量上限（超出按 LRU 逐出）
  final int maxEntries;

  final DateTime Function() _clock;

  /// LinkedHashMap 保持插入/访问顺序：重插即移到队尾，队首即最久未使用
  final LinkedHashMap<K, _Entry<V>> _entries = LinkedHashMap<K, _Entry<V>>();

  /// 当前缓存条目数（含尚未被读到的过期条目）
  int get length => _entries.length;

  /// 读缓存；未命中或已过期返回 null
  V? get(K key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (_isExpired(entry)) return null;
    _entries[key] = entry; // 移到队尾 = 标记为最近使用
    return entry.value;
  }

  /// 探测是否命中，**不提权**（不改变 LRU 顺序），供断言/统计使用
  bool containsKey(K key) {
    final entry = _entries[key];
    return entry != null && !_isExpired(entry);
  }

  void put(K key, V value) {
    _entries.remove(key); // 覆盖时先摘掉旧位置，保证顺序正确
    _entries[key] = _Entry<V>(value, _clock());
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();

  bool _isExpired(_Entry<V> entry) =>
      _clock().difference(entry.storedAt) >= ttl;
}

class _Entry<V> {
  _Entry(this.value, this.storedAt);

  final V value;
  final DateTime storedAt;
}
