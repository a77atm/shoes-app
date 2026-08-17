import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../data/models/models.dart';
import '../../../presentation/providers/providers.dart';
import '../../../core/constants/app_constants.dart';
import 'package:intl/intl.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _searchController = TextEditingController();
  bool _isGrid = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventoryAsync = ref.watch(inventoryStreamProvider);
    final currentUser =
        ref.watch(currentUserProvider).whenOrNull(data: (u) => u);
    final isAdmin = currentUser?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.inventory),
        actions: [
          IconButton(
            icon: Icon(_isGrid ? Icons.list_rounded : Icons.grid_view_rounded),
            onPressed: () => setState(() => _isGrid = !_isGrid),
            tooltip: _isGrid ? 'عرض قائمة' : 'عرض شبكة',
          ),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/inventory/add'),
              icon: const Icon(Icons.add),
              label: const Text('إضافة منتج'),
            )
          : null,
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'بحث بالماركة أو الاسم أو المقاس...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(inventorySearchProvider.notifier)
                              .state = '';
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                ref.read(inventorySearchProvider.notifier).state = value;
              },
            ),
          ),

          // Inventory list
          Expanded(
            child: inventoryAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('خطأ: $e')),
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 72,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withOpacity(0.4)),
                        const SizedBox(height: 16),
                        Text(AppStrings.noData,
                            style: Theme.of(context).textTheme.bodyLarge),
                      ],
                    ),
                  );
                }

                if (_isGrid) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.45,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) => _InventoryGridCard(
                      item: items[index],
                      isAdmin: isAdmin,
                      index: index,
                    ),
                  );
                } else {
                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _InventoryListCard(
                      item: items[index],
                      isAdmin: isAdmin,
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryGridCard extends ConsumerWidget {
  final InventoryModel item;
  final bool isAdmin;
  final int index;
  const _InventoryGridCard(
      {required this.item, required this.isAdmin, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isAdmin ? () => context.go('/inventory/edit/${item.id}') : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.brand,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (item.isLowStock)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color:
                            item.currentBalance == 0 ? Colors.red : Colors.orange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.currentBalance == 0 ? 'نفذ' : 'منخفض',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                item.productName,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Chip(
                    label:
                        Text(item.size, style: const TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  Flexible(
                    child: Text(
                      '${item.currentBalance} قطعة',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: item.isLowStock
                              ? Colors.orange
                              : colors.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${NumberFormat('#,##0', 'ar').format(item.currentPrice)} ج.م',
                style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold, color: colors.primary),
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: Duration(milliseconds: index * 50))
        .slideY(begin: 0.1);
  }
}

class _InventoryListCard extends ConsumerWidget {
  final InventoryModel item;
  final bool isAdmin;
  const _InventoryListCard({required this.item, required this.isAdmin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: ListTile(
        title: Text('${item.brand} - ${item.productName}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('مقاس: ${item.size} | رصيد: ${item.currentBalance}/${item.openingBalance}'),
            Text(
              '${NumberFormat('#,##0', 'ar').format(item.currentPrice)} ج.م',
              style:
                  TextStyle(color: colors.primary, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: item.isLowStock
            ? Icon(
                Icons.warning_amber_rounded,
                color: item.currentBalance == 0 ? Colors.red : Colors.orange,
              )
            : null,
        onTap: isAdmin ? () => context.go('/inventory/edit/${item.id}') : null,
      ),
    );
  }
}

