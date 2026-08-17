import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../presentation/providers/providers.dart';
import '../../../data/services/sales_service.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(reportPeriodProvider);
    final range = ref.watch(reportDateRangeProvider);
    final reportAsync = ref.watch(salesReportProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('التقارير'),
      ),
      body: Column(
        children: [
          // Period selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SegmentedButton<ReportPeriod>(
              segments: const [
                ButtonSegment(
                    value: ReportPeriod.daily, label: Text('يومي')),
                ButtonSegment(
                    value: ReportPeriod.weekly, label: Text('أسبوعي')),
                ButtonSegment(
                    value: ReportPeriod.monthly, label: Text('شهري')),
                ButtonSegment(
                    value: ReportPeriod.custom, label: Text('مخصص')),
              ],
              selected: {period},
              onSelectionChanged: (s) {
                ref.read(reportPeriodProvider.notifier).state = s.first;
                _updateRange(ref, s.first);
              },
            ),
          ),

          // Date range display
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.date_range, size: 16, color: colors.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  '${DateFormat('d MMM y', 'ar').format(range.start)} - ${DateFormat('d MMM y', 'ar').format(range.end)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant),
                ),
                if (period == ReportPeriod.custom) ...[
                  const Spacer(),
                  TextButton(
                    onPressed: () => _pickCustomRange(context, ref, range),
                    child: const Text('تغيير'),
                  ),
                ],
              ],
            ),
          ),
          const Divider(),

          // Report content
          Expanded(
            child: reportAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('خطأ: $e')),
              data: (report) => _ReportContent(report: report),
            ),
          ),
        ],
      ),
    );
  }

  void _updateRange(WidgetRef ref, ReportPeriod period) {
    final now = DateTime.now();
    DateRange range;
    switch (period) {
      case ReportPeriod.daily:
        range = DateRange(
            start: DateTime(now.year, now.month, now.day),
            end: DateTime(now.year, now.month, now.day, 23, 59, 59));
        break;
      case ReportPeriod.weekly:
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        range = DateRange(
            start: DateTime(weekStart.year, weekStart.month, weekStart.day),
            end: now);
        break;
      case ReportPeriod.monthly:
        range = DateRange(
            start: DateTime(now.year, now.month, 1), end: now);
        break;
      case ReportPeriod.custom:
        return; // Don't update, let user pick
    }
    ref.read(reportDateRangeProvider.notifier).state = range;
  }

  void _pickCustomRange(
      BuildContext context, WidgetRef ref, DateRange current) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
          start: current.start, end: current.end),
    );
    if (range != null) {
      ref.read(reportDateRangeProvider.notifier).state =
          DateRange(start: range.start, end: range.end);
    }
  }
}

class _ReportContent extends StatelessWidget {
  final SalesReport report;
  const _ReportContent({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary cards
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'إجمالي المبيعات',
                value: '${report.totalSales}',
                subtitle: 'فاتورة',
                icon: Icons.receipt_rounded,
                color: colors.primaryContainer,
                iconColor: colors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'الإيرادات',
                value:
                    '${NumberFormat('#,##0', 'ar').format(report.totalRevenue)}',
                subtitle: 'ج.م',
                icon: Icons.payments_rounded,
                color: colors.secondaryContainer,
                iconColor: colors.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SummaryCard(
          title: 'إجمالي القطع المباعة',
          value: '${report.totalItemsSold}',
          subtitle: 'قطعة',
          icon: Icons.shopping_bag_rounded,
          color: colors.tertiaryContainer,
          iconColor: colors.tertiary,
          fullWidth: true,
        ),
        const SizedBox(height: 24),

        // Revenue chart
        if (report.dailyRevenue.isNotEmpty) ...[
          Text('الإيرادات اليومية',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: _RevenueChart(dailyRevenue: report.dailyRevenue),
          ),
          const SizedBox(height: 24),
        ],

        // Top products
        if (report.topProducts.isNotEmpty) ...[
          Text('أفضل المنتجات',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...report.topProducts.take(5).map((p) => _RankItem(
                rank: report.topProducts.indexOf(p) + 1,
                title: p['name'] as String,
                value:
                    '${NumberFormat('#,##0', 'ar').format(p['revenue'])} ج.م',
                subtitle: '${p['quantity']} قطعة',
                maxValue: (report.topProducts.first['revenue'] as double),
                currentValue: (p['revenue'] as double),
              )),
          const SizedBox(height: 24),
        ],

        // Top customers
        if (report.topCustomers.isNotEmpty) ...[
          Text('أفضل العملاء',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...report.topCustomers.take(5).map((c) => _RankItem(
                rank: report.topCustomers.indexOf(c) + 1,
                title: c['name'] as String,
                value:
                    '${NumberFormat('#,##0', 'ar').format(c['revenue'])} ج.م',
                subtitle: '${c['count']} فاتورة',
                maxValue:
                    (report.topCustomers.first['revenue'] as double),
                currentValue: (c['revenue'] as double),
              )),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color iconColor;
  final bool fullWidth;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.iconColor,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: iconColor.withOpacity(0.2),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: iconColor)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(value,
                        style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold, color: iconColor)),
                    const SizedBox(width: 4),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: iconColor)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RankItem extends StatelessWidget {
  final int rank;
  final String title;
  final String value;
  final String subtitle;
  final double maxValue;
  final double currentValue;

  const _RankItem({
    required this.rank,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.maxValue,
    required this.currentValue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ratio = maxValue > 0 ? currentValue / maxValue : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('#$rank',
                style: TextStyle(
                    color: rank <= 3 ? colors.primary : colors.onSurfaceVariant,
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(title,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(value,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colors.primary)),
                        Text(subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: ratio,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor: colors.surfaceVariant,
                  minHeight: 6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueChart extends StatelessWidget {
  final Map<DateTime, double> dailyRevenue;
  const _RevenueChart({required this.dailyRevenue});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sortedEntries = dailyRevenue.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (sortedEntries.isEmpty) return const SizedBox();

    final maxY = sortedEntries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY > 0 ? maxY / 4 : 1,
          getDrawingHorizontalLine: (v) => FlLine(
            color: colors.onSurface.withOpacity(0.1),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: sortedEntries.length > 7
                  ? (sortedEntries.length / 5).floorToDouble()
                  : 1,
              getTitlesWidget: (v, m) {
                final idx = v.toInt();
                if (idx < 0 || idx >= sortedEntries.length) {
                  return const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat('d/M').format(sortedEntries[idx].key),
                    style: TextStyle(
                        fontSize: 10,
                        color: colors.onSurfaceVariant),
                  ),
                );
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (v, m) => Text(
                NumberFormat.compact().format(v),
                style: TextStyle(
                    fontSize: 10, color: colors.onSurfaceVariant),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: sortedEntries
                .asMap()
                .entries
                .map((e) => FlSpot(e.key.toDouble(), e.value.value))
                .toList(),
            isCurved: true,
            color: colors.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: colors.primary.withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }
}
