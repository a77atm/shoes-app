import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../data/models/models.dart';
import '../../../presentation/providers/providers.dart';
import '../../../core/constants/app_constants.dart';

class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(salesStreamProvider);
    final filters = ref.watch(saleFiltersProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.sales),
        actions: [
          if (filters.hasFilters)
            TextButton.icon(
              icon: const Icon(Icons.filter_list_off),
              label: const Text('إلغاء الفلاتر'),
              onPressed: () => ref.read(saleFiltersProvider.notifier).state =
                  const SaleFilters(),
            ),
          IconButton(
            icon: Badge(
              isLabelVisible: filters.hasFilters,
              child: const Icon(Icons.filter_list_rounded),
            ),
            onPressed: () => _showFilterSheet(context, ref, filters),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/sales/add'),
        icon: const Icon(Icons.add),
        label: const Text('بيع جديد'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'بحث باسم العميل أو المنتج...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                ref.read(saleFiltersProvider.notifier).state =
                    filters.copyWith(searchQuery: value);
              },
            ),
          ),

          // Status filter chips
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _FilterChip(
                    label: 'الكل',
                    isSelected: filters.status == null,
                    onSelected: (_) => ref
                        .read(saleFiltersProvider.notifier)
                        .state = filters.copyWith()..clearStatus()),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '✓ تم الدفع',
                  isSelected: filters.status == AppConstants.statusPaid,
                  onSelected: (_) => ref
                      .read(saleFiltersProvider.notifier)
                      .state = SaleFilters(status: AppConstants.statusPaid),
                  selectedColor: Colors.green,
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '⏳ تحت التسليم',
                  isSelected: filters.status == AppConstants.statusPending,
                  onSelected: (_) => ref
                      .read(saleFiltersProvider.notifier)
                      .state = SaleFilters(status: AppConstants.statusPending),
                  selectedColor: Colors.orange,
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '↩ مرتجع',
                  isSelected: filters.status == AppConstants.statusReturned,
                  onSelected: (_) => ref
                      .read(saleFiltersProvider.notifier)
                      .state = SaleFilters(status: AppConstants.statusReturned),
                  selectedColor: Colors.red,
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Sales list
          Expanded(
            child: salesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
              data: (sales) {
                if (sales.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 72,
                            color: colors.onSurfaceVariant.withOpacity(0.4)),
                        const SizedBox(height: 16),
                        const Text('لا توجد مبيعات'),
                      ],
                    ),
                  );
                }

                // Summary bar
                final totalAmount =
                    sales.fold(0.0, (sum, s) => sum + s.totalAmount);
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      color: colors.primaryContainer.withOpacity(0.3),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${sales.length} فاتورة',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            'الإجمالي: ${NumberFormat('#,##0', 'ar').format(totalAmount)} ج.م',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.primary),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: sales.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _SaleCard(sale: sales[index]),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet(
      BuildContext context, WidgetRef ref, SaleFilters current) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _FilterBottomSheet(current: current),
    );
  }
}

extension on SaleFilters {
  SaleFilters clearStatus() => SaleFilters(
        startDate: startDate,
        endDate: endDate,
        customerId: customerId,
        saleType: saleType,
        minAmount: minAmount,
        maxAmount: maxAmount,
        searchQuery: searchQuery,
      );
}

class _SaleCard extends ConsumerWidget {
  final SaleModel sale;
  const _SaleCard({required this.sale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (sale.status) {
      case AppConstants.statusPaid:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_rounded;
        statusLabel = 'تم الدفع';
        break;
      case AppConstants.statusPending:
        statusColor = Colors.orange;
        statusIcon = Icons.pending_rounded;
        statusLabel = 'تحت التسليم';
        break;
      case AppConstants.statusReturned:
        statusColor = Colors.red;
        statusIcon = Icons.assignment_return_rounded;
        statusLabel = 'مرتجع';
        break;
      default:
        statusColor = colors.primary;
        statusIcon = Icons.receipt;
        statusLabel = sale.status;
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/sales/${sale.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sale.customerName,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(statusLabel,
                            style: TextStyle(
                                fontSize: 12,
                                color: statusColor,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.shopping_bag_outlined,
                      size: 16, color: colors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    sale.items.map((i) => '${i.brand} ${i.productName} (${i.quantity})').join(', '),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 14, color: colors.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('d MMM y', 'ar').format(sale.saleDate),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      if (sale.isBulk) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('مجمعة',
                              style: TextStyle(
                                  fontSize: 11, color: colors.secondary)),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${NumberFormat('#,##0', 'ar').format(sale.totalAmount)} ج.م',
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold, color: colors.primary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final ValueChanged<bool> onSelected;
  final Color? selectedColor;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = selectedColor ?? colors.primary;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      selectedColor: color.withOpacity(0.15),
      checkmarkColor: color,
      labelStyle: isSelected
          ? TextStyle(color: color, fontWeight: FontWeight.w600)
          : null,
    );
  }
}

class _FilterBottomSheet extends ConsumerStatefulWidget {
  final SaleFilters current;
  const _FilterBottomSheet({required this.current});

  @override
  ConsumerState<_FilterBottomSheet> createState() =>
      _FilterBottomSheetState();
}

class _FilterBottomSheetState extends ConsumerState<_FilterBottomSheet> {
  late SaleFilters _filters;

  @override
  void initState() {
    super.initState();
    _filters = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, controller) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('تصفية المبيعات',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () => setState(() => _filters = const SaleFilters()),
                  child: const Text('إعادة تعيين'),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView(
                controller: controller,
                children: [
                  // Date range
                  const Text('الفترة الزمنية',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.date_range, size: 18),
                          label: Text(_filters.startDate != null
                              ? DateFormat('d/M/y').format(_filters.startDate!)
                              : 'من تاريخ'),
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _filters.startDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (date != null) {
                              setState(() => _filters =
                                  _filters.copyWith(startDate: date));
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.date_range, size: 18),
                          label: Text(_filters.endDate != null
                              ? DateFormat('d/M/y').format(_filters.endDate!)
                              : 'إلى تاريخ'),
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _filters.endDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (date != null) {
                              setState(() =>
                                  _filters = _filters.copyWith(endDate: date));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Sale type
                  const Text('نوع البيع',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilterChip(
                        label: const Text('مبيعات عادية'),
                        selected: _filters.saleType == 'normal',
                        onSelected: (v) => setState(() => _filters =
                            _filters.copyWith(saleType: v ? 'normal' : null)),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('مبيعات مجمعة'),
                        selected: _filters.saleType == 'bulk',
                        onSelected: (v) => setState(() => _filters =
                            _filters.copyWith(saleType: v ? 'bulk' : null)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            FilledButton(
              onPressed: () {
                ref.read(saleFiltersProvider.notifier).state = _filters;
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              child: const Text('تطبيق الفلاتر'),
            ),
          ],
        ),
      ),
    );
  }
}
