/// 哔哩轻小说 (linovelib.com) 网页爬虫 —— 第二数据源
///
/// 实测可用接口（2026-11，全部匿名无需登录，UTF-8 编码）：
/// - 排行榜：`/top/monthvisit.html`、`/top/weekvisit.html`、`/top/allvisit.html`
/// - 书页：`/novel/{nid}.html` → 标题/作者/封面/简介
/// - 目录：`/novel/{nid}/catalog` → 卷 + 章节链接 `/novel/{nid}/{cid}.html`
/// - 正文：`/novel/{nid}/{cid}.html` → id="TextContent" 内 `<p>` 段落
/// - 搜索：`/s/{关键词}.html`（部分地区网络可能受限，失败时回退本地 wenku8 目录）
///
/// nid: linovelib 小说 ID；cid: 章节 ID（如 128988）
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'wenku8_api.dart' show RateGate;

class LinovelibApi {
  static const base = 'https://www.linovelib.com';
  static const ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  final http.Client _client;
  final RateGate _gate = RateGate();
  final Map<String, (Book, List<Volume>)> _tocCache = {};

  LinovelibApi({http.Client? client}) : _client = client ?? http.Client();

  Future<String> _get(String path, {int retries = 2}) async {
    await _gate.wait();
    Object? lastErr;
    for (var i = 0; i <= retries; i++) {
      try {
        final resp = await _client
            .get(
              Uri.parse('$base$path'),
              headers: {
                'User-Agent': ua,
                'Referer': '$base/',
                'Accept': 'text/html,application/xhtml+xml',
                'Accept-Language': 'zh-CN,zh;q=0.9',
              },
            )
            .timeout(const Duration(seconds: 20));
        if (resp.statusCode == 200) return utf8.decode(resp.bodyBytes);
        lastErr = Wenku8Exception('HTTP ${resp.statusCode}: $path');
      } catch (e) {
        lastErr = e;
      }
      if (i < retries) await Future.delayed(Duration(milliseconds: 800 * (i + 1)));
    }
    throw Wenku8Exception('linovelib 请求失败: $lastErr');
  }

  // ============ 排行榜 ============

  /// 排行榜书籍列表。period: weekvisit/monthvisit/allvisit
  Future<List<Book>> ranking({String period = 'monthvisit'}) async {
    final html = await _get('/top/$period.html');
    final books = <Book>[];
    final seen = <String>{};
    for (final m in _rankLink.allMatches(html)) {
      final nid = m.group(1)!;
      final title = m.group(2)!.trim();
      if (seen.contains(nid) || title.isEmpty || title.length < 2) continue;
      seen.add(nid);
      books.add(Book(
        aid: 'lino_$nid',
        title: title,
        coverUrl: coverUrl(nid),
        source: BookSource.linovelib,
      ));
      if (books.length >= 30) break;
    }
    return books;
  }

  static final RegExp _rankLink =
      RegExp(r'<a[^>]*href="/novel/(\d+)\.html"[^>]*title="([^"]{2,60})"');

  // ============ 书页 ============

  Future<Book> bookInfo(String nid) async {
    final html = await _get('/novel/$nid.html');
    final title = RegExp(r'<h1[^>]*>([^<]+)</h1>').firstMatch(html)?.group(1)?.trim();
    final author = RegExp(r'author[^>]*>\s*<a[^>]*>([^<]+)</a>', caseSensitive: false)
            .firstMatch(html)
            ?.group(1)
            ?.trim() ??
        RegExp(r'<meta name="author" content="([^"]+)"').firstMatch(html)?.group(1);
    final intro = RegExp(r'<meta name="description" content="([^"]+)"')
        .firstMatch(html)
        ?.group(1)
        ?.trim();
    // 真实封面：/files/article/image/{n}/{nid}/{nid}s.jpg
    final n = int.tryParse(nid) ?? 0;
    final cover =
        RegExp(r'(https?:\/\/www\.linovelib\.com)?\/files\/article\/image\/\d+\/\d+\/\d+s\.jpg')
                .firstMatch(html)
                ?.group(0) ??
            '/files/article/image/${n ~/ 1000}/$nid/${nid}s.jpg';

    return Book(
      aid: 'lino_$nid',
      title: title ?? 'linovelib #$nid',
      author: author ?? '',
      intro: _cleanIntro(intro),
      coverUrl: cover.startsWith('http') ? cover : '$base$cover',
      source: BookSource.linovelib,
    );
  }

  // ============ 目录 ============

  Future<List<Volume>> toc(String nid) async {
    final cached = _tocCache[nid];
    if (cached != null) return cached.$2;

    final html = await _get('/novel/$nid/catalog');
    final volumes = <Volume>[];

    // 卷：`<div class="volume clearfix" data-category="N">` 内 `<h3>` 卷名 + 章节列表
    // 容错方案：按章节链接顺序切卷
    final volTitleRe = RegExp(r'<h3[^>]*>([^<]+)</h3>');
    final chRe = RegExp(r'<a[^>]*href="/novel/\d+/(\d+)\.html"[^>]*>\s*([^<]+?)\s*</a>');

    final h3s = volTitleRe.allMatches(html).toList();
    final matches = chRe.allMatches(html).toList();

    if (h3s.length >= 2) {
      // 每个 h3（卷标题）作为分界：收集它之后到下一个 h3 之间的章节
      for (var vi = 0; vi < h3s.length; vi++) {
        final volTitle = h3s[vi].group(1)!.trim();
        final start = h3s[vi].end;
        final end = vi + 1 < h3s.length ? h3s[vi + 1].start : html.length;
        final seg = html.substring(start, end);
        final chs = chRe
            .allMatches(seg)
            .map((m) => Chapter(
                  aid: nid,
                  cid: m.group(1)!,
                  title: m.group(2)!.trim(),
                  volumeTitle: volTitle,
                ))
            .toList();
        if (chs.isNotEmpty) {
          volumes.add(Volume(vid: 'lv$vi', title: volTitle, chapters: chs));
        }
      }
    } else {
      // 无卷结构：全部放一个卷
      final chs = chRe
          .allMatches(html)
          .map((m) => Chapter(
                aid: nid,
                cid: m.group(1)!,
                title: m.group(2)!.trim(),
                volumeTitle: '正文',
              ))
          .toList();
      if (chs.isNotEmpty) {
        volumes.add(Volume(vid: 'lv0', title: '正文', chapters: chs));
      }
    }

    if (volumes.isEmpty) throw Wenku8Exception('linovelib 目录解析失败: $nid');
    final result = (await bookInfo(nid), volumes);
    _tocCache[nid] = result;
    if (_tocCache.length > 20) _tocCache.remove(_tocCache.keys.first);
    return volumes;
  }

  // ============ 章节正文 ============

  /// 抓取章节正文。linovelib 长章节会分页（下一页），自动聚合。
  Future<String> chapter(String nid, String cid) async {
    final buf = StringBuffer();
    var path = '/novel/$nid/$cid.html';
    var visited = 0;

    while (path != null && visited < 30) {
      final html = await _get(path);
      buf.write(_extractContent(html));
      if (buf.isNotEmpty) buf.write('\n');

      // 分页：找 "下一页"（而非 "下一章"）链接
      final next = RegExp(
              r'<a[^>]*href="(/novel/\d+/\d+[_\d]*\.html)"[^>]*>\s*下一页\s*</a>')
          .firstMatch(html)
          ?.group(1);
      // 下一页 URL 带 _2/_3 后缀；若与当前相同则停止
      final cur = path.split('/').last;
      if (next == null || next.split('/').last == cur) break;
      path = next;
      visited++;
    }

    final text = buf.toString().trim();
    if (text.isEmpty) throw Wenku8Exception('linovelib 章节内容为空: $nid/$cid');
    return text;
  }

  /// 提取 id="TextContent" 内的段落文本
  String _extractContent(String html) {
    final start = html.indexOf('id="TextContent"');
    if (start < 0) return '';
    // 取到正文容器结束（粗略：取接下来的 60KB）
    final seg = html.substring(start, start + 60000 < html.length ? start + 60000 : html.length);
    final paras = <String>[];
    for (final m in RegExp(r'<p>([\s\S]*?)</p>').allMatches(seg)) {
      var t = m.group(1)!
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&amp;', '&')
          .replaceAll(RegExp(r'&#\d+;'), '')
          .trim();
      if (t.isEmpty) continue;
      // 过滤广告/推广行
      if (t.contains('哔哩轻小说') && t.length < 30) continue;
      if (RegExp(r'(app|手机|客户端|广告|www\.|https?://)').hasMatch(t) && t.length < 40) continue;
      paras.add(t);
    }
    return paras.join('\n');
  }

  String _cleanIntro(String? s) {
    if (s == null) return null;
    return s
        .replaceAll(RegExp(r'内容简介[：:]?'), '')
        .trim();
  }

  /// 封面 URL（固定模式：/files/article/image/{n}/{nid}/{nid}s.jpg）
  static String coverUrl(String nid) {
    final n = int.tryParse(nid) ?? 0;
    return '$base/files/article/image/${n ~/ 1000}/$nid/${nid}s.jpg';
  }

  // ============ 搜索 ============

  /// 在线搜索（部分地区网络可能被拒；失败返回空并抛 Wenku8Exception）
  Future<List<Book>> search(String keyword, {int limit = 20}) async {
    final kw = Uri.encodeComponent(keyword);
    try {
      final html = await _get('/s/$kw.html');
      final books = <Book>[];
      final seen = <String>{};
      for (final m in RegExp(
              r'<a[^>]*href="/novel/(\d+)\.html"[^>]*title="([^"]{2,60})"')
          .allMatches(html)) {
        final nid = m.group(1)!;
        if (seen.contains(nid)) continue;
        seen.add(nid);
        books.add(Book(
          aid: 'lino_$nid',
          title: m.group(2)!.trim(),
          coverUrl: coverUrl(nid),
          source: BookSource.linovelib,
        ));
        if (books.length >= limit) break;
      }
      return books;
    } catch (e) {
      throw Wenku8Exception('linovelib 搜索不可用（可能是网络限制），请使用 wenku8 本地目录搜索');
    }
  }

  void dispose() => _client.close();
}
