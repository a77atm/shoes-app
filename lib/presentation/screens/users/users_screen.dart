import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/models.dart';
import '../../../presentation/providers/providers.dart';

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersStreamProvider);
    final currentUserAsync = ref.watch(currentUserProvider);
    final isAdmin = currentUserAsync.when(
        data: (u) => u?.isAdmin ?? false,
        loading: () => false,
        error: (_, __) => false);

    if (!isAdmin) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outlined, size: 64),
              SizedBox(height: 16),
              Text('ليس لديك صلاحية للوصول لهذه الصفحة'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('إدارة المستخدمين')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddUserDialog(context, ref),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('مستخدم جديد'),
      ),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e')),
        data: (users) {
          if (users.isEmpty) {
            return const Center(child: Text('لا يوجد مستخدمون'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) => _UserCard(
              user: users[i],
              currentUserId: currentUserAsync.whenOrNull(data: (u) => u?.id),
            ),
          );
        },
      ),
    );
  }

  void _showAddUserDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String role = 'employee';
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('إضافة مستخدم جديد'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'الاسم *'),
                    validator: (v) =>
                        (v?.isEmpty ?? true) ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني *'),
                    validator: (v) {
                      if (v?.isEmpty ?? true) return 'مطلوب';
                      if (!v!.contains('@')) return 'بريد غير صالح';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'كلمة المرور *'),
                    validator: (v) {
                      if (v?.isEmpty ?? true) return 'مطلوب';
                      if (v!.length < 6) return 'على الأقل 6 حروف';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(labelText: 'الدور'),
                    items: const [
                      DropdownMenuItem(
                          value: 'employee', child: Text('موظف')),
                      DropdownMenuItem(value: 'admin', child: Text('مدير')),
                    ],
                    onChanged: (v) => setState(() => role = v ?? 'employee'),
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
              onPressed: isLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setState(() => isLoading = true);
                      try {
                        await ref.read(authServiceProvider).createUser(
                              name: nameCtrl.text.trim(),
                              email: emailCtrl.text.trim(),
                              password: passCtrl.text,
                              role: role,
                            );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setState(() => isLoading = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text('خطأ: $e'),
                            backgroundColor: Colors.red,
                          ));
                        }
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends ConsumerWidget {
  final UserModel user;
  final String? currentUserId;
  const _UserCard({required this.user, this.currentUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isCurrentUser = user.id == currentUserId;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: user.isAdmin
              ? colors.primaryContainer
              : colors.secondaryContainer,
          child: Icon(
            user.isAdmin
                ? Icons.admin_panel_settings_rounded
                : Icons.person_rounded,
            color: user.isAdmin ? colors.primary : colors.secondary,
          ),
        ),
        title: Row(
          children: [
            Text(user.name,
                style:
                    theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (isCurrentUser) ...[
              const SizedBox(width: 8),
              Chip(
                label: const Text('أنت', style: TextStyle(fontSize: 10)),
                backgroundColor: colors.primaryContainer,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.email, style: theme.textTheme.bodySmall),
            Text(
              user.isAdmin ? 'مدير' : 'موظف',
              style: TextStyle(
                  color: user.isAdmin ? colors.primary : colors.secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: isCurrentUser
            ? null
            : Switch.adaptive(
                value: user.isActive,
                onChanged: (v) => ref
                    .read(authServiceProvider)
                    .toggleUserStatus(user.id, v),
              ),
      ),
    );
  }
}
