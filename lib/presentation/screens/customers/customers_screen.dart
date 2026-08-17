import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../data/models/models.dart';
import '../../../presentation/providers/providers.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final isAdmin =
        userAsync.when(data: (u) => u?.isAdmin ?? false, loading: () => false, error: (_, __) => false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('العملاء'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'جميع العملاء'),
            Tab(text: 'المستحقات'),
          ],
        ),
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showAddCustomerDialog(context, ref),
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('إضافة عميل'),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          // All customers
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'بحث بالاسم أو رقم الهاتف...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) =>
                      ref.read(customerSearchProvider.notifier).state = v,
                ),
              ),
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final customersAsync =
                        ref.watch(customersStreamProvider);
                    return customersAsync.when(
                      loading: () => const Center(
                          child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('خطأ: $e')),
                      data: (customers) => customers.isEmpty
                          ? const Center(child: Text('لا توجد عملاء'))
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                              itemCount: customers.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (ctx, i) =>
                                  _CustomerCard(customer: customers[i]),
                            ),
                    );
                  },
                ),
              ),
            ],
          ),

          // Pending payments
          Consumer(
            builder: (context, ref, _) {
              final pendingAsync = ref.watch(pendingCustomersProvider);
              return pendingAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('خطأ: $e')),
                data: (customers) {
                  if (customers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_outline_rounded,
                              size: 72, color: Colors.green),
                          const SizedBox(height: 16),
                          Text('لا توجد مستحقات معلقة',
                              style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                    );
                  }
                  final total =
                      customers.fold(0.0, (sum, c) => sum + c.pendingAmount);
                  return Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        color: Colors.orange.withOpacity(0.1),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('إجمالي المستحقات',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text(
                              '${NumberFormat('#,##0', 'ar').format(total)} ج.م',
                              style: const TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: customers.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, i) =>
                              _PendingCustomerCard(customer: customers[i]),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddCustomerDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة عميل جديد'),
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
                  keyboardType: TextInputType.phone,
                  decoration:
                      const InputDecoration(labelText: 'رقم الهاتف *'),
                  validator: (v) => (v?.isEmpty ?? true) ? 'مطلوب' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: addressCtrl,
                  decoration:
                      const InputDecoration(labelText: 'العنوان (اختياري)'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'ملاحظات (اختياري)'),
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
              try {
                await ref.read(customerServiceProvider).addCustomer(
                      CustomerModel(
                        id: '',
                        name: nameCtrl.text.trim(),
                        phone: phoneCtrl.text.trim(),
                        address: addressCtrl.text.trim().isEmpty
                            ? null
                            : addressCtrl.text.trim(),
                        notes: notesCtrl.text.trim().isEmpty
                            ? null
                            : notesCtrl.text.trim(),
                        createdAt: DateTime.now(),
                      ),
                    );
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final CustomerModel customer;
  const _CustomerCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colors.primaryContainer,
          child: Text(customer.name[0],
              style: TextStyle(color: colors.primary,
                  fontWeight: FontWeight.bold)),
        ),
        title: Text(customer.name,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(customer.phone),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${NumberFormat('#,##0', 'ar').format(customer.totalPurchases)} ج.م',
              style: TextStyle(
                  color: colors.primary, fontWeight: FontWeight.bold),
            ),
            if (customer.pendingAmount > 0)
              Text(
                'مستحق: ${NumberFormat('#,##0', 'ar').format(customer.pendingAmount)}',
                style: const TextStyle(color: Colors.orange, fontSize: 11),
              ),
          ],
        ),
        onTap: () => context.go('/customers/${customer.id}'),
      ),
    );
  }
}

class _PendingCustomerCard extends StatelessWidget {
  final CustomerModel customer;
  const _PendingCustomerCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.shade100,
          child: Text(customer.name[0],
              style: const TextStyle(
                  color: Colors.orange, fontWeight: FontWeight.bold)),
        ),
        title: Text(customer.name),
        subtitle: Text(customer.phone),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${NumberFormat('#,##0', 'ar').format(customer.pendingAmount)} ج.م',
              style: const TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
            const Text('مستحق', style: TextStyle(fontSize: 11)),
          ],
        ),
        onTap: () => context.go('/customers/${customer.id}'),
      ),
    );
  }
}
