import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/models/models.dart';
import '../../../presentation/providers/providers.dart';

class AddEditInventoryScreen extends ConsumerStatefulWidget {
  final String? inventoryId;
  const AddEditInventoryScreen({super.key, this.inventoryId});

  @override
  ConsumerState<AddEditInventoryScreen> createState() =>
      _AddEditInventoryScreenState();
}

class _AddEditInventoryScreenState
    extends ConsumerState<AddEditInventoryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _brandCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  final _openingBalanceCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _soldCtrl = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingData = false;
  InventoryModel? _existingItem;

  bool get isEdit => widget.inventoryId != null;

  @override
  void initState() {
    super.initState();
    if (isEdit) _loadItem();
  }

  Future<void> _loadItem() async {
    setState(() => _isLoadingData = true);
    final item = await ref
        .read(inventoryServiceProvider)
        .getInventoryItem(widget.inventoryId!);
    if (item != null && mounted) {
      _existingItem = item;
      _brandCtrl.text = item.brand;
      _nameCtrl.text = item.productName;
      _sizeCtrl.text = item.size;
      _openingBalanceCtrl.text = item.openingBalance.toString();
      _priceCtrl.text = item.currentPrice.toString();
      _soldCtrl.text = item.soldQuantity.toString();
    }
    if (mounted) setState(() => _isLoadingData = false);
  }

  @override
  void dispose() {
    _brandCtrl.dispose();
    _nameCtrl.dispose();
    _sizeCtrl.dispose();
    _openingBalanceCtrl.dispose();
    _priceCtrl.dispose();
    _soldCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final service = ref.read(inventoryServiceProvider);

      if (isEdit && _existingItem != null) {
        final updated = _existingItem!.copyWith(
          brand: _brandCtrl.text.trim(),
          productName: _nameCtrl.text.trim(),
          size: _sizeCtrl.text.trim(),
          openingBalance: int.parse(_openingBalanceCtrl.text),
          soldQuantity: int.parse(_soldCtrl.text),
          currentPrice: double.parse(_priceCtrl.text),
        );
        await service.updateItem(updated);
      } else {
        final newItem = InventoryModel(
          id: '',
          brand: _brandCtrl.text.trim(),
          productName: _nameCtrl.text.trim(),
          size: _sizeCtrl.text.trim(),
          openingBalance: int.parse(_openingBalanceCtrl.text),
          soldQuantity: int.tryParse(_soldCtrl.text) ?? 0,
          currentPrice: double.parse(_priceCtrl.text),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await service.addItem(newItem);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'تم تحديث المنتج' : 'تم إضافة المنتج'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/inventory');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المنتج'),
        content: Text(
            'هل أنت متأكد من حذف "${_nameCtrl.text}"؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true && _existingItem != null) {
      await ref.read(inventoryServiceProvider).deleteItem(_existingItem!.id);
      if (mounted) context.go('/inventory');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return Scaffold(
        appBar: AppBar(title: Text(isEdit ? 'تعديل المنتج' : 'إضافة منتج')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'تعديل المنتج' : 'إضافة منتج'),
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _delete,
              tooltip: 'حذف المنتج',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Brand
            TextFormField(
              controller: _brandCtrl,
              decoration: const InputDecoration(
                labelText: 'الماركة *',
                prefixIcon: Icon(Icons.branding_watermark_outlined),
              ),
              validator: (v) => (v?.isEmpty ?? true) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 12),

            // Product name
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم المنتج *',
                prefixIcon: Icon(Icons.shopping_bag_outlined),
              ),
              validator: (v) => (v?.isEmpty ?? true) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 12),

            // Size
            TextFormField(
              controller: _sizeCtrl,
              decoration: const InputDecoration(
                labelText: 'المقاس *',
                prefixIcon: Icon(Icons.straighten_rounded),
                hintText: 'مثال: 42، EU42، 8.5',
              ),
              validator: (v) => (v?.isEmpty ?? true) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 12),

            // Opening balance and sold
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _openingBalanceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'رصيد أول المدة *',
                      prefixIcon: Icon(Icons.inventory_rounded),
                    ),
                    validator: (v) {
                      if (v?.isEmpty ?? true) return 'مطلوب';
                      if (int.tryParse(v!) == null) return 'رقم غير صالح';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _soldCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'الكمية المباعة',
                      prefixIcon: Icon(Icons.sell_outlined),
                    ),
                    validator: (v) {
                      if (v?.isEmpty ?? true) return null;
                      if (int.tryParse(v!) == null) return 'رقم غير صالح';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Price
            TextFormField(
              controller: _priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'سعر البيع (ج.م) *',
                prefixIcon: Icon(Icons.attach_money_rounded),
              ),
              validator: (v) {
                if (v?.isEmpty ?? true) return 'مطلوب';
                if (double.tryParse(v!) == null) return 'سعر غير صالح';
                return null;
              },
            ),
            const SizedBox(height: 32),

            // Save button
            FilledButton.icon(
              onPressed: _isLoading ? null : _save,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_rounded),
              label: Text(isEdit ? 'حفظ التغييرات' : 'إضافة المنتج'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ),
      ),
    );
  }
}
