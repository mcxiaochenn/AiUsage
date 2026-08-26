import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../design_system/design_system.dart';
import '../rust/models.dart';

enum TokenUsageView { daily, weekly, cumulative }

@immutable
class TokenUsageCell {
  const TokenUsageCell({
    required this.date,
    required this.tokens,
    required this.dailyLevel,
  });

  final String date;
  final int? tokens;
  final int dailyLevel;
}

@immutable
class TokenUsageWeek {
  const TokenUsageWeek({
    required this.startDate,
    required this.cells,
    required this.totalTokens,
    required this.cumulativeTokens,
    required this.weeklyFillCount,
    required this.cumulativeFillCount,
  });

  final String startDate;
  final List<TokenUsageCell> cells;
  final int totalTokens;
  final int cumulativeTokens;
  final int weeklyFillCount;
  final int cumulativeFillCount;
}

@immutable
class TokenUsageChartData {
  const TokenUsageChartData({required this.weeks, required this.cutoffDate});

  final List<TokenUsageWeek> weeks;
  final String cutoffDate;
}

@visibleForTesting
TokenUsageChartData buildTokenUsageChartData(
  List<DailyTokenBucket> buckets,
  DateTime now,
) {
  final today = DateTime.utc(now.year, now.month, now.day);
  final cutoff = today.subtract(const Duration(days: 1));
  final currentWeekStart = today.subtract(Duration(days: today.weekday % 7));
  final firstDate = currentWeekStart.subtract(const Duration(days: 51 * 7));
  final totals = <String, int>{};

  for (final bucket in buckets) {
    final date = _parseCalendarDate(bucket.startDate);
    if (date == null || date.isBefore(firstDate) || date.isAfter(cutoff)) {
      continue;
    }
    final key = _calendarDate(date);
    totals.update(
      key,
      (value) => value + max(0, bucket.tokens),
      ifAbsent: () => max(0, bucket.tokens),
    );
  }

  final rawWeeks = List.generate(52, (weekIndex) {
    final weekStart = firstDate.add(Duration(days: weekIndex * 7));
    final cells = List.generate(7, (dayIndex) {
      final date = weekStart.add(Duration(days: dayIndex));
      final key = _calendarDate(date);
      return (
        date: key,
        tokens: date.isAfter(cutoff) ? null : totals[key] ?? 0,
      );
    }, growable: false);
    final total = cells.fold<int>(0, (sum, cell) => sum + (cell.tokens ?? 0));
    return (startDate: _calendarDate(weekStart), cells: cells, total: total);
  }, growable: false);

  final dailyPeak = rawWeeks
      .expand((week) => week.cells)
      .fold<int>(0, (peak, cell) => max(peak, cell.tokens ?? 0));
  final weeklyPeak = rawWeeks.fold<int>(
    0,
    (peak, week) => max(peak, week.total),
  );
  var cumulative = 0;
  final cumulativeTotals = rawWeeks
      .map((week) {
        cumulative += week.total;
        return cumulative;
      })
      .toList(growable: false);
  final cumulativePeak = cumulativeTotals.isEmpty ? 0 : cumulativeTotals.last;

  return TokenUsageChartData(
    cutoffDate: _calendarDate(cutoff),
    weeks: List.generate(rawWeeks.length, (index) {
      final week = rawWeeks[index];
      final cumulativeTotal = cumulativeTotals[index];
      return TokenUsageWeek(
        startDate: week.startDate,
        cells: week.cells
            .map(
              (cell) => TokenUsageCell(
                date: cell.date,
                tokens: cell.tokens,
                dailyLevel: _dailyLevel(cell.tokens, dailyPeak),
              ),
            )
            .toList(growable: false),
        totalTokens: week.total,
        cumulativeTokens: cumulativeTotal,
        weeklyFillCount: _columnFillCount(week.total, weeklyPeak),
        cumulativeFillCount: _columnFillCount(cumulativeTotal, cumulativePeak),
      );
    }, growable: false),
  );
}

class TokenUsageChart extends StatelessWidget {
  const TokenUsageChart({
    super.key,
    required this.buckets,
    required this.view,
    required this.onViewChanged,
  });

  final List<DailyTokenBucket> buckets;
  final TokenUsageView view;
  final ValueChanged<TokenUsageView> onViewChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = buildTokenUsageChartData(buckets, DateTime.now());
    return Card(
      child: Padding(
        padding: context.aiSpacing.cardInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.tokenUsageChart, style: context.aiTypography.cardTitle),
            SizedBox(height: context.aiSpacing.controlGap),
            LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: AlignmentDirectional.centerStart,
                child: SegmentedButton<TokenUsageView>(
                  expandedInsets:
                      constraints.maxWidth <
                          AiUsageLayoutTokens.compactBreakpoint
                      ? EdgeInsets.zero
                      : null,
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: TokenUsageView.daily,
                      label: Text(l10n.daily),
                    ),
                    ButtonSegment(
                      value: TokenUsageView.weekly,
                      label: Text(l10n.weekly),
                    ),
                    ButtonSegment(
                      value: TokenUsageView.cumulative,
                      label: Text(l10n.cumulative),
                    ),
                  ],
                  selected: {view},
                  onSelectionChanged: (selection) {
                    onViewChanged(selection.first);
                  },
                ),
              ),
            ),
            SizedBox(height: context.aiSpacing.sectionGap),
            if (buckets.isEmpty)
              Text(l10n.noTokenBuckets)
            else
              Semantics(
                container: true,
                label: l10n.tokenUsageChartSemantics(_viewLabel(l10n, view)),
                child: _TokenUsageGrid(data: data, view: view),
              ),
            SizedBox(height: context.aiSpacing.inlineWideGap),
            const _TokenUsageLegend(),
          ],
        ),
      ),
    );
  }
}

@immutable
class _TokenUsageTarget {
  const _TokenUsageTarget({
    required this.id,
    required this.message,
    required this.tokens,
  });

  final String id;
  final String message;
  final int tokens;
}

class _TokenUsageGrid extends StatefulWidget {
  const _TokenUsageGrid({required this.data, required this.view});

  final TokenUsageChartData data;
  final TokenUsageView view;

  @override
  State<_TokenUsageGrid> createState() => _TokenUsageGridState();
}

class _TokenUsageGridState extends State<_TokenUsageGrid> {
  _TokenUsageTarget? _selectedTarget;
  _TokenUsageTarget? _hoveredTarget;

  _TokenUsageTarget? get _activeTarget => _hoveredTarget ?? _selectedTarget;

  @override
  void didUpdateWidget(covariant _TokenUsageGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view ||
        !_sameChartData(oldWidget.data, widget.data)) {
      _selectedTarget = null;
      _hoveredTarget = null;
    }
  }

  void _toggleSelected(_TokenUsageTarget target) {
    setState(() {
      _selectedTarget = _selectedTarget?.id == target.id ? null : target;
    });
  }

  void _setHovered(_TokenUsageTarget? target) {
    if (_hoveredTarget?.id == target?.id) return;
    setState(() => _hoveredTarget = target);
  }

  void _clearSelection() {
    if (_selectedTarget == null && _hoveredTarget == null) return;
    setState(() {
      _selectedTarget = null;
      _hoveredTarget = null;
    });
  }

  Widget _wrapTarget(_TokenUsageTarget target, Widget child) {
    final selected = _selectedTarget?.id == target.id;
    final hovered = _hoveredTarget?.id == target.id;
    final colors = context.aiColors;
    final emphasized = selected || hovered;
    final decorated = Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (emphasized)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: AiUsageDataVisualizationTokens.selectionDecoration(
                  colors,
                  selected: selected,
                ),
              ),
            ),
          ),
      ],
    );
    return Tooltip(
      message: target.message,
      child: MouseRegion(
        onEnter: (_) => _setHovered(target),
        onExit: (_) => _setHovered(null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _toggleSelected(target),
          child: Semantics(
            button: true,
            label: target.message,
            child: decorated,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = _monthLabels(context, widget.data.weeks);
    final active = _activeTarget;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: AiUsageDataVisualizationTokens.chartDetailExtent,
          child: DecoratedBox(
            decoration: AiUsageDataVisualizationTokens.detailDecoration(
              context.aiColors,
            ),
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: context.aiSpacing.controlGap,
                end: context.aiSpacing.tightGap,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      active?.message ?? l10n.tokenUsageInteractionHint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.aiTypography.supporting,
                    ),
                  ),
                  if (active != null)
                    IconButton(
                      tooltip: l10n.cancel,
                      onPressed: _clearSelection,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.close,
                        size: AiUsageComponentSizeTokens.compactIndicatorExtent,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: context.aiSpacing.contentGap),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _clearSelection,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: SizedBox(
              width:
                  widget.data.weeks.length *
                  AiUsageDataVisualizationTokens.chartColumnExtent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: AiUsageDataVisualizationTokens.monthLabelExtent,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final MapEntry(key: index, value: label)
                            in labels.entries)
                          PositionedDirectional(
                            start:
                                index *
                                AiUsageDataVisualizationTokens
                                    .chartColumnExtent,
                            child: Text(
                              label,
                              style: context.aiTypography.caption,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final week in widget.data.weeks)
                        SizedBox(
                          width:
                              AiUsageDataVisualizationTokens.chartColumnExtent,
                          child: switch (widget.view) {
                            TokenUsageView.daily => _DailyWeekColumn(
                              week: week,
                              wrapTarget: _wrapTarget,
                            ),
                            TokenUsageView.weekly => _AggregateWeekColumn(
                              week: week,
                              view: widget.view,
                              fillCount: week.weeklyFillCount,
                              tokens: week.totalTokens,
                              wrapTarget: _wrapTarget,
                            ),
                            TokenUsageView.cumulative => _AggregateWeekColumn(
                              week: week,
                              view: widget.view,
                              fillCount: week.cumulativeFillCount,
                              tokens: week.cumulativeTokens,
                              wrapTarget: _wrapTarget,
                            ),
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DailyWeekColumn extends StatelessWidget {
  const _DailyWeekColumn({required this.week, required this.wrapTarget});

  final TokenUsageWeek week;
  final Widget Function(_TokenUsageTarget target, Widget child) wrapTarget;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        for (final cell in week.cells)
          if (cell.tokens case final tokens?)
            wrapTarget(
              _TokenUsageTarget(
                id: 'daily:${cell.date}',
                message: l10n.dailyTokenTooltip(
                  cell.date,
                  _formatTokens(context, tokens),
                ),
                tokens: tokens,
              ),
              _ChartCell(
                key: ValueKey('daily-${cell.date}'),
                level: cell.dailyLevel,
              ),
            )
          else
            _ChartCell(key: ValueKey('daily-${cell.date}'), level: null),
      ],
    );
  }
}

class _AggregateWeekColumn extends StatelessWidget {
  const _AggregateWeekColumn({
    required this.week,
    required this.view,
    required this.fillCount,
    required this.tokens,
    required this.wrapTarget,
  });

  final TokenUsageWeek week;
  final TokenUsageView view;
  final int fillCount;
  final int tokens;
  final Widget Function(_TokenUsageTarget target, Widget child) wrapTarget;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final message = switch (view) {
      TokenUsageView.weekly => l10n.weeklyTokenTooltip(
        week.startDate,
        _formatTokens(context, tokens),
      ),
      TokenUsageView.cumulative => l10n.cumulativeTokenTooltip(
        week.startDate,
        _formatTokens(context, tokens),
      ),
      TokenUsageView.daily => throw StateError('Daily uses individual cells.'),
    };
    return wrapTarget(
      _TokenUsageTarget(
        id: '${view.name}:${week.startDate}',
        message: message,
        tokens: tokens,
      ),
      Column(
        key: ValueKey('${view.name}-${week.startDate}'),
        children: [
          for (var row = 0; row < 7; row++)
            _ChartCell(level: 7 - row <= fillCount ? 4 : 0),
        ],
      ),
    );
  }
}

String _formatTokens(BuildContext context, int tokens) =>
    NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(tokens);

bool _sameChartData(TokenUsageChartData left, TokenUsageChartData right) {
  if (left.cutoffDate != right.cutoffDate ||
      left.weeks.length != right.weeks.length) {
    return false;
  }
  for (var index = 0; index < left.weeks.length; index++) {
    final leftWeek = left.weeks[index];
    final rightWeek = right.weeks[index];
    if (leftWeek.startDate != rightWeek.startDate ||
        leftWeek.totalTokens != rightWeek.totalTokens ||
        leftWeek.cumulativeTokens != rightWeek.cumulativeTokens ||
        leftWeek.weeklyFillCount != rightWeek.weeklyFillCount ||
        leftWeek.cumulativeFillCount != rightWeek.cumulativeFillCount ||
        leftWeek.cells.length != rightWeek.cells.length) {
      return false;
    }
    for (var cellIndex = 0; cellIndex < leftWeek.cells.length; cellIndex++) {
      final leftCell = leftWeek.cells[cellIndex];
      final rightCell = rightWeek.cells[cellIndex];
      if (leftCell.date != rightCell.date ||
          leftCell.tokens != rightCell.tokens ||
          leftCell.dailyLevel != rightCell.dailyLevel) {
        return false;
      }
    }
  }
  return true;
}

class _ChartCell extends StatelessWidget {
  const _ChartCell({super.key, required this.level});

  final int? level;

  @override
  Widget build(BuildContext context) => Container(
    width: AiUsageDataVisualizationTokens.chartCellExtent,
    height: AiUsageDataVisualizationTokens.chartCellExtent,
    margin: EdgeInsets.only(
      bottom: AiUsageDataVisualizationTokens.chartCellGap,
    ),
    decoration: AiUsageDataVisualizationTokens.cellDecoration(
      context.aiColors,
      level,
    ),
  );
}

class _TokenUsageLegend extends StatelessWidget {
  const _TokenUsageLegend();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = context.aiTypography.supporting;
    return Wrap(
      spacing: context.aiSpacing.tightGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(l10n.lessUsage, style: style),
        for (var level = 0; level <= 4; level++)
          Container(
            width: AiUsageDataVisualizationTokens.chartLegendExtent,
            height: AiUsageDataVisualizationTokens.chartLegendExtent,
            decoration: AiUsageDataVisualizationTokens.legendDecoration(
              context.aiColors,
              level,
            ),
          ),
        Text(l10n.moreUsage, style: style),
      ],
    );
  }
}

Map<int, String> _monthLabels(
  BuildContext context,
  List<TokenUsageWeek> weeks,
) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final result = <int, String>{};
  for (var index = 0; index < weeks.length; index++) {
    final start = _parseCalendarDate(weeks[index].startDate);
    if (start == null) continue;
    for (var offset = 0; offset < 7; offset++) {
      final date = start.add(Duration(days: offset));
      if (date.day == 1) {
        result[index] = DateFormat.MMM(locale).format(date);
        break;
      }
    }
  }
  return result;
}

String _viewLabel(AppLocalizations l10n, TokenUsageView view) => switch (view) {
  TokenUsageView.daily => l10n.daily,
  TokenUsageView.weekly => l10n.weekly,
  TokenUsageView.cumulative => l10n.cumulative,
};

int _dailyLevel(int? tokens, int peak) {
  if (tokens == null || tokens <= 0 || peak <= 0) return 0;
  final ratio = tokens / peak;
  if (ratio > .75) return 4;
  if (ratio > .5) return 3;
  if (ratio > .25) return 2;
  return 1;
}

int _columnFillCount(int tokens, int peak) {
  if (tokens <= 0 || peak <= 0) return 0;
  return max(1, (tokens / peak * 7).ceil());
}

DateTime? _parseCalendarDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

String _calendarDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
