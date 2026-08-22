import 'package:ai_usage/src/rust/models.dart';
import 'package:ai_usage/src/widgets/token_usage_chart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily values use Codex thresholds and exclude today', () {
    final data = buildTokenUsageChartData(const [
      DailyTokenBucket(startDate: '2026-01-01', tokens: 80),
      DailyTokenBucket(startDate: '2026-01-01', tokens: 20),
      DailyTokenBucket(startDate: '2025-12-31', tokens: 75),
      DailyTokenBucket(startDate: '2025-12-30', tokens: 50),
      DailyTokenBucket(startDate: '2025-12-29', tokens: 25),
      DailyTokenBucket(startDate: '2025-12-28', tokens: -4),
      DailyTokenBucket(startDate: '2026-01-02', tokens: 999),
      DailyTokenBucket(startDate: 'invalid', tokens: 999),
    ], DateTime(2026, 1, 2, 23, 30));

    expect(data.cutoffDate, '2026-01-01');
    expect(_cell(data, '2026-01-01').tokens, 100);
    expect(_cell(data, '2026-01-01').dailyLevel, 4);
    expect(_cell(data, '2025-12-31').dailyLevel, 3);
    expect(_cell(data, '2025-12-30').dailyLevel, 2);
    expect(_cell(data, '2025-12-29').dailyLevel, 1);
    expect(_cell(data, '2025-12-28').dailyLevel, 0);
    expect(_cell(data, '2026-01-02').tokens, isNull);
  });

  test(
    'weeks are Sunday aligned, bounded to 52, and cumulative is monotonic',
    () {
      final data = buildTokenUsageChartData(const [
        DailyTokenBucket(startDate: '2025-01-04', tokens: 999),
        DailyTokenBucket(startDate: '2025-01-05', tokens: 70),
        DailyTokenBucket(startDate: '2025-12-27', tokens: 100),
        DailyTokenBucket(startDate: '2026-01-01', tokens: 250),
      ], DateTime(2026, 1, 2));

      expect(data.weeks, hasLength(52));
      expect(data.weeks.first.startDate, '2025-01-05');
      expect(data.weeks.first.totalTokens, 70);
      expect(data.weeks.first.cells.first.date, '2025-01-05');
      expect(data.weeks.last.startDate, '2025-12-28');
      expect(data.weeks.last.totalTokens, 250);
      expect(data.weeks.last.weeklyFillCount, 7);
      expect(data.weeks[data.weeks.length - 2].weeklyFillCount, 3);
      expect(data.weeks.last.cumulativeTokens, 420);
      for (var index = 1; index < data.weeks.length; index++) {
        expect(
          data.weeks[index].cumulativeTokens,
          greaterThanOrEqualTo(data.weeks[index - 1].cumulativeTokens),
        );
      }
    },
  );
}

TokenUsageCell _cell(TokenUsageChartData data, String date) => data.weeks
    .expand((week) => week.cells)
    .singleWhere((cell) => cell.date == date);
