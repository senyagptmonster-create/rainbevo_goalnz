import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../app/brand.dart';
import '../app/store.dart';
import '../app/theme.dart';

/// Season planner. A vertical timeline of blocks with a load bar per week —
/// the shape of the season is visible before any text is read.
class ProductApp extends StatefulWidget {
  const ProductApp({super.key});

  @override
  State<ProductApp> createState() => _ProductAppState();
}

class _Block {
  final String name;
  final int weeks;
  final String focus;
  final int load; // 1..5
  const _Block(this.name, this.weeks, this.focus, this.load);

  static _Block? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final weeks = raw['weeks'];
    if (name is! String || name.isEmpty) return null;
    if (weeks is! int || weeks <= 0) return null;
    final focus = raw['focus'];
    final load = raw['load'];
    return _Block(
      name,
      weeks,
      focus is String ? focus : '',
      load is int ? load.clamp(1, 5) : 3,
    );
  }
}

class _Template {
  final String id;
  final String name;
  final List<_Block> blocks;
  const _Template(this.id, this.name, this.blocks);

  int get weeks => blocks.fold(0, (s, b) => s + b.weeks);

  static _Template? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    final rawBlocks = raw['blocks'];
    if (rawBlocks is! List) return null;
    final blocks = <_Block>[];
    for (final b in rawBlocks) {
      final parsed = _Block.tryParse(b);
      if (parsed != null) blocks.add(parsed);
    }
    if (blocks.isEmpty) return null;
    return _Template(id, name, blocks);
  }
}

class _ProductAppState extends State<ProductApp> {
  static const _kTemplate = 'sp_template';
  static const _kDone = 'sp_done';

  List<_Template> _templates = const [];
  int _index = 0;
  Set<String> _doneWeeks = <String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var templates = <_Template>[];
    try {
      final raw = await rootBundle.loadString('assets/json/content.json');
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['templates'] is List) {
        for (final t in decoded['templates'] as List) {
          final parsed = _Template.tryParse(t);
          if (parsed != null) templates.add(parsed);
        }
      }
    } catch (_) {
      templates = <_Template>[];
    }
    final saved = await Store.getInt(_kTemplate);
    final done = await Store.getStringSet(_kDone);
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _index = templates.isEmpty ? 0 : saved.clamp(0, templates.length - 1);
      _doneWeeks = done;
      _loading = false;
    });
  }

  Future<void> _toggleWeek(String id) async {
    final next = Set<String>.of(_doneWeeks);
    if (!next.remove(id)) next.add(id);
    setState(() => _doneWeeks = next);
    await Store.setStringSet(_kDone, next);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: cBg,
        body: Center(child: CircularProgressIndicator(color: cAccent)),
      );
    }
    if (_templates.isEmpty) {
      return Scaffold(
        backgroundColor: cBg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              'Plan pack unavailable.',
              textAlign: TextAlign.center,
              style: AppTheme.text(15, color: AppTheme.textSecondary),
            ),
          ),
        ),
      );
    }

    final template = _templates[_index];
    var weekNumber = 0;
    final rows = <Widget>[];

    for (var bi = 0; bi < template.blocks.length; bi++) {
      final block = template.blocks[bi];
      rows.add(_blockHeader(block));
      for (var w = 0; w < block.weeks; w++) {
        weekNumber++;
        rows.add(_weekRow('${template.id}_$weekNumber', weekNumber, block));
      }
    }

    final doneInPlan = _doneWeeks
        .where((k) => k.startsWith('${template.id}_'))
        .length;

    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kProductTitle, style: AppTheme.display(24)),
                  Text(
                    '$doneInPlan of ${template.weeks} weeks done',
                    style: AppTheme.text(
                      13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _templates.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final selected = i == _index;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _index = i);
                      Store.setInt(_kTemplate, i);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: AppTheme.radiusOf(0.6),
                        color: selected ? cAccent : Colors.transparent,
                        border: Border.all(
                          color: selected ? cAccent : AppTheme.border,
                        ),
                      ),
                      child: Text(
                        _templates[i].name,
                        style: AppTheme.text(
                          13.5,
                          weight: FontWeight.w700,
                          color: selected
                              ? AppTheme.onAccent
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                children: rows,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blockHeader(_Block b) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              b.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.text(
                12,
                color: cAlt,
                weight: FontWeight.w700,
                spacing: 1.6,
              ),
            ),
          ),
          Text(
            '${b.weeks} wk',
            style: AppTheme.text(12, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _weekRow(String id, int number, _Block b) {
    final done = _doneWeeks.contains(id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _toggleWeek(id),
          borderRadius: AppTheme.radius,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: AppTheme.radius,
              color: done
                  ? cAccent.withValues(alpha: 0.12)
                  : AppTheme.surface,
              border: Border.all(
                color: done ? cAccent : AppTheme.border,
                width: done ? 1.5 : 1.1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? cAccent : Colors.transparent,
                    border: Border.all(
                      color: done ? cAccent : AppTheme.border,
                      width: 1.6,
                    ),
                  ),
                  child: done
                      ? Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: AppTheme.onAccent,
                        )
                      : Text(
                          '$number',
                          style: AppTheme.text(
                            12,
                            color: AppTheme.textMuted,
                            weight: FontWeight.w700,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    b.focus.isEmpty ? 'Week $number' : b.focus,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.text(
                      13.5,
                      color: done
                          ? AppTheme.textSecondary
                          : AppTheme.textPrimary,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Пять делений нагрузки: видно форму сезона без чтения
                Row(
                  children: [
                    for (var i = 1; i <= 5; i++)
                      Container(
                        width: 4,
                        height: 6.0 + i * 3,
                        margin: const EdgeInsets.only(left: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: i <= b.load ? cAlt : AppTheme.border,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
