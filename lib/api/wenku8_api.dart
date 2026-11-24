/// wenku8 API + 全本 TXT 下载引擎
///
/// 双源架构：
/// 1. WebScraper（网页爬虫）：逐章在线抓取，无需登录
/// 2. Wenku8Api（本文件）：全本 TXT 下载（dl.wenku8.com）+ 登录管理
///
/// 登录：wenku8.net/login.php（当前站点登录已失效，保留 UI 供将来恢复）
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../src/gbk.dart';

/// 限速门：两次请求间隔 ≥ 1.2s
class RateGate {
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _chain = Future.value();
  Future<void> wait() {
    final task = _chain.then((_) async {
      final now = DateTime.now();
      final diff = now.difference(_last);
      const min = Duration(milliseconds: 1200);
      if (diff < min) await Future.delayed(min - diff);
      _last = DateTime.now();
    });
    _chain = task.catchError((_) {});
    return task;
  }
}

class Wenku8Api {
  static const txtBase = 'https://dl.wenku8.com';
  static const webBase = 'https://www.wenku8.net';
  static const ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  final http.Client _client;
  final RateGate _gate = RateGate();
  final Map<String, _BookText> _bookTexts = {}; // 全本 TXT 缓存

  Wenku8Api({http.Client? client}) : _client = client ?? http.Client();

  /// 全本 TXT 下载 → 解析为 (Book, List<Volume>)
  Future<(Book, List<Volume>)> bookDetail(String aid) async {
    // 先从缓存检查
    if (_bookTexts.containsKey(aid)) {
      return (_bookTexts[aid]!.book, _bookTexts[aid]!.volumes);
    }

    await _gate.wait();
    final resp = await _client.get(
      Uri.parse('$txtBase/down.php?type=txt&id=$aid'),
      headers: {'User-Agent': ua, 'Referer': '$webBase/book/$aid.htm'},
    ).timeout(const Duration(seconds: 60));

    if (resp.statusCode != 200) {
      throw Wenku8Exception('下载失败: HTTP ${resp.statusCode}');
    }

    final raw = decodeGbk(resp.bodyBytes);
    final parsed = _parseFullText(aid, raw);
    _bookTexts[aid] = parsed;
    return (parsed.book, parsed.volumes);
  }

  /// 从缓存的全本 TXT 中切片章节内容
  Future<String> chapterContent(String aid, String cid) async {
    final bt = _bookTexts[aid];
    if (bt == null) {
      // 触发全本下载
      await bookDetail(aid);
    }
    final bt2 = _bookTexts[aid]!;
    final idx = bt2.chapterByCid[cid];
    if (idx == null) throw Wenku8Exception('章节不存在: $cid');
    // 从 chapterLines 查找行范围
    final range = bt2.chapterLines[idx];
    if (range == null) throw Wenku8Exception('章节行索引缺失');
    final lines = bt2.lines;
    return lines.sublist(range.$1, range.$2).join('\n').trim();
  }

  /// 解析全本 TXT → Book + Volumes + Chapters
  _BookText _parseFullText(String aid, String raw) {
    final lines = raw.split('\n');

    // 提取书名（通常在前面几行，用 <> 包裹）
    String bookTitle = '文库作品 #$aid';
    for (var i = 0; i < lines.length && i < 10; i++) {
      final m = RegExp(r'<(.+)>').firstMatch(lines[i].trim());
      if (m != null) {
        bookTitle = m.group(1)!.trim();
        break;
      }
    }

    // 一遍扫描：识别卷标题和章标题，记录每章的行范围
    final volumes = <Volume>[];
    final chapterByCid = <String, int>{};
    final chapterLines = <int, (int, int)>{}; // globalIdx → (startLine, endLine)

    final volRe = RegExp(r'^第[一二三四五六七八九十百千\d]+卷\s*(.*)');
    final chRe = RegExp(r'^第[一二三四五六七八九十百千\d]+章\s*(.*)|^(序章|尾声|后记|终章|楔子|引子|番外)');

    String? curVolTitle;
    List<Chapter>? curChapters;
    int? curChStartLine;
    int globalIdx = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final volMatch = volRe.firstMatch(line);
      final chMatch = chRe.firstMatch(line);

      if (volMatch != null) {
        // 结束上一章
        if (curChapters != null && curChapters.isNotEmpty && curChStartLine != null) {
          chapterLines[globalIdx - 1] = (curChStartLine, i);
        }
        curVolTitle = line;
        curChapters = [];
        volumes.add(Volume(vid: 'v${volumes.length + 1}', title: curVolTitle, chapters: curChapters));
      } else if (chMatch != null) {
        // 结束上一章
        if (curChapters != null && curChapters.isNotEmpty && curChStartLine != null) {
          chapterLines[globalIdx - 1] = (curChStartLine, i);
        }
        if (curChapters != null) {
          final cid = 'c${volumes.length - 1}_${curChapters.length}';
          curChapters.add(Chapter(
            aid: aid,
            cid: cid,
            title: line,
            volumeTitle: curVolTitle,
          ));
          chapterByCid[cid] = globalIdx;
          chapterLines[globalIdx] = (i + 1, lines.length); // 暂设到末尾，后续章节会覆盖
          globalIdx++;
          curChStartLine = i + 1;
        }
      }
    }

    // 如果没有解析到章节（纯文本无标题），整本作为一个章节
    if (volumes.isEmpty) {
      final chs = [Chapter(aid: aid, cid: 'c0_0', title: bookTitle)];
      volumes.add(Volume(vid: 'v1', title: '全文', chapters: chs));
      chapterByCid['c0_0'] = 0;
      chapterLines[0] = (0, lines.length);
    }

    final book = Book(
      aid: aid,
      title: bookTitle,
      coverUrl: WebScraperCover.url(aid),
    );

    return _BookText(
      book: book,
      volumes: volumes,
      lines: lines,
      chapterByCid: chapterByCid,
      chapterLines: chapterLines,
    );
  }

  // ============ 登录管理 ============

  String? _cookie;
  String? _username;

  String? get username => _username;
  String? get cookie => _cookie;
  bool get isLoggedIn => _cookie != null && _cookie!.isNotEmpty;

  /// 网页登录（当前 wenku8.net 登录已失效，保留接口）
  Future<bool> login(String username, String password) async {
    await _gate.wait();
    try {
      final resp = await _client
          .post(
            Uri.parse('$webBase/login.php?do=submit'),
            headers: {
              'User-Agent': ua,
              'Content-Type': 'application/x-www-form-urlencoded',
              'Referer': '$webBase/login.php',
            },
            body: {
              'username': username,
              'password': password,
              'action': 'login',
              'usecookie': '315360000',
              'submit': ' 登 录 ',
            },
          )
          .timeout(const Duration(seconds: 20));

      final html = decodeGbk(resp.bodyBytes);
      // 登录成功标记：页面上不再出现"选择[登录]"
      if (html.contains('欢迎') && !html.contains('选择[登录]')) {
        _username = username;
        final sc = resp.headers['set-cookie'];
        if (sc != null) {
          _cookie = sc.split(';').first;
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  void logout() {
    _cookie = null;
    _username = null;
  }
}

/// 封面 URL 集中管理
class WebScraperCover {
  static String url(String aid) {
    final n = int.tryParse(aid) ?? 0;
    return 'https://img.wenku8.com/image/${n ~/ 1000}/$aid/${aid}s.jpg';
  }
}

/// 全本 TXT 缓存
class _BookText {
  final Book book;
  final List<Volume> volumes;
  final List<String> lines;
  final Map<String, int> chapterByCid;
  final Map<int, (int, int)> chapterLines; // globalIdx → (startLine, endLine)

  _BookText({
    required this.book,
    required this.volumes,
    required this.lines,
    required this.chapterByCid,
    required this.chapterLines,
  });
}
