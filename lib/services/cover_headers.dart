/// 封面图请求头解析
///
/// **为什么需要**：豆瓣图床（`img1.doubanio.com` / `img3…` / `img9…`）有反盗链，
/// 不带 `Referer` 的请求一律返回 `HTTP 418` + 响应体 `cdn error 001`；
/// 带上 `Referer: https://book.douban.com/` 才是正常图片（实测 29 万–34 万字节）。
///
/// 应用侧的封面加载点是 `Image.network`，**默认不带任何请求头**，
/// 所以即便数据源给出的是豆瓣原图直链，手机上也会吃 418 → 封面全空。
/// 这里按主机名判定，只给豆瓣域补 Referer，其他源（OpenLibrary /
/// Google Books / TMDB）一个字节都不多带。
library;

/// 豆瓣图床/站点域名统一使用的 Referer（豆瓣自己校验的就是这个值）
const String kDoubanReferer = 'https://book.douban.com/';

/// 按封面 URL 生成所需的请求头；无需附加时返回 null
/// （`Image.network` 的 headers 传 null 与传空 Map 等价，返回 null 更省一次分配）。
Map<String, String>? coverHeadersFor(String? url) {
  if (url == null) return null;
  if (!isDoubanImageHost(url)) return null;
  return const {'Referer': kDoubanReferer};
}

/// URL 是否落在豆瓣域下（含 `doubanio.com` 图床与 `douban.com` 主站）
///
/// 判定用「等于或后缀匹配」，避免 `evil-doubanio.com` 这类伪造串被误命中。
bool isDoubanImageHost(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) return false;
  return _hostMatches(host, 'doubanio.com') || _hostMatches(host, 'douban.com');
}

bool _hostMatches(String host, String domain) =>
    host == domain || host.endsWith('.$domain');
