/// 搜索页：双源搜索（wenku8 本地目录 / linovelib 在线）
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../api/linovelib_api.dart';
import '../api/novel_catalog.dart';
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
      try {
        final books = await _lino.search(kw.trim());
        setState(() { _results = books; _searching = false; });
      } catch (e) {
        setState(() { _results = []; _searching = false; _onlineError = '哔哩轻小说在线搜索不可用（可能是网络限制）。\n可切换到轻小说文库本地目录搜索。'; });
      }
    } else {
      final books = NovelCatalog.instance.search(kw.trim(), limit: 100).map((e) => e.toBook()).toList();
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
            hintText: _online ? '搜索哔哩轻小说...' : '搜索书名或作者（本地 4328 本）...',
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
                      _online ? '搜索哔哩轻小说 (linovelib.com)\n在线全书搜索' : '输入关键词搜索\n本地目录共 ${NovelCatalog.instance.count} 本书籍',
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
