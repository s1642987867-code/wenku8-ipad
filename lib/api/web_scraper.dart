/// wenku8.net 网页爬虫（在线阅读引擎，匿名无需登录）
///
/// 数据链路（全部实测可用，2026-11）：
/// - 书页：`https://www.wenku8.net/book/{aid}.htm` → 标题/作者/封面/简介/index链接
/// - 目录：`/novel/{aid~/1000}/{aid}/index.htm` → `.vcss` 卷 + `.ccss` 章节链接
/// - 正文：`/novel/{aid~/1000}/{aid}/{cid}.htm` → `div#content`（栈法取闭合）
///
/// 所有页面 GBK 编码，用 decodeGbk() 解码。
/// 排行/搜索/分类需登录（当前 wenku8.net 登录已失效），用本地目录快照替代。
library;

import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../src/gbk.dart';
import 'wenku8_api.dart' show RateGate;

class WebScraper {
  static const base = 'https://www.wenku8.net';
  static const ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  final RateGate _gate = RateGate();
  final Map<String, (Book, List<Volume>)> _tocCache = {};

  /// 带限速的 HTTP GET（GBK 解码）
  Future<String> _get(String path, {String referer = '$base/', int attempts = 3}) async {
    var lastErr = '';
    for (var i = 0; i < attempts; i++) {
      await _gate.wait();
      try {
        final resp = await http
            .get(Uri.parse('$base$path'), headers: {'User-Agent': ua, 'Referer': referer})
            .timeout(const Duration(seconds: 25));
        if (resp.statusCode != 200) {
          lastErr = 'HTTP ${resp.statusCode}';
          await Future.delayed(Duration(milliseconds: 1200 * (i + 1)));
          continue;
        }
        return decodeGbk(resp.bodyBytes);
      } catch (e) {
        lastErr = e.toString();
        await Future.delayed(Duration(milliseconds: 600 * (i + 1)));
      }
    }
    throw Wenku8Exception('在线抓取失败: $lastErr');
  }

  /// 小说路径：`/novel/{aid~/1000}/{aid}/`
  String novelDir(String aid) {
    final n = int.tryParse(aid) ?? 0;
    return '/novel/${n ~/ 1000}/$aid';
  }

  /// 封面 URL
  static String coverUrl(String aid) {
    final n = int.tryParse(aid) ?? 0;
    return 'https://img.wenku8.com/image/${n ~/ 1000}/$aid/${aid}s.jpg';
  }

  /// 书页 → 完整 Book（含标题/作者/简介）
  Future<Book> bookInfo(String aid) async {
    final html = await _get('/book/$aid.htm');
    // 标题：<title>川之光 - 松浦寿辉 - 其他文库 - 轻小说文库</title>
    final fullTitle = RegExp(r'<title>([^<]+)</title>').firstMatch(html)?.group(1) ?? '';
    final parts = fullTitle.split(' - ');
    final title = parts.isNotEmpty ? parts[0].trim() : '文库作品 #$aid';
    final author = parts.length > 1 ? parts[1].trim() : '';

    // 简介：从书页内容区提取
    String? intro;
    final introMatch = RegExp(r'<span[^>]*style="[^"]*font-size:14px[^"]*"[^>]*>([\s\S]*?)</span>').firstMatch(html);
    if (introMatch != null) {
      intro = introMatch.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    }

    // 状态：从书页表格提取
    String? status;
    final statusMatch = RegExp(r'文章状态[^<]*<[^>]+>([^<]+)').firstMatch(html);
    if (statusMatch != null) {
      status = statusMatch.group(1)!.trim();
    }

    return Book(
      aid: aid,
      title: title,
      author: author,
      coverUrl: coverUrl(aid),
      status: status,
      intro: intro,
    );
  }

  /// 目录（卷章树）
  Future<(Book, List<Volume>)> toc(String aid) async {
    final cached = _tocCache[aid];
    if (cached != null) return cached;

    final html = await _get('${novelDir(aid)}/index.htm', referer: '$base/book/$aid.htm');
    final volumes = <Volume>[];

    // 卷行：<td class="vcss" colspan="4" vid="86070">第一卷 ...</td>
    // 章行：<td class="ccss"><a href="86071.htm">序章</a></td>
    final rowRe = RegExp(
        r'<td class="vcss"[^>]*>([^<]+)</td>|<td class="ccss"><a href="(\d+)\.htm"[^>]*>([^<]+)</a></td>');

    String? curVolTitle;
    List<Chapter>? curChapters;

    for (final m in rowRe.allMatches(html)) {
      if (m.group(1) != null) {
        // 卷标题
        curVolTitle = m.group(1)!.trim();
        curChapters = [];
        volumes.add(Volume(vid: 'v${volumes.length + 1}', title: curVolTitle, chapters: curChapters));
      } else if (m.group(2) != null && curChapters != null) {
        // 章节
        final cid = m.group(2)!;
        curChapters.add(Chapter(
          aid: aid,
          cid: 'w$cid', // w 前缀：网页章节
          title: m.group(3)!.trim(),
          volumeTitle: curVolTitle,
        ));
      }
    }

    if (volumes.isEmpty) {
      throw Wenku8Exception('目录解析失败（可能改版或该书无在线目录）');
    }

    // 从 index 页提取书名/作者
    final title = RegExp(r'<div id="title">([^<]+)</div>').firstMatch(html)?.group(1)?.trim() ??
        '文库作品 #$aid';
    final author = RegExp(r'<div id="info">作者：([^<]+)</div>').firstMatch(html)?.group(1)?.trim() ??
        '';

    final book = Book(
      aid: aid,
      title: title,
      author: author,
      coverUrl: coverUrl(aid),
    );

    final result = (book, volumes);
    if (_tocCache.length > 20) _tocCache.remove(_tocCache.keys.first);
    _tocCache[aid] = result;
    return result;
  }

  /// 章节正文（栈法提取 div#content）
  Future<String> chapter(String aid, String cid) async {
    final real = cid.startsWith('w') ? cid.substring(1) : cid;
    final html = await _get('${novelDir(aid)}/$real.htm', referer: '$base${novelDir(aid)}/index.htm');

    final start = html.indexOf('<div id="content">');
    if (start < 0) throw Wenku8Exception('正文容器缺失');

    // 栈法找配对 </div>
    var depth = 0;
    var end = -1;
    final divRe = RegExp(r'<div\b|</div>');
    for (final m in divRe.allMatches(html, start)) {
      if (m.group(0) == '<div') {
        depth++;
      } else {
        depth--;
        if (depth == 0) {
          end = m.end;
          break;
        }
      }
    }
    if (end < 0) end = html.length;

    final seg = html.substring(start, end);
    var txt = seg
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final cp = int.tryParse(m.group(1)!);
          return (cp != null && cp >= 0 && cp <= 0x10FFFF) ? String.fromCharCode(cp) : '';
        })
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
          final cp = int.tryParse(m.group(1)!, radix: 16);
          return (cp != null && cp >= 0 && cp <= 0x10FFFF) ? String.fromCharCode(cp) : '';
        });

    // 去首尾水印
    txt = txt.replaceAll(RegExp(r'^\s*本文来自.*$', multiLine: true), '');
    txt = txt.replaceAll(RegExp(r'最新最全的日本动漫轻小说.*$'), '');
    txt = txt.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return txt.trim();
  }
}
