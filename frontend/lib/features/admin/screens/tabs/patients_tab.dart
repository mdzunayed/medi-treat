import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/user.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/mt_error_state.dart';
import '../../admin_providers.dart';
import 'admin_table_chrome.dart';

/// "Patients" sidebar screen — accounts with `role: 'user'`. The admin
/// scans this for sign-up volume, support context, and basic moderation.
class PatientsTab extends ConsumerWidget {
  const PatientsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminPatientsProvider);
    return AdminListScaffold(
      title: 'Patients',
      subtitle: 'All registered patient accounts',
      onRefresh: () async {
        ref.invalidate(adminPatientsProvider);
        await ref.read(adminPatientsProvider.future);
      },
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => MtErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(adminPatientsProvider),
        ),
        data: (rows) => rows.isEmpty
            ? const AdminEmptyState(
                icon: Icons.people_outline,
                title: 'No patients yet',
                subtitle: 'New sign-ups will appear here automatically.',
              )
            : _PatientsTable(rows: rows),
      ),
    );
  }
}

class _PatientsTable extends StatelessWidget {
  final List<User> rows;
  const _PatientsTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.all(MtColors.brandSofter),
          headingTextStyle: MtTextStyles.labelSm.copyWith(
            color: MtColors.ink3,
            letterSpacing: 0.8,
          ),
          dataRowMinHeight: 56,
          dataRowMaxHeight: 64,
          columns: const [
            DataColumn(label: Text('NAME')),
            DataColumn(label: Text('PHONE')),
            DataColumn(label: Text('EMAIL')),
            DataColumn(label: Text('STATUS')),
          ],
          rows: [
            for (final u in rows)
              DataRow(cells: [
                DataCell(_NameCell(name: u.name)),
                DataCell(Text(u.phone.isEmpty ? '—' : u.phone,
                    style: MtTextStyles.bodyMd
                        .copyWith(color: MtColors.ink2))),
                DataCell(Text(u.email.isEmpty ? '—' : u.email,
                    style: MtTextStyles.bodyMd
                        .copyWith(color: MtColors.ink2))),
                DataCell(_StatusPill(label: u.accountStatus)),
              ]),
          ],
        ),
      ),
    );
  }
}

class _NameCell extends StatelessWidget {
  final String name;
  const _NameCell({required this.name});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InitialsAvatar(
          name: name,
          size: 32,
          backgroundColor: MtColors.brandSoft,
          textColor: MtColors.brand,
        ),
        const SizedBox(width: 10),
        Text(name,
            style: MtTextStyles.labelMd.copyWith(color: MtColors.ink)),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  const _StatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final active = label.toLowerCase() == 'active';
    final fg = active ? MtColors.completed : MtColors.ink3;
    final bg = active ? MtColors.completedBg : MtColors.bg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label.toUpperCase(),
        style:
            MtTextStyles.labelSm.copyWith(color: fg, fontSize: 9),
      ),
    );
  }
}
