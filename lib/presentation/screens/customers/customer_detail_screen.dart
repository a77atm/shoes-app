import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../data/models/models.dart';
import '../../../presentation/providers/providers.dart';

class CustomerDetailScreen extends ConsumerWidget {
  final String customerId;
  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(customersStreamProvider);
    final salesAsync = ref.watch(salesStreamProvider);

    final customer = customersAsync.whenData(
        (list) => list.where((c) => c.id == customerId).firstOrNull);
    final sales = salesAsync.whenData(
        (list) => list.where((s) => s.customerId == customerId).toList());

    return customer.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('خطأ: $e'))),
      data: (c) {
        if (c == null) {
          return const Scaffold(
              body: Center(child: Text('العميل غير موجود')));
        }
        return _CustomerDetailView(
          customer: c,
          salesAsync: sales,
        );
      },
    );
  }
}

class _CustomerDetailView extends ConsumerWidget {
  final CustomerModel customer;
  final AsyncValue<List<SaleModel>> salesAsync;

  const _CustomerDetailView({
    required this.customer,
    required this.salesAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(customer.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showEditDialog(context, ref),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Customer stats
            Row(
              children: [
                Expanded(
                  child: Card(
                    color: colors.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(Icons.shopping_bag_rounded,
                              color: colors.primary),
                          const SizedBox(height: 8),
                          Text('إجمالي المشتريات',
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.center),
                          Text(
                            '${NumberFormat('#,##0', 'ar').format(customer.totalPurchases)} ج.م',
                            style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Card(
                    color: customer.pendingAmount > 0
                        ? Colors.orange.shade50
                        : colors.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(
                            Icons.pending_actions_rounded,
                            color: customer.pendingAmount > 0
                                ? Colors.orange
                                : colors.secondary,
                          ),
                          const SizedBox(height: 8),
                          Text('المستحقات',
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.center),
                          Text(
                            '${NumberFormat('#,##0', 'ar').format(customer.pendingAmount)} ج.م',
                            style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: customer.pendingAmount > 0
                                    ? Colors.orange
                                    : colors.secondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Info
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
                    _InfoRow(
                        icon: Icons.phone_rounded, value: customer.phone),
                    if (customer.address != null)
                      _InfoRow(
                          icon: Icons.location_on_outlined,
                          value: customer.address!),
                    if (customer.notes != null)
                      _InfoRow(
                          icon: Icons.notes_rounded, value: customer.notes!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Sales history
            Text('سجل المبيعات',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            salesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (_, __) => const SizedBox(),
              data: (sales) {
                if (sales.isEmpty) {
                  return const Center(child: Text('لا توجد مبيعات'));
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sales.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final sale = sales[i];
                    Color statusColor = sale.status == 'paid'
                        ? Colors.green
                        : sale.status == 'pending'
                            ? Colors.orange
                            : Colors.red;
                    return Card(
                      child: ListTile(
                        title: Text(
                          sale.items
                              .map((i) => '${i.brand} ${i.productName}')
                              .join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(DateFormat('d MMM y', 'ar')
                            .format(sale.saleDate)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${NumberFormat('#,##0', 'ar').format(sale.totalAmount)} ج.م',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colors.primary),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                sale.status == 'paid'
                                    ? 'مدفوع'
                                    : sale.status == 'pending'
                                        ? 'معلق'
                                        : 'مرتجع',
                                style: TextStyle(
                                    color: statusColor, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController(text: customer.name);
    final phoneCtrl = TextEditingController(text: customer.phone);
    final addressCtrl = TextEditingController(text: customer.address ?? '');
    final notesCtrl = TextEditingController(text: customer.notes ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل بيانات العميل'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'الاسم *'),
                  validator: (v) => (v?.isEmpty ?? true) ? 'مطلوب' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: phoneCtrl,
                  decoration:
                      const InputDecoration(labelText: 'رقم الهاتف *'),
                  validator: (v) => (v?.isEmpty ?? true) ? 'مطلوب' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(labelText: 'العنوان'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              await ref.read(customerServiceProvider).updateCustomer(
                    customer.copyWith(
                      name: nameCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      address: addressCtrl.text.trim(),
                      notes: notesCtrl.text.trim(),
                    ),
                  );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String value;
  const _InfoRow({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
