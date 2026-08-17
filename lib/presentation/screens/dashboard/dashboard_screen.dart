import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../data/models/models.dart';
import '../../../presentation/providers/providers.dart';
import '../../../core/constants/app_constants.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statsAsync = ref.watch(dashboardStatsProvider);
    final invStatsAsync = ref.watch(inventoryStatsProvider);
    final lowStockAsync = ref.watch(lowStockStreamProvider);
    final userAsync = ref.watch(currentUserProvider);

    final userName =
        userAsync.when(data: (u) => u?.name ?? '', loading: () => '', error: (_, __) => '');

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة التحكم'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
          PopupMenuButton(
            icon: const CircleAvatar(
              child: Icon(Icons.person_outline, size: 20),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                child: const ListTile(
                  leading: Icon(Icons.logout),
                  title: Text(AppStrings.logout),
                  contentPadding: EdgeInsets.zero,
                ),
                onTap: () => ref.read(authServiceProvider).signOut(),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardStatsProvider);
          ref.invalidate(inventoryStatsProvider);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'أهلاً، $userName 👋',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ).animate().fadeIn().slideX(begin: -0.1),
                    Text(
                      DateFormat('EEEE، d MMMM y', 'ar').format(DateTime.now()),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ).animate().fadeIn(delay: 100.ms),
                  ],
                ),
              ),
            ),

            // ── Sales Stats ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: statsAsync.when(
                  loading: () => const _StatsShimmer(),
                  error: (e, _) =>
                      Text('خطأ: $e', style: TextStyle(color: colors.error)),
                  data: (stats) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('إحصائيات المبيعات',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              title: 'مبيعات اليوم',
                              value:
                                  '${_formatCurrency(stats.todayRevenue)} ج.م',
                              subtitle: '${stats.todaySalesCount} فاتورة',
                              icon: Icons.today_rounded,
                              color: colors.primaryContainer,
                              iconColor: colors.primary,
                              delay: 200,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              title: 'مبيعات الشهر',
                              value:
                                  '${_formatCurrency(stats.monthRevenue)} ج.م',
                              subtitle: '${stats.monthSalesCount} فاتورة',
                              icon: Icons.calendar_month_rounded,
                              color: colors.secondaryContainer,
                              iconColor: colors.secondary,
                              delay: 300,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _PendingCard(
                        count: stats.pendingSalesCount,
                        amount: stats.pendingAmount,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Inventory Stats ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: invStatsAsync.when(
                  loading: () => const SizedBox(),
                  error: (_, __) => const SizedBox(),
                  data: (stats) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('إحصائيات المخزون',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MiniStatCard(
                            label: 'إجمالي المنتجات',
                            value: '${stats['total']}',
                            icon: Icons.inventory_2_rounded,
                          ),
                          _MiniStatCard(
                            label: 'مخزون منخفض',
                            value: '${stats['lowStock']}',
                            icon: Icons.warning_amber_rounded,
                            color: Colors.orange,
                          ),
                          _MiniStatCard(
                            label: 'نفذ المخزون',
                            value: '${stats['outOfStock']}',
                            icon: Icons.remove_circle_outline,
                            color: Colors.red,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Low Stock Alerts ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: lowStockAsync.when(
                loading: () => const SizedBox(),
                error: (_, __) => const SizedBox(),
                data: (items) {
                  if (items.isEmpty) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.orange, size: 20),
                            const SizedBox(width: 8),
                            Text('تنبيهات المخزون المنخفض',
                                style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: Column(
                            children: items.take(5).map((item) {
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      item.currentBalance == 0
                                          ? Colors.red.shade100
                                          : Colors.orange.shade100,
                                  child: Icon(
                                    item.currentBalance == 0
                                        ? Icons.remove_circle
                                        : Icons.warning_amber_rounded,
                                    color: item.currentBalance == 0
                                        ? Colors.red
                                        : Colors.orange,
                                    size: 20,
                                  ),
                                ),
                                title: Text(item.fullName,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                    'الرصيد: ${item.currentBalance} / ${item.openingBalance}'),
                                trailing: item.currentBalance == 0
                                    ? const Chip(
                                        label: Text('نفذ',
                                            style: TextStyle(
                                                color: Colors.red,
                                                fontSize: 12)),
                                        backgroundColor: Color(0xFFFFEBEE),
                                        padding: EdgeInsets.zero,
                                      )
                                    : Chip(
                                        label: Text('منخفض',
                                            style: TextStyle(
                                                color: Colors.orange.shade900,
                                                fontSize: 12)),
                                        backgroundColor:
                                            Colors.orange.shade50,
                                        padding: EdgeInsets.zero,
                                      ),
                                onTap: () =>
                                    context.go('/inventory/edit/${item.id}'),
                              );
                            }).toList(),
                          ),
                        ),
                        if (items.length > 5)
                          TextButton(
                            onPressed: () => context.go('/inventory'),
                            child: Text('عرض الكل (${items.length})'),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // ── Quick Actions ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('إجراءات سريعة',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _QuickAction(
                          label: 'بيع جديد',
                          icon: Icons.add_shopping_cart_rounded,
                          onTap: () => context.go('/sales/add'),
                        ),
                        _QuickAction(
                          label: 'منتج جديد',
                          icon: Icons.add_box_rounded,
                          onTap: () => context.go('/inventory/add'),
                        ),
                        _QuickAction(
                          label: 'عميل جديد',
                          icon: Icons.person_add_rounded,
                          onTap: () => context.go('/customers'),
                        ),
                        _QuickAction(
                          label: 'التقارير',
                          icon: Icons.bar_chart_rounded,
                          onTap: () => context.go('/reports'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCurrency(double amount) {
    return NumberFormat('#,##0', 'ar').format(amount);
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color iconColor;
  final int delay;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color,
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(height: 12),
            Text(title,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(value,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Text(subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: delay)).slideY(begin: 0.2);
  }
}

class _PendingCard extends StatelessWidget {
  final int count;
  final double amount;
  const _PendingCard({required this.count, required this.amount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      color: colors.tertiaryContainer,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colors.tertiary.withOpacity(0.2),
          child: Icon(Icons.pending_actions_rounded, color: colors.tertiary),
        ),
        title: Text('تحت التسليم',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Text('$count فاتورة'),
        trailing: Text(
          '${NumberFormat('#,##0', 'ar').format(amount)} ج.م',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold, color: colors.tertiary),
        ),
      ),
    ).animate().fadeIn(delay: 400.ms);
  }
}

class _MiniStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  const _MiniStatCard(
      {required this.label,
      required this.value,
      required this.icon,
      this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final c = color ?? colors.primary;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: c, size: 24),
              const SizedBox(height: 4),
              Text(value,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold, color: c)),
              Text(label,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant, fontSize: 11),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _QuickAction(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(icon, size: 18, color: colors.primary),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _StatsShimmer extends StatelessWidget {
  const _StatsShimmer();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: SizedBox(height: 120)),
        SizedBox(width: 12),
        Expanded(child: SizedBox(height: 120)),
      ],
    );
  }
}
