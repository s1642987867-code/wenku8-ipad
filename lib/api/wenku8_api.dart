/// 轻小说文库 API 层。
///
/// 数据源（全部来自轻小说文库 / light-novel-library_Wenku8_Android 项目所依赖的站点资源）：
/// - **全本 TXT 通道**（主引擎，已实测可用）：
///   `https://dl.wenku8.com/down.php?type=txt&id=<aid>` —— 无需登录，
///   返回 GBK 全本，卷章标记规整：`第X卷 卷名 N.章名`。
/// - **封面 CDN**：`https://img.wenku8.com/image/{aid~/1000}/{aid}/{aid}s.jpg`
///   （与 P5UEDGK/Wenku8_Flutter、MewX/light-novel-library 相同规则）。
/// - **书架/进度/离线**：本地实现（SharedPreferences + 文件缓存），
///   与 15dd/wenku8reader 的 MMKV+Room 思路一致。
/// - 兼容保留 App 中继协议封装（v1.30，`wenku8-relay.mewx.org`），
///   用于登录用户时启用云书架等扩展（当前不可达时自动降级）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../src/gbk.dart';
import '../models/models.dart';

class Wenku8Api {
  /// 全本 TXT 下载通道（实测稳定，无需登录）。
  static const String txtBase = 'https://dl.wenku8.com';

  /// 封面 CDN。
  static String coverUrl(String aid) {
    final n = int.tryParse(aid) ?? 0;
    return 'https://img.wenku8.com/image/${n ~/ 1000}/$aid/${aid}s.jpg';
  }

  /// App 中继（v1.30 协议，登录后可选使用；当前不可达时自动降级）。
  static const String relayBase = 'https://wenku8-relay.mewx.org';
  static const String appVer = '1.24-pico-mochi';
  static const String relayUa =
      'Dalvik/2.1.0 (Linux; U; Android 15; 23114RD76B Build/AQ3A.240912.001)';

  final http.Client _client;
  final Duration timeout;
  final _RateGate _gate = _RateGate();

  /// 全本 TXT 原文缓存（避免重复下载 3~10MB 文本）。
  final Map<String, _BookText> _bookTexts = {};

  Wenku8Api({http.Client? client, this.timeout = const Duration(seconds: 30)})
      : _client = client ?? http.Client();

  // ---------------- 全本 TXT 主通道 ----------------

  /// 下载并解析全本 TXT → (Book, Volumes)。结果驻内存缓存。
  Future<(Book, List<Volume>)> bookDetail(String aid) async {
    final cached = _bookTexts[aid];
    if (cached != null) return (cached.book, cached.volumes);
    final text = await fetchBookText(aid);
    final parsed = _parseFullText(aid, text);
    final entry = _BookText(book: parsed.$1, volumes: parsed.$2, raw: text);
    _bookTexts[aid] = entry;
    return (entry.book, entry.volumes);
  }

  /// 章节正文：从全本 TXT 中按行区间切出。
  Future<String> chapterContent(String aid, String cid) async {
    final entry = await _ensureBook(aid);
    final chapter = entry.chapterByCid[cid];
    if (chapter == null) {
      throw Wenku8Exception('章节不存在: $aid/$cid');
    }
    final raw = entry.raw;
    final lines = raw.split('\n');
    final start = chapter.startLine ?? 0;
    final end = chapter.endLine ?? lines.length;
    final slice = lines.sublist(
        start.clamp(0, lines.length), end.clamp(0, lines.length));
    return _cleanContent(slice.join('\n'));
  }

  Future<_BookText> _ensureBook(String aid) async {
    final cached = _bookTexts[aid];
    if (cached != null) return cached;
    await bookDetail(aid);
    return _bookTexts[aid]!;
  }

  /// 拉取全本 TXT（GBK 解码）。使用 dart:io HttpClient（可复用连接、
  /// 自动处理 gzip），失败时经 package:http 重试。
  Future<String> fetchBookText(String aid) async {
    await _gate.wait();
    var lastErr = '';
    for (var attempt = 0; attempt <= 2; attempt++) {
      try {
        final hc = HttpClient();
        hc.userAgent =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
        hc.autoUncompress = true;
        try {
          final req = await hc.getUrl(Uri.parse('$txtBase/down.php?type=txt&id=$aid'));
          final resp = await req.close().timeout(timeout);
          if (resp.statusCode == 429) {
            throw Wenku8Exception('下载过于频繁（HTTP 429），请稍后再试');
          }
          if (resp.statusCode != 200) {
            lastErr = 'HTTP ${resp.statusCode}';
            continue;
          }
          final bytes = <int>[];
          await for (final chunk in resp) {
            bytes.addAll(chunk);
          }
          return smartDecode(bytes);
        } finally {
          hc.close();
        }
      } on Wenku8Exception {
        rethrow;
      } catch (e) {
        lastErr = e.toString();
        await Future.delayed(Duration(milliseconds: 800 * (attempt + 1)));
      }
    }
    throw Wenku8Exception('全本下载失败: $lastErr');
  }

  /// 解析全本 TXT 为卷章树。
  ///
  /// 行格式（实测）：`第一卷 苍月魔女与受诅咒之王 1.诅咒话语及苍蓝之塔`
  /// 同书的标记行以书名分隔卷与章。特殊行：插图 / 后记 / 序章 / 后日谈。
  (Book, List<Volume>) _parseFullText(String aid, String raw) {
    final lines = raw.split('\n');
    final headerRe = RegExp(
        r'^(第[一二三四五六七八九十百千零〇\d]+卷\s*\S.*?)\s+'
        r'(\d+[\.．]\s*.+'
        r'|第[一二三四五六七八九十百千零〇\d]+章.*'
        r'|序章.*|序|序言.*|前言.*|prologue.*'
        r'|终章.*|尾声.*|epilogue.*'
        r'|后记.*|附录.*|插图|插画.*|后日谈.*|特典.*|番外.*|OVA.*|短篇.*|SS.*|IF.*|间章.*'
        r')$',
        caseSensitive: false);
    // 兜底：书名行（如 <Unnamed Memory 无名记忆>）
    final titleRe = RegExp(r'^\s*<(.+?)>\s*$');
    String title = '';
    final volumes = <Volume>[];
    String? curVolTitle;
    String? curVolId;
    List<Chapter>? curChapters;

    void closeChapter(Chapter? c, int endLine) {
      if (c != null) c.endLine = endLine;
    }

    Chapter? curChapter;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      final tm = titleRe.firstMatch(line);
      if (tm != null && title.isEmpty) {
        title = tm.group(1)!;
        continue;
      }
      final hm = headerRe.firstMatch(line);
      if (hm != null) {
        final volTitle = hm.group(1)!.trim();
        final chTitle = hm.group(2)!.trim();
        if (curVolTitle == null || curVolTitle != volTitle) {
          // 开新卷
          if (curChapter != null) closeChapter(curChapter, i);
          curChapter = null;
          curVolTitle = volTitle;
          curVolId = 'v${volumes.length + 1}';
          curChapters = [];
          volumes.add(Volume(vid: curVolId, title: volTitle, chapters: curChapters));
        } else {
          if (curChapter != null) closeChapter(curChapter, i);
        }
        curChapter = Chapter(
          aid: aid,
          cid: 'c${volumes.last.chapters.length + 1}_$i',
          title: chTitle,
          volumeTitle: volTitle,
        );
        curChapter.startLine = i + 1;
        volumes.last.chapters.add(curChapter);
      }
    }
    if (curChapter != null) closeChapter(curChapter, lines.length);

    if (title.isEmpty) {
      title = '文库作品 #$aid';
    }
    final book = Book(
      aid: aid,
      title: title,
      author: '', // TXT 通道无作者字段；由 UI 层留空展示
      coverUrl: coverUrl(aid),
      status: null,
    );
    final byCid = <String, Chapter>{};
    for (final v in volumes) {
      for (final c in v.chapters) {
        byCid[c.cid] = c;
      }
    }
    return (book, volumes);
  }

  /// 清洗正文。
  String _cleanContent(String raw) {
    var s = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    s = s.replaceAll(RegExp(r'^\s*本章节由.*?轻小说文库.*$', multiLine: true), '');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s.trim();
  }

  // ---------------- 书籍发现 ----------------

  /// 精选书单（轻小说文库知名度高的作品 aid 集合，用于发现页展示；点击进入详情拉取全本）。
  static const List<(String, String, String)> featured = [
    ('2906', 'Unnamed Memory 无名记忆', '三木なずな'),
    ('2334', 'Re:从零开始的异世界生活', '长月达平'),
    ('2455', '为美好的世界献上祝福！', '暁なつむ'),
    ('1636', '刀剑神域', '川原砾'),
    ('1712', '魔法科高校的劣等生', '佐岛勤'),
    ('2232', '我的青春恋爱物语果然有问题。', '渡航'),
    ('2746', '欢迎来到实力至上主义的教室', '衣笠彰悟'),
    ('2221', '路人女主的养成方法', '丸戸史明'),
    ('1117', '狼与香辛料', '支仓冻砂'),
    ('1947', '约会大作战', '橘公司'),
    ('2057', '章鱼噛噛的广播剧', '五十岚雄策'),
    ('1258', '冰结镜界的伊甸', '细音启'),
    ('1264', '魔之系列', '乔林知'),
    ('2002', '侦探已经死了。', '二语十'),
    ('2374', '口袋里的战争', '细音启'),
    ('1489', '笨蛋、测验、召唤兽', '井上坚二'),
    ('1866', '机巧少女不会受伤', '海空陆'),
    ('1441', '莉可丽丝', '尾尾丸一희'),
  ];

  /// 按标题关键字在精选集中搜索（离线快速通道）；
  /// 无结果时返回空列表，UI 层可提示改用其他方式。
  List<Book> searchFeatured(String keyword) {
    final kw = keyword.toLowerCase().trim();
    return [
      for (final (aid, title, author) in featured)
        if (title.toLowerCase().contains(kw) || author.contains(keyword))
          Book(aid: aid, title: title, author: author, coverUrl: coverUrl(aid)),
    ];
  }

  // ---------------- App 中继协议（登录用户可选，不可达自动降级） ----------------

  Future<String> relay(String actionQuery, {int retries = 1}) async {
    await _gate.wait();
    var lastErr = '';
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final resp = await _client
            .post(Uri.parse(relayBase),
                headers: {'User-Agent': relayUa},
                body: {
                  'appver': appVer,
                  'request': base64Encode(utf8.encode(actionQuery)),
                  'timetoken':
                      DateTime.now().millisecondsSinceEpoch.toString(),
                })
            .timeout(timeout);
        if (resp.statusCode != 200) {
          lastErr = 'HTTP ${resp.statusCode}';
          continue;
        }
        return smartDecode(resp.bodyBytes);
      } catch (e) {
        lastErr = e.toString();
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }
    throw Wenku8Exception('中继不可达: $lastErr');
  }

  /// 登录（App 协议）。中继不可达时返回 false（UI 提示降级为本地模式）。
  Future<bool> login(String username, String password) async {
    try {
      final q =
          'action=login&username=${Uri.encodeQueryComponent(username)}'
          '&password=${Uri.encodeQueryComponent(password)}';
      final text = await relay(q);
      return !text.contains('error') &&
          int.tryParse(text.trim()) == null &&
          text.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void dispose() => _client.close();
}

/// 书籍文本的内存缓存条目。
class _BookText {
  final Book book;
  final List<Volume> volumes;
  final String raw;
  final Map<String, Chapter> chapterByCid = {};
  _BookText({required this.book, required this.volumes, required this.raw}) {
    for (final v in volumes) {
      for (final c in v.chapters) {
        chapterByCid[c.cid] = c;
      }
    }
  }
}

/// 简单限速门：两次请求间隔 ≥ 1.2s，降低 429 风险。
class _RateGate {
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> wait() async {
    final now = DateTime.now();
    final diff = now.difference(_last);
    const min = Duration(milliseconds: 1200);
    if (diff < min) await Future.delayed(min - diff);
    _last = DateTime.now();
  }
}

class Wenku8Exception implements Exception {
  final String message;
  Wenku8Exception(this.message);
  @override
  String toString() => message;
}

/// 磁盘缓存（离线阅读）：{root}/{aid}/{cid}.txt。
class ContentCache {
  final Directory root;
  final Map<String, Future<void>> _writeQueue = {};
  static const int maxChapterBytes = 8 * 1024 * 1024;

  ContentCache(this.root);

  File _file(String aid, String cid) => File(
      '${root.path}${Platform.pathSeparator}$aid${Platform.pathSeparator}$cid.txt');

  Future<String?> get(String aid, String cid) async {
    final f = _file(aid, cid);
    if (await f.exists()) {
      final len = await f.length();
      if (len > maxChapterBytes) return null;
      return f.readAsString();
    }
    return null;
  }

  Future<void> put(String aid, String cid, String content) async {
    final key = '$aid-$cid';
    final prev = _writeQueue[key];
    final task = () async {
      await prev;
      final f = _file(aid, cid);
      await f.parent.create(recursive: true);
      await f.writeAsString(content, flush: true);
    }();
    _writeQueue[key] = task;
    await task;
    _writeQueue.remove(key);
  }

  Future<bool> exists(String aid, String cid) async => _file(aid, cid).exists();

  Future<void> removeBook(String aid) async {
    final d = Directory('${root.path}${Platform.pathSeparator}$aid');
    if (await d.exists()) await d.delete(recursive: true);
  }

  Future<int> bookChapterCount(String aid) async {
    final d = Directory('${root.path}${Platform.pathSeparator}$aid');
    if (!await d.exists()) return 0;
    return (await d.list().toList()).whereType<File>().length;
  }

  Future<int> totalSize() async {
    var total = 0;
    if (!await root.exists()) return 0;
    await for (final e in root.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    return total;
  }
}
