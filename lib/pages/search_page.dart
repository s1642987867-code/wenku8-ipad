/// 搜索页：双源搜索（wenku8 本地目录 / linovelib 在线）
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../api/linovelib_api.dart';
import '../api/novel_catalog.dart';
import '../api/web_scraper.dart';
import '../models/models.dart';
import 'book_detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _lino = LinovelibApi();
  List<Book> _results = [];
  bool _searched = false;
  bool _online = false; // false=wenku8 本地目录, true=linovelib 在线
  bool _searching = false;
  String? _onlineError;

  Future<void> _doSearch(String kw) async {
    if (kw.trim().isEmpty) return;
    setState(() { _searching = true; _searched = true; _onlineError = null; });

    if (_online) {
      // 哔哩在线搜索有验证码防护，无法爬虫直搜。
      // 改为：关键词匹配内置热门书单；纯数字则按 nid 直达书页。
      final kwTrim = kw.trim();
      final nid = int.tryParse(kwTrim);
      try {
        if (nid != null) {
          final book = await _lino.bookInfo(kwTrim);
          if (!mounted) return;
          setState(() { _results = [book]; _searching = false; });
          return;
        }
        // 关键词：抓月榜+周榜，按标题过滤
        final all = <Book>[];
        for (final p in ['monthvisit', 'weekvisit', 'allvisit']) {
          try { all.addAll(await _lino.ranking(period: p)); } catch (_) {}
        }
        if (!mounted) return;
        final filtered = all.where((b) => b.title.contains(kwTrim) || kwTrim.contains(b.title)).toSet().toList();
        setState(() {
          _results = filtered;
          _searching = false;
          _onlineError = filtered.isEmpty
              ? '哔哩轻小说在线搜索需验证码，当前仅支持：\n1. 输入书号(NID)直达，如 2725\n2. 从热门榜单中筛选\n试试「发现 → 哔哩·月榜」'
              : null;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() { _results = []; _searching = false; _onlineError = '哔哩轻小说连接失败：$e\n可切换到轻小说文库本地目录搜索。'; });
      }
    } else {
      final kwTrim = kw.trim();
      // wenku8：纯数字 = 书号直达（实时爬取书页）
      final aid = int.tryParse(kwTrim);
      if (aid != null && aid > 0 && aid < 10000) {
        try {
          setState(() { _searching = true; });
          final scraper = WebScraper();
          final book = await scraper.bookInfo(kwTrim);
          if (!mounted) return;
          setState(() { _results = [book]; _searching = false; });
          return;
        } catch (e) {
          // 书号爬取失败，回退本地搜索
        }
      }
      final books = NovelCatalog.instance.search(kwTrim, limit: 100).map((e) => e.toBook()).toList();
      if (!mounted) return;
      setState(() { _results = books; _searching = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: _online ? '哔哩书号直达 / 热门榜筛选...' : '书名/作者搜索 · 或书号直达...',
            border: InputBorder.none,
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _controller.clear(); setState(() { _results = []; _searched = false; }); })
                : null,
          ),
          onChanged: (v) => setState(() {}),
          onSubmitted: _doSearch,
          autofocus: true,
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () => _doSearch(_controller.text)),
        ],
      ),
      body: Column(
        children: [
          // 数据源切换
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('轻小说文库'), icon: Icon(Icons.local_library, size: 16)),
                      ButtonSegment(value: true, label: Text('哔哩轻小说'), icon: Icon(Icons.public, size: 16)),
                    ],
                    selected: {_online},
                    onSelectionChanged: (s) => setState(() { _online = s.first; _results = []; _searched = false; _onlineError = null; }),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: !_searched
                ? Center(
                    child: Text(
                      _online ? '哔哩轻小说 (linovelib.com)\n输入书号(NID)直达 · 或关键词筛选热门榜' : '轻小说文库\n书名/作者搜索 · 输入书号(1-4402)直达在线书页',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : _searching
                    ? const Center(child: CircularProgressIndicator())
                    : _onlineError != null
                        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_onlineError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.orange))))
                        : _results.isEmpty
                            ? const Center(child: Text('未找到相关书籍', style: TextStyle(color: Colors.grey)))
                            : ListView.builder(
                                itemCount: _results.length,
                                itemBuilder: (ctx, i) => _BookTile(_results[i]),
                              ),
          ),
        ],
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  final Book book;
  const _BookTile(this.book);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CachedNetworkImage(
          imageUrl: book.coverUrl ?? '',
          width: 50,
          height: 70,
          fit: BoxFit.cover,
          placeholder: (_, __) => const SizedBox(width: 50, height: 70, child: ColoredBox(color: Color(0xFFE0E0E0))),
          errorWidget: (_, __, ___) => const SizedBox(width: 50, height: 70, child: ColoredBox(color: Color(0xFFE0E0E0))),
        ),
      ),
      title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${book.author}${book.category != null ? ' · ${book.category}' : ''}${book.source == BookSource.linovelib ? ' · 哔哩' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => BookDetailPage(aid: book.aid, book: book))),
    );
  }
}
