/// wenku8.net 网页爬虫（在线阅读引擎，实测 2026-11 可用，无需登录）：
/// - 书页：`https://www.wenku8.net/book/{aid}.htm` → 标题/作者/卷索引链接
/// - 目录：`/novel/{aid~/1000}/{aid}/index.htm` → `.vcss` 卷 + `.ccss` 章节链接
/// - 正文：`/novel/{aid~/1000}/{aid}/{cid}.htm` → `div#content`（栈法取闭合）
/// 搜索需登录 → 搜索走本地 3892 本目录快照（NovelCatalog）。
///
/// 在线/离线双源：ReaderPage 先查 ContentCache（本地缓存或导入），
/// miss 时走本爬虫逐章在线抓取并落缓存。
library;

import 'package:http/http.dart' as http;

import 'wenku8_api.dart' show RateGate, Wenku8Exception;
import '../models/models.dart';
import '../src/gbk.dart';

class WebScraper {
  static const base = 'https://www.wenku8.net';
  static const ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  final Map<String, (Book, List<Volume>)> _tocCache = {};
  final RateGate _gate = RateGate(); // M2：限速防封 IP

  /// 章节正文拉取（http 包，限速 + 失败退避）。
  Future<String> _get(String path,
      {String referer = '$base/', int attempts = 3}) async {
    var lastErr = '';
    for (var i = 0; i < attempts; i++) {
      await _gate.wait();
      try {
        final resp = await http.get(
          Uri.parse('$base$path'),
          headers: {'User-Agent': ua, 'Referer': referer},
        ).timeout(const Duration(seconds: 25));
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

  String novelDir(String aid) {
    final n = int.tryParse(aid) ?? 0;
    return '/novel/${n ~/ 1000}/$aid';
  }

  /// 书页 → 标题/作者。
  Future<(String, String)> bookMeta(String aid) async {
    final html = await _get('/book/$aid.htm');
    // title 形如「川之光 - 松浦寿辉 - 其他文库 - 轻小说文库」
    final full = RegExp(r'<title>([^<]+)</title>').firstMatch(html)?.group(1) ?? '';
    final parts = full.split(' - ');
    final title = parts.isNotEmpty ? parts[0].trim() : '文库作品 #$aid';
    final author = parts.length > 1 ? parts[1].trim() : '';
    return (title, author);
  }

  /// 目录（卷章树）。aid 必须是 wenku8 数字 aid。
  Future<(Book, List<Volume>)> toc(String aid) async {
    final cached = _tocCache[aid];
    if (cached != null) return cached;
    final html = await _get('${novelDir(aid)}/index.htm',
        referer: '$base/book/$aid.htm');
    final volumes = <Volume>[];
    // 卷行：<td class="vcss" colspan="4" vid="86070">第一卷 佣兵将剑拔起…</td>
    // 章节行：<td class="ccss"><a href="86071.htm">序章</a></td>
    final rowRe = RegExp(
        r'<td class="vcss"[^>]*>([^<]+)</td>|<td class="ccss"><a href="(\d+)\.htm"[^>]*>([^<]+)</a></td>');
    String? curVolTitle;
    List<Chapter>? curChapters;
    for (final m in rowRe.allMatches(html)) {
      if (m.group(1) != null) {
        curVolTitle = m.group(1)!.trim();
        curChapters = [];
        volumes.add(Volume(
            vid: 'v${volumes.length + 1}',
            title: curVolTitle,
            chapters: curChapters));
      } else if (m.group(2) != null && curChapters != null) {
        final cid = m.group(2)!;
        curChapters.add(Chapter(
            aid: aid,
            cid: 'w$cid', // w 前缀：网页章节 id（数字），区别于 TXT 解析的 c{i}_{line}
            title: m.group(3)!.trim(),
            volumeTitle: curVolTitle));
      }
    }
    if (volumes.isEmpty) {
      throw Wenku8Exception('目录解析失败（可能改版或该书无在线目录）');
    }
    // 书名/作者：从 index 页头部
    final title =
        RegExp(r'<div id="title">([^<]+)</div>').firstMatch(html)?.group(1)?.trim() ?? '';
    final author =
        RegExp(r'<div id="info">作者：([^<]+)</div>').firstMatch(html)?.group(1)?.trim() ?? '';
    final book = Book(
      aid: aid,
      title: title.isEmpty ? '文库作品 #$aid' : title,
      author: author,
      coverUrl: Wenku8Cover.url(aid),
      status: null,
    );
    final result = (book, volumes);
    // m1：目录缓存上限 20 本
    if (_tocCache.length > 20) _tocCache.remove(_tocCache.keys.first);
    _tocCache[aid] = result;
    return result;
  }

  /// 章节正文（在线抓取，栈法提取 div#content）。
  Future<String> chapter(String aid, String cid) async {
    final real = cid.startsWith('w') ? cid.substring(1) : cid;
    final html = await _get('${novelDir(aid)}/$real.htm',
        referer: '$base${novelDir(aid)}/index.htm');
    final start = html.indexOf('<div id="content">');
    if (start < 0) {
      throw Wenku8Exception('正文容器缺失（章节可能被移除）');
    }
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
        .replaceAllMapped(RegExp(r'&#(\d+);'),
            (m) => String.fromCharCode(int.parse(m.group(1)!)))
        // m2：十六进制实体
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
            (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
    // 去首尾站点水印行
    txt = txt.replaceAll(RegExp(r'^\s*本文来自.*$', multiLine: true), '');
    txt = txt.replaceAll(RegExp(r'最新最全的日本动漫轻小说.*$'), '');
    txt = txt.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return txt.trim();
  }
}

/// 封面 URL 集中管理（此前在 wenku8_api.dart 内联，这里供爬虫层复用）。
class Wenku8Cover {
  static String url(String aid) {
    final n = int.tryParse(aid) ?? 0;
    return 'https://img.wenku8.com/image/${n ~/ 1000}/$aid/${aid}s.jpg';
  }
}
