/// 阅读器：滚动 / 横排翻页 / 竖排翻页 / 大屏对页。
library;

import 'package:flutter/material.dart';

import '../models/models.dart';
import 'design_system.dart';

/// 阅读器统一入口。
class ReaderView extends StatefulWidget {
  final String title;
  final String content;
  final ReaderSettings settings;
  final ValueChanged<ReaderSettings>? onSettingsChanged;
  final VoidCallback? onPrevChapter;
  final VoidCallback? onNextChapter;
  const ReaderView({
    super.key,
    required this.title,
    required this.content,
    required this.settings,
    this.onSettingsChanged,
    this.onPrevChapter,
    this.onNextChapter,
  });

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  late ReaderSettings s = widget.settings;

  @override
  void didUpdateWidget(ReaderView old) {
    super.didUpdateWidget(old);
    if (old.content != widget.content || old.settings != widget.settings) {
      s = widget.settings;
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (s.mode) {
      ReaderMode.scroll => _ScrollReader(content: widget.content, settings: s),
      ReaderMode.horizontalPage =>
        _PageReader(content: widget.content, settings: s, axis: Axis.horizontal),
      ReaderMode.verticalPage =>
        _PageReader(content: widget.content, settings: s, axis: Axis.vertical),
      ReaderMode.twoPage => _TwoPageReader(content: widget.content, settings: s),
    };
    return Column(
      children: [
        Expanded(child: body),
        _ReaderToolbar(
          settings: s,
          onSettingsChanged: (ns) {
            setState(() => s = ns);
            widget.onSettingsChanged?.call(ns);
          },
          onPrev: widget.onPrevChapter,
          onNext: widget.onNextChapter,
        ),
      ],
    );
  }
}

/// 文本段落化。
List<String> paragraphs(String content) => content
    .split('\n')
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

TextStyle _bodyStyle(ReaderSettings s, double? fontSizeOverride) {
  final fs = fontSizeOverride ?? s.fontSize;
  return TextStyle(
    fontSize: fs,
    height: s.lineHeight,
    color: _themeInk(s.theme),
    fontFamily: _mapFont(s.fontFamily),
  );
}

Color _themeInk(String theme) =>
    theme == 'dark' ? const Color(0xFFD8D2C6) : CreamTokens.ink;
Color _themeBg(String theme) => switch (theme) {
      'dark' => const Color(0xFF221E19),
      'paper' => const Color(0xFFFFFCF5),
      _ => CreamTokens.bgBase,
    };

String _mapFont(String name) => switch (name) {
      'Songti' => 'Songti SC',
      'Kaiti' => 'Kaiti SC',
      _ => 'PingFang SC',
    };

// ---------------- 滚动模式 ----------------

class _ScrollReader extends StatelessWidget {
  final String content;
  final ReaderSettings settings;
  const _ScrollReader({required this.content, required this.settings});

  @override
  Widget build(BuildContext context) {
    final ps = paragraphs(content);
    return Container(
      color: _themeBg(settings.theme),
      child: Scrollbar(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          itemCount: ps.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => SelectableText(
            '　　${ps[i]}',
            style: _bodyStyle(settings, null),
          ),
        ),
      ),
    );
  }
}

// ---------------- 翻页模式（横排 / 竖排共用分页器） ----------------

class _PageReader extends StatefulWidget {
  final String content;
  final ReaderSettings settings;
  final Axis axis;
  const _PageReader({
    required this.content,
    required this.settings,
    required this.axis,
  });

  @override
  State<_PageReader> createState() => _PageReaderState();
}

class _PageReaderState extends State<_PageReader> {
  final _controller = PageController();
  late List<String> _pages = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _paginate();
  }

  @override
  void didUpdateWidget(_PageReader old) {
    super.didUpdateWidget(old);
    _paginate();
  }

  void _paginate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox;
      final size = box.size;
      final ps = paragraphs(widget.content);
      final style = _bodyStyle(widget.settings, null);
      final pages = _layoutPages(ps, style, size, widget.axis);
      if (pages.length != _pages.length) {
        setState(() => _pages = pages);
      }
    });
  }

  List<String> _layoutPages(
      List<String> ps, TextStyle style, Size size, Axis axis) {
    // 近似分页：按字符宽度估算每页可容纳字符数（含标点、空隙修正系数）。
    final usable = (axis == Axis.horizontal
            ? Size(size.width - 56, size.height - 48)
            : Size(size.width - 48, size.height - 56));
    final charW = (style.fontSize ?? 19) * 1.02;
    final charsPerLine = (usable.width / charW).floor().clamp(6, 100);
    final lineH = (style.fontSize ?? 19) * (style.height ?? 1.8);
    final linesPerPage = (usable.height / lineH).floor().clamp(4, 200);
    final capacity = charsPerLine * linesPerPage;

    final pages = <String>[];
    final buf = StringBuffer();
    var count = 0;
    for (final p in ps) {
      final text = '　　$p\n';
      for (final ch in text.runes) {
        if (count >= capacity) {
          pages.add(buf.toString());
          buf.clear();
          count = 0;
        }
        buf.writeCharCode(ch);
        count += (ch > 0x2E80) ? 1 : 0.5.round();
      }
    }
    if (buf.isNotEmpty) pages.add(buf.toString());
    return pages.isEmpty ? [''] : pages;
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;
    return Container(
      color: _themeBg(widget.settings.theme),
      child: PageView(
        scrollDirection:
            vertical ? Axis.vertical : Axis.horizontal,
        controller: _controller,
        children: [
          for (final p in _pages)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: vertical ? 24 : 28,
                vertical: vertical ? 28 : 24,
              ),
              child: vertical
                  ? // 竖排：右起竖行
                  _VerticalText(text: p, style: _bodyStyle(widget.settings, null))
                  : Text(p, style: _bodyStyle(widget.settings, null)),
            ),
        ],
      ),
    );
  }
}

/// 竖排文字：从右到左的竖行列。
class _VerticalText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const _VerticalText({required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n').where((e) => e.isNotEmpty).toList();
    return LayoutBuilder(builder: (context, cons) {
      // 每列字符数 = 可用高 / 行高
      final lineH = (style.fontSize ?? 19) * 1.15;
      final charsPerCol = (cons.maxHeight / lineH).floor().clamp(4, 200);
      final cols = <List<String>>[];
      for (final para in lines) {
        final runes = para.runes.toList();
        for (var i = 0; i < runes.length; i += charsPerCol) {
          cols.add(
            runes.sublist(i, (i + charsPerCol).clamp(0, runes.length))
                .map(String.fromCharCode)
                .toList(),
          );
        }
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true, // 右起
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            for (final col in cols)
              SizedBox(
                width: (style.fontSize ?? 19) * 1.5,
                child: Column(
                  children: [
                    for (final ch in col)
                      SizedBox(
                        height: lineH,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Text(ch, style: style),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    });
  }
}

// ---------------- 大屏对页 ----------------

class _TwoPageReader extends StatefulWidget {
  final String content;
  final ReaderSettings settings;
  const _TwoPageReader({required this.content, required this.settings});

  @override
  State<_TwoPageReader> createState() => _TwoPageReaderState();
}

class _TwoPageReaderState extends State<_TwoPageReader> {
  final _controller = PageController();
  late List<String> _pages = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _paginate();
  }

  @override
  void didUpdateWidget(_TwoPageReader old) {
    super.didUpdateWidget(old);
    _paginate();
  }

  void _paginate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox;
      final size = box.size;
      final ps = paragraphs(widget.content);
      final style = _bodyStyle(widget.settings, null);
      // 每个物理页拆成左右两个逻辑页。
      final single = _layoutPagesForSize(ps, style,
          Size(size.width / 2 - 40, size.height - 56));
      // 两两一组
      final spreads = <List<String>>[];
      for (var i = 0; i < single.length; i += 2) {
        spreads.add([
          single[i],
          if (i + 1 < single.length) single[i + 1] else '',
        ]);
      }
      if (spreads.length != _pages.length) {
        setState(() => _pages = single);
      }
      _spreads = spreads;
    });
  }

  List<List<String>> _spreads = const [];

  List<String> _layoutPagesForSize(
      List<String> ps, TextStyle style, Size size) {
    final charW = (style.fontSize ?? 19) * 1.02;
    final charsPerLine = ((size.width) / charW).floor().clamp(6, 100);
    final lineH = (style.fontSize ?? 19) * (style.height ?? 1.8);
    final linesPerPage = ((size.height) / lineH).floor().clamp(4, 200);
    final capacity = charsPerLine * linesPerPage;
    final pages = <String>[];
    final buf = StringBuffer();
    var count = 0;
    for (final p in ps) {
      final text = '　　$p\n';
      for (final ch in text.runes) {
        if (count >= capacity) {
          pages.add(buf.toString());
          buf.clear();
          count = 0;
        }
        buf.writeCharCode(ch);
        count++;
      }
    }
    if (buf.isNotEmpty) pages.add(buf.toString());
    return pages.isEmpty ? [''] : pages;
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;
    if (!isWide) {
      // 窄屏退化为单页模式
      return _PageReader(
        content: widget.content,
        settings: widget.settings,
        axis: Axis.horizontal,
      );
    }
    return Container(
      color: _themeBg(widget.settings.theme),
      child: PageView(
        controller: _controller,
        children: [
          for (final spread in _spreads)
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(spread[0],
                        style: _bodyStyle(widget.settings, null)),
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  color: CreamTokens.glassBorder,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(spread[1],
                        style: _bodyStyle(widget.settings, null)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------- 工具栏 ----------------

class _ReaderToolbar extends StatelessWidget {
  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onSettingsChanged;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  const _ReaderToolbar({
    required this.settings,
    required this.onSettingsChanged,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    const modes = [
      (ReaderMode.scroll, '滚动'),
      (ReaderMode.horizontalPage, '横排'),
      (ReaderMode.verticalPage, '竖排'),
      (ReaderMode.twoPage, '对页'),
    ];
    return CreamGlass(
      radius: BorderRadius.zero,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final (m, label) in modes)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: settings.mode == m,
                      onSelected: (_) =>
                          onSettingsChanged(settings.copyWith(mode: m)),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.text_decrease),
                onPressed: () => onSettingsChanged(settings.copyWith(
                    fontSize: (settings.fontSize - 1).clamp(12, 40))),
              ),
              Text('${settings.fontSize.round()}',
                  style: const TextStyle(color: CreamTokens.ink)),
              IconButton(
                icon: const Icon(Icons.text_increase),
                onPressed: () => onSettingsChanged(settings.copyWith(
                    fontSize: (settings.fontSize + 1).clamp(12, 40))),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.palette_outlined),
                onSelected: (t) => onSettingsChanged(settings.copyWith(theme: t)),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'cream', child: Text('奶白')),
                  PopupMenuItem(value: 'paper', child: Text('纸白')),
                  PopupMenuItem(value: 'dark', child: Text('夜间')),
                ],
              ),
              IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
            ],
          ),
        ],
      ),
    );
  }
}
