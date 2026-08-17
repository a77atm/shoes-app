import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../data/models/models.dart';
import '../../../presentation/providers/providers.dart';
import '../../../core/constants/app_constants.dart';

class AddSaleScreen extends ConsumerStatefulWidget {
  const AddSaleScreen({super.key});

  @override
  ConsumerState<AddSaleScreen> createState() => _AddSaleScreenState();
}

class _AddSaleScreenState extends ConsumerState<AddSaleScreen> {
  final _notesCtrl = TextEditingController();
  String? _selectedCustomerId;
  String? _selectedCustomerName;
  String _status = AppConstants.statusPaid;
  String _saleType = 'normal';
  DateTime _saleDate = DateTime.now();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    ref.read(cartProvider.notifier).clear();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cart = ref.read(cartProvider);

    if (_selectedCustomerId == null) {
      _showError('الرجاء اختيار العميل');
      return;
    }
    if (cart.isEmpty) {
      _showError('الرجاء إضافة منتج على الأقل');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = await ref.read(authServiceProvider).getUserData(
            ref.read(authStateProvider).when(
                  data: (u) => u?.uid ?? '',
                  loading: () => '',
                  error: (_, __) => '',
                ),
          );

      final total = cart.fold(0.0, (sum, item) => sum + item.totalPrice);

      final sale = SaleModel(
        id: '',
        customerId: _selectedCustomerId!,
        customerName: _selectedCustomerName!,
        items: cart,
        totalAmount: total,
        status: _status,
        saleType: _saleType,
        notes: _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
        createdById: user?.id ?? '',
        createdByName: user?.name ?? '',
        saleDate: _saleDate,
        createdAt: DateTime.now(),
      );

      await ref.read(salesServiceProvider).addSale(sale);
      ref.read(cartProvider.notifier).clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم تسجيل البيع بنجاح'),
          backgroundColor: Colors.green,
        ));
        context.go('/sales');
      }
    } catch (e) {
      _showError('خطأ: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final total = cart.fold(0.0, (sum, i) => sum + i.totalPrice);

    return Scaffold(
      appBar: AppBar(title: const Text('بيع جديد')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Customer selector ────────────────────────────
                _SectionHeader(title: 'العميل', icon: Icons.person_rounded),
                const SizedBox(height: 8),
                _CustomerSelector(
                  selectedId: _selectedCustomerId,
                  selectedName: _selectedCustomerName,
                  onSelected: (id, name) => setState(() {
                    _selectedCustomerId = id;
                    _selectedCustomerName = name;
                  }),
                ),
                const SizedBox(height: 20),

                // ── Products ──────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _SectionHeader(
                        title: 'المنتجات', icon: Icons.shopping_bag_rounded),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('إضافة منتج'),
                      onPressed: () => _showProductPicker(context),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (cart.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: colors.outline.withOpacity(0.3),
                          style: BorderStyle.solid),
                      borderRadius: BorderRadius.circular(12),
                      color: colors.surfaceVariant.withOpacity(0.3),
                    ),
                    child: Center(
                      child: Text('أضف منتجات للفاتورة',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant)),
                    ),
                  )
                else
                  ...cart.map((item) => _CartItemTile(
                        item: item,
                        onRemove: () =>
                            cartNotifier.removeItem(item.inventoryId),
                        onQuantityChanged: (q) =>
                            cartNotifier.updateQuantity(item.inventoryId, q),
                        onPriceChanged: (p) =>
                            cartNotifier.updatePrice(item.inventoryId, p),
                      )),
                const SizedBox(height: 20),

                // ── Sale type ──────────────────────────────────────
                _SectionHeader(title: 'نوع البيع', icon: Icons.category_rounded),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'normal',
                        label: Text('عادي'),
                        icon: Icon(Icons.shopping_cart_rounded)),
                    ButtonSegment(
                        value: 'bulk',
                        label: Text('مجمع'),
                        icon: Icon(Icons.inventory_2_rounded)),
                  ],
                  selected: {_saleType},
                  onSelectionChanged: (s) =>
                      setState(() => _saleType = s.first),
                  style: ButtonStyle(
                    minimumSize: WidgetStateProperty.all(
                        const Size.fromHeight(44)),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Status ─────────────────────────────────────────
                _SectionHeader(title: 'حالة البيع', icon: Icons.info_rounded),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'paid',
                        label: Text('تم الدفع'),
                        icon: Icon(Icons.check_circle_rounded)),
                    ButtonSegment(
                        value: 'pending',
                        label: Text('تحت التسليم'),
                        icon: Icon(Icons.pending_rounded)),
                  ],
                  selected: {_status},
                  onSelectionChanged: (s) => setState(() => _status = s.first),
                  style: ButtonStyle(
                    minimumSize: WidgetStateProperty.all(
                        const Size.fromHeight(44)),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Date ────────────────────────────────────────────
                _SectionHeader(
                    title: 'تاريخ البيع', icon: Icons.calendar_today_rounded),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined),
                  label:
                      Text(DateFormat('d MMMM y', 'ar').format(_saleDate)),
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _saleDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) setState(() => _saleDate = date);
                  },
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44)),
                ),
                const SizedBox(height: 20),

                // ── Notes ───────────────────────────────────────────
                _SectionHeader(title: 'ملاحظات', icon: Icons.notes_rounded),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'ملاحظات إضافية (اختياري)',
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),

          // ── Bottom total + submit ──────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('الإجمالي',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant)),
                    Text(
                      '${NumberFormat('#,##0.##', 'ar').format(total)} ج.م',
                      style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.primary),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _submit,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_rounded),
                    label: const Text('حفظ الفاتورة'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showProductPicker(BuildContext context) {
    final inventoryAsync = ref.read(inventoryStreamProvider);
    inventoryAsync.whenData((items) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _ProductPickerSheet(
          items: items,
          onAdd: (item) {
            ref.read(cartProvider.notifier).addItem(item);
          },
        ),
      );
    });
  }
}

class _CustomerSelector extends ConsumerWidget {
  final String? selectedId;
  final String? selectedName;
  final Function(String id, String name) onSelected;

  const _CustomerSelector({
    this.selectedId,
    this.selectedName,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _showCustomerPicker(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: colors.outline.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12),
          color: colors.surfaceVariant.withOpacity(0.3),
        ),
        child: Row(
          children: [
            Icon(Icons.person_outlined, color: colors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                selectedName ?? 'اختر العميل',
                style: selectedId != null
                    ? Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)
                    : Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _showCustomerPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => _CustomerPickerSheet(
          controller: controller,
          onSelected: onSelected,
        ),
      ),
    );
  }
}

class _CustomerPickerSheet extends ConsumerStatefulWidget {
  final ScrollController controller;
  final Function(String id, String name) onSelected;
  const _CustomerPickerSheet(
      {required this.controller, required this.onSelected});

  @override
  ConsumerState<_CustomerPickerSheet> createState() =>
      _CustomerPickerSheetState();
}

class _CustomerPickerSheetState
    extends ConsumerState<_CustomerPickerSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(allCustomersProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'بحث...',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: customersAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Text('خطأ في التحميل'),
              data: (customers) {
                final filtered = _search.isEmpty
                    ? customers
                    : customers
                        .where((c) =>
                            c.name
                                .toLowerCase()
                                .contains(_search.toLowerCase()) ||
                            c.phone.contains(_search))
                        .toList();
                return ListView(
                  controller: widget.controller,
                  children: filtered
                      .map((c) => ListTile(
                            leading: const CircleAvatar(
                                child: Icon(Icons.person_rounded)),
                            title: Text(c.name),
                            subtitle: Text(c.phone),
                            onTap: () {
                              widget.onSelected(c.id, c.name);
                              Navigator.pop(context);
                            },
                          ))
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductPickerSheet extends StatefulWidget {
  final List<InventoryModel> items;
  final Function(SaleItemModel) onAdd;
  const _ProductPickerSheet({required this.items, required this.onAdd});

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? widget.items
        : widget.items
            .where((i) =>
                i.brand.toLowerCase().contains(_search.toLowerCase()) ||
                i.productName.toLowerCase().contains(_search.toLowerCase()) ||
                i.size.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (ctx, controller) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'بحث في المنتجات...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: filtered.length,
                itemBuilder: (ctx, index) {
                  final item = filtered[index];
                  return ListTile(
                    title: Text('${item.brand} - ${item.productName}'),
                    subtitle: Text(
                        'مقاس ${item.size} | ${item.currentBalance} قطعة | ${NumberFormat('#,##0', 'ar').format(item.currentPrice)} ج.م'),
                    trailing: item.currentBalance > 0
                        ? IconButton(
                            icon: const Icon(Icons.add_circle_rounded,
                                color: Colors.green),
                            onPressed: () {
                              widget.onAdd(SaleItemModel(
                                inventoryId: item.id,
                                brand: item.brand,
                                productName: item.productName,
                                size: item.size,
                                quantity: 1,
                                priceAtSale: item.currentPrice,
                              ));
                              Navigator.pop(context);
                            },
                          )
                        : const Chip(label: Text('نفذ')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final SaleItemModel item;
  final VoidCallback onRemove;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<double> onPriceChanged;

  const _CartItemTile({
    required this.item,
    required this.onRemove,
    required this.onQuantityChanged,
    required this.onPriceChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${item.brand} - ${item.productName} (${item.size})',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: colors.error),
                  onPressed: onRemove,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Quantity
                Expanded(
                  child: Row(
                    children: [
                      const Text('الكمية: '),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 22),
                        onPressed: item.quantity > 1
                            ? () => onQuantityChanged(item.quantity - 1)
                            : null,
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('${item.quantity}',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 22),
                        onPressed: () => onQuantityChanged(item.quantity + 1),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
                // Price
                Expanded(
                  child: TextFormField(
                    initialValue: item.priceAtSale.toString(),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'السعر',
                      suffixText: 'ج.م',
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final price = double.tryParse(v);
                      if (price != null) onPriceChanged(price);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'الإجمالي: ${NumberFormat('#,##0.##', 'ar').format(item.totalPrice)} ج.م',
                style: TextStyle(
                    color: colors.primary, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
