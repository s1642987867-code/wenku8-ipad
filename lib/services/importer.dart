/// 本地书库导入：EPUB / TXT。
///
/// EPUB：zip 解包 → container.xml 找 OPF → spine/manifest 确定章节顺序
///   → 逐章 XHTML 抽文本（按 <h1..h6>/块级元素分段）→ 生成 Volume/Chapter 树
///   + 本地章节缓存（ContentCache），阅读时命中缓存走离线。
/// TXT：整本导入，单卷单章（或按 "第X章" 正则智能分章）。
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/models.dart';
import '../src/gbk.dart';

class ImportResult {
  final Book book;
  final List<Volume> volumes;
  final Map<String, String> chapterText; // cid -> 正文
  ImportResult({required this.book, required this.volumes, required this.chapterText});
}

/// 智能分章正则：第X章/卷/话/节、Chapter N、数字编号。
final _chapterRe = RegExp(
    r'^\s*(第[一二三四五六七八九十百千万零两\d]+[章卷话节回部]|Chapter\s+\d+|CHAPTER\s+\d+|序章|楔子|前言|后记|番外).{0,40}$');

class LocalImporter {
  /// 从文件字节导入。
  /// [chapterize]：TXT 是否按正则自动分章（用户可选关闭）。
  static Future<ImportResult> importFile(
      String fileName, List<int> bytes,
      {bool chapterize = true}) async {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.epub')) {
      return _importEpub(fileName, bytes);
    }
    if (lower.endsWith('.txt')) {
      return _importTxt(fileName, bytes, chapterize: chapterize);
    }
    throw ImportException('暂不支持该格式：$fileName（当前支持 EPUB / TXT）');
  }

  // ---------------- EPUB ----------------

  static Future<ImportResult> _importEpub(String fileName, List<int> bytes) async {
    Archive? archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw ImportException('EPUB 文件损坏（zip 解包失败）：$e');
    }
    ArchiveFile? opfFile;
    // 1) container.xml → OPF 路径
    final container = _findFile(archive, 'META-INF/container.xml');
    if (container != null) {
      try {
        final doc = XmlDocument.parse(utf8.decode(container.content as List<int>,
            allowMalformed: true));
        final rootfile = doc.findAllElements('rootfile').firstOrNull;
        final fullPath = rootfile?.getAttribute('full-path');
        if (fullPath != null) opfFile = _findFile(archive, fullPath);
      } catch (_) {
        // 回退：直接搜 .opf
      }
    }
    opfFile ??= archive.files
        .where((f) => f.name.toLowerCase().endsWith('.opf') && f.isFile)
        .firstOrNull;
    if (opfFile == null) {
      throw ImportException('EPUB 缺少 OPF 元数据（不是标准 EPUB）');
    }

    final opfDir = opfFile.name.contains('/')
        ? opfFile.name.substring(0, opfFile.name.lastIndexOf('/') + 1)
        : '';
    String opfXml;
    try {
      opfXml = utf8.decode(opfFile.content as List<int>, allowMalformed: true);
    } catch (e) {
      throw ImportException('OPF 解析失败：$e');
    }
    final opf = XmlDocument.parse(opfXml);

    // 2) metadata：标题/作者/封面
    final titleEl = opf.findAllElements('dc:title').firstOrNull ??
        opf.findAllElements('title').firstOrNull;
    final creatorEl = opf.findAllElements('dc:creator').firstOrNull ??
        opf.findAllElements('creator').firstOrNull;
    final title = (titleEl?.innerText.trim().isNotEmpty ?? false)
        ? titleEl!.innerText.trim()
        : fileName.replaceAll(RegExp(r'\.epub$', caseSensitive: false), '');
    final author = creatorEl?.innerText.trim() ?? '佚名';

    // 3) manifest + spine → 章节顺序
    final manifest = <String, String>{}; // id -> href
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      final mediaType = item.getAttribute('media-type') ?? '';
      if (id != null && href != null && mediaType.contains('xhtml')) {
        manifest[id] = href;
      }
    }
    final spineRefs = <String>[];
    for (final ref in opf.findAllElements('itemref')) {
      final idref = ref.getAttribute('idref');
      if (idref != null && manifest.containsKey(idref)) spineRefs.add(idref);
    }
    if (spineRefs.isEmpty) {
      // 兜底：manifest 顺序
      spineRefs.addAll(manifest.keys);
    }
    if (spineRefs.isEmpty) {
      throw ImportException('EPUB 未发现任何章节内容');
    }

    // 4) 逐章抽取文本
    final volumes = <Volume>[];
    final chapterText = <String, String>{};
    final chapters = <Chapter>[];
    var seq = 0;
    for (final idref in spineRefs) {
      final href = manifest[idref]!;
      final path = (opfDir + href).replaceAll('//', '/');
      final f = _findFile(archive, path) ?? _findFile(archive, href);
      if (f == null) continue;
      String html;
      try {
        html = utf8.decode(f.content as List<int>, allowMalformed: true);
      } catch (_) {
        continue;
      }
      final paras = _extractParagraphs(html);
      if (paras.isEmpty) continue;
      final chTitle = _chapterTitle(html, paras, seq);
      final cid = 'e${seq++}';
      chapters.add(Chapter(
          aid: _localAid(fileName, bytes.length), cid: cid, title: chTitle));
      chapterText[cid] = paras.join('\n');
    }
    if (chapters.isEmpty) {
      throw ImportException('EPUB 内容页全部无法解析');
    }
    // EPUB 分卷：每 40 章一卷（大部分 EPUB 只有线性 spine）
    for (var i = 0; i < chapters.length; i += 40) {
      final slice = chapters.sublist(i, (i + 40).clamp(0, chapters.length));
      volumes.add(Volume(
          vid: 'v${i ~/ 40}',
          title: slice.length == chapters.length
              ? '正文'
              : '第 ${i ~/ 40 + 1} 分册（${slice.first.title}…）',
          chapters: slice));
    }
    final book = Book(
      aid: _localAid(fileName, bytes.length),
      title: title,
      author: author,
      status: '已导入',
      intro: '本地导入 · EPUB · ${chapters.length} 章',
    );
    return ImportResult(
        book: book, volumes: volumes, chapterText: chapterText);
  }

  static String _chapterTitle(String html, List<String> paras, int seq) {
    // 优先 h1-h3 标题
    final m = RegExp(r'<h[1-3][^>]*>(.*?)</h[1-3]>',
            dotAll: true, caseSensitive: false)
        .firstMatch(html);
    if (m != null) {
      final t = _stripTags(m.group(1) ?? '').trim();
      if (t.isNotEmpty && t.length <= 60) return t;
    }
    // m3 修复：第一段只有形似章标题时才用作标题，否则避免正文重复
    if (paras.isNotEmpty && paras.first.length <= 60 &&
        _chapterRe.hasMatch(paras.first)) {
      return paras.first;
    }
    return '第 ${seq + 1} 节';
  }

  /// XHTML → 段落列表。M4 修复：<br> 先转为换行再剥块级标签，
  /// 避免 <br> 排版的正文被挤成超长段。
  static List<String> _extractParagraphs(String html) {
    final out = <String>[];
    final bodyM = RegExp(r'<body[^>]*>(.*)</body>',
            dotAll: true, caseSensitive: false)
        .firstMatch(html);
    var body = bodyM?.group(1) ?? html;
    // <br> 转换行
    body = body.replaceAll(
        RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    final blockRe = RegExp(
        r'<(?:p|div|h[1-6]|li)[^>]*>(.*?)</(?:p|div|h[1-6]|li)>',
        dotAll: true, caseSensitive: false);
    for (final m in blockRe.allMatches(body)) {
      // 块内可能有 <br> 转出的 \n，拆多段
      final text = _stripTags(m.group(1) ?? '').trim();
      if (text.isEmpty) continue;
      for (final seg in text.split('\n')) {
        final t = seg.trim();
        if (t.isNotEmpty) out.add(t);
      }
    }
    if (out.isEmpty) {
      // 无块级结构：剥标签后按换行/空行切段
      final text = _stripTags(body).trim();
      if (text.isNotEmpty) {
        out.addAll(text
            .split(RegExp(r'\n\s*\n|\n'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty));
      }
    }
    return out;
  }

  static String _stripTags(String s) {
    var t = s;
    t = t.replaceAll(RegExp(r'<[^>]+>'), '');
    t = t.replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&');
    t = t.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"');
    t = t.replaceAll('&#39;', "'").replaceAll('&apos;', "'");
    // 数字实体
    t = t.replaceAllMapped(RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!)));
    return t.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }

  static ArchiveFile? _findFile(Archive a, String path) {
    // C1 修复：只去掉前导 "/"，不破坏子路径
    final norm = path.replaceAll('\\', '/');
    final clean = norm.startsWith('/') ? norm.substring(1) : norm;
    for (final f in a.files) {
      if (f.name == clean || f.name.endsWith('/$clean') || f.name == norm) {
        return f;
      }
    }
    return null;
  }

  // ---------------- TXT ----------------

  static Future<ImportResult> _importTxt(String fileName, List<int> bytes,
      {required bool chapterize}) async {
    // m4 修复：严格 UTF-8 解码，失败才是 GBK（避免 GBK 被误判成 UTF-8 乱码）
    String text;
    final hasBom = bytes.length >= 3 &&
        bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF;
    if (hasBom) {
      text = utf8.decode(bytes, allowMalformed: true);
    } else {
      try {
        text = utf8.decode(bytes); // 严格模式
      } on FormatException {
        text = _decodeGbk(bytes);
      }
    }
    final lines = text.split(RegExp(r'\r?\n'));
    final book = Book(
      aid: _localAid(fileName, bytes.length),
      title: fileName.replaceAll(RegExp(r'\.txt$', caseSensitive: false), ''),
      author: '本地导入',
      status: '已导入',
      intro: '本地导入 · TXT · ${lines.length} 行',
    );
    final chapterText = <String, String>{};
    final volumes = <Volume>[];
    if (!chapterize) {
      final body = lines.where((l) => l.trim().isNotEmpty).join('\n');
      // 单章但超长（>120k 字）切分为 40k 字分片防卡顿
      const chunk = 40000;
      if (body.length <= chunk) {
        chapterText['c0'] = body;
        volumes.add(Volume(
            vid: 'v0',
            title: '全文',
            chapters: [Chapter(aid: book.aid, cid: 'c0', title: '全文')]));
      } else {
        final chapters = <Chapter>[];
        for (var i = 0, p = 0; i < body.length; i += chunk, p++) {
          chapterText['c$p'] = body.substring(i, (i + chunk).clamp(0, body.length));
          chapters.add(Chapter(
              aid: book.aid, cid: 'c$p', title: '片段 ${p + 1}'));
        }
        volumes.add(Volume(vid: 'v0', title: '全文', chapters: chapters));
      }
      return ImportResult(book: book, volumes: volumes, chapterText: chapterText);
    }
    // 智能分章
    final chapters = <Chapter>[];
    var buf = <String>[];
    var curTitle = '开篇';
    var seq = 0;
    void flush() {
      final body = buf.where((l) => l.trim().isNotEmpty).join('\n');
      if (body.isEmpty) return;
      final cid = 'c${seq++}';
      chapters.add(Chapter(aid: book.aid, cid: cid, title: curTitle));
      chapterText[cid] = body;
      buf = [];
    }

    for (final line in lines) {
      if (_chapterRe.hasMatch(line.trim())) {
        flush();
        curTitle = line.trim();
      }
      buf.add(line);
    }
    flush();
    if (chapters.isEmpty) {
      // 无章节标记：整本单章
      final body = lines.where((l) => l.trim().isNotEmpty).join('\n');
      chapterText['c0'] = body.isEmpty ? '（空文件）' : body;
      chapters.add(Chapter(aid: book.aid, cid: 'c0', title: '全文'));
    }
    // 分卷：每 50 章
    for (var i = 0; i < chapters.length; i += 50) {
      final slice = chapters.sublist(i, (i + 50).clamp(0, chapters.length));
      volumes.add(Volume(
          vid: 'v${i ~/ 50}',
          title: slice.length == chapters.length
              ? '正文'
              : '第 ${i ~/ 50 + 1} 卷（${slice.first.title}…）',
          chapters: slice));
    }
    return ImportResult(book: book, volumes: volumes, chapterText: chapterText);
  }

  static bool _looksUtf8(List<int> b) {
    // BOM 直接判 UTF-8
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
      return true;
    }
    var validMulti = 0, badMulti = 0;
    for (var i = 0; i < b.length;) {
      final c = b[i];
      if (c < 0x80) {
        i++;
        continue;
      }
      int need;
      if (c >= 0xC2 && c <= 0xDF) {
        need = 1;
      } else if (c >= 0xE0 && c <= 0xEF) {
        need = 2;
      } else if (c >= 0xF0 && c <= 0xF4) {
        need = 3;
      } else {
        badMulti++;
        i++;
        continue;
      }
      if (i + need < b.length) {
        var ok = true;
        for (var k = 1; k <= need; k++) {
          if (b[i + k] & 0xC0 != 0x80) ok = false;
        }
        if (ok) {
          validMulti++;
        } else {
          badMulti++;
        }
      }
      i += need + 1;
    }
    return badMulti == 0 || (validMulti > 0 && badMulti < validMulti);
  }

  /// GBK 解码：复用项目内 gbk.dart（同步接口）。
  static String _decodeGbk(List<int> bytes) {
    try {
      return decodeGbk(bytes);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  /// 本地书 aid 前缀 `L` + 文件名 hash + 长度（m5：降低同名不同内容碰撞）。
  static String _localAid(String fileName, [int contentLength = 0]) {
    var h = 0;
    for (final c in fileName.codeUnits) {
      h = (h * 31 + c) & 0x7FFFFFFF;
    }
    // 混入长度（同文件名不同内容时 aid 不同 → 各自独立条目）
    h = (h * 33 + contentLength) & 0x7FFFFFFF;
    return 'L${h.toRadixString(36)}';
  }
}

class ImportException implements Exception {
  final String message;
  ImportException(this.message);
  @override
  String toString() => message;
}
