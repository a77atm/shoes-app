import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../data/models/models.dart';
import '../../../presentation/providers/providers.dart';
import '../../../core/constants/app_constants.dart';

class SaleDetailScreen extends ConsumerWidget {
  final String saleId;
  const SaleDetailScreen({super.key, required this.saleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(salesStreamProvider);
    final userAsync = ref.watch(currentUserProvider);
    final isAdmin =
        userAsync.when(data: (u) => u?.isAdmin ?? false, loading: () => false, error: (_, __) => false);

    final saleOpt = salesAsync.whenData(
        (sales) => sales.where((s) => s.id == saleId).firstOrNull);

    return saleOpt.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('خطأ: $e'))),
      data: (sale) {
        if (sale == null) {
          return const Scaffold(body: Center(child: Text('لم يتم العثور على الفاتورة')));
        }
        return _SaleDetailView(sale: sale, isAdmin: isAdmin);
      },
    );
  }
}

class _SaleDetailView extends ConsumerWidget {
  final SaleModel sale;
  final bool isAdmin;
  const _SaleDetailView({required this.sale, required this.isAdmin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (sale.status) {
      case AppConstants.statusPaid:
        statusColor = Colors.green;
        statusLabel = 'تم الدفع';
        statusIcon = Icons.check_circle_rounded;
        break;
      case AppConstants.statusPending:
        statusColor = Colors.orange;
        statusLabel = 'تحت التسليم';
        statusIcon = Icons.pending_rounded;
        break;
      case AppConstants.statusReturned:
        statusColor = Colors.red;
        statusLabel = 'مرتجع';
        statusIcon = Icons.assignment_return_rounded;
        break;
      default:
        statusColor = colors.primary;
        statusLabel = sale.status;
        statusIcon = Icons.receipt;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الفاتورة'),
        actions: [
          if (isAdmin && sale.status != AppConstants.statusReturned)
            PopupMenuButton<String>(
              itemBuilder: (ctx) => [
                if (sale.status == AppConstants.statusPending)
                  const PopupMenuItem(
                    value: 'paid',
                    child: ListTile(
                      leading: Icon(Icons.check_circle, color: Colors.green),
                      title: Text('تأكيد الدفع'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                const PopupMenuItem(
                  value: 'returned',
                  child: ListTile(
                    leading: Icon(Icons.assignment_return, color: Colors.red),
                    title: Text('تسجيل كمرتجع'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              onSelected: (value) =>
                  _updateStatus(context, ref, value),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: statusColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 28),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(statusLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.bold)),
                      Text(
                          DateFormat('d MMMM y - h:mm a', 'ar')
                              .format(sale.saleDate),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: statusColor.withOpacity(0.8))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Customer info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('بيانات العميل',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Divider(),
                    _InfoRow(label: 'الاسم', value: sale.customerName),
                    _InfoRow(
                        label: 'نوع البيع',
                        value: sale.isBulk ? 'مجمع' : 'عادي'),
                    if (sale.notes != null)
                      _InfoRow(label: 'ملاحظات', value: sale.notes!),
                    _InfoRow(
                        label: 'سجّل بواسطة', value: sale.createdByName),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Items
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('المنتجات',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Divider(),
                    ...sale.items.map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${item.brand} - ${item.productName}',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600)),
                                    Text(
                                        'مقاس ${item.size} × ${item.quantity}',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: colors.onSurfaceVariant)),
                                    Text(
                                        'سعر الوحدة: ${NumberFormat('#,##0', 'ar').format(item.priceAtSale)} ج.م',
                                        style: theme.textTheme.bodySmall),
                                  ],
                                ),
                              ),
                              Text(
                                '${NumberFormat('#,##0', 'ar').format(item.totalPrice)} ج.م',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colors.primary),
                              ),
                            ],
                          ),
                        )),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('الإجمالي',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text(
                          '${NumberFormat('#,##0', 'ar').format(sale.totalAmount)} ج.م',
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.primary),
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

  void _updateStatus(
      BuildContext context, WidgetRef ref, String newStatus) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(newStatus == 'paid' ? 'تأكيد الدفع' : 'تسجيل كمرتجع'),
        content: Text(newStatus == 'paid'
            ? 'هل تريد تأكيد استلام الدفع؟'
            : 'هل تريد تسجيل هذا البيع كمرتجع؟ سيتم إعادة المخزون.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: newStatus == 'returned'
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(salesServiceProvider).updateSaleStatus(
            sale.id,
            newStatus,
            sale.status,
            sale.totalAmount,
            sale.customerId,
          );
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
