part of 'exports_screen.dart';

// ── Physical Crate Panel ──────────────────────────────────────────────────────

class _PhysicalCratePanel extends StatelessWidget {
  final CrateType crateType;
  final String? destDir;
  final bool creating;
  final double progress;
  final PhysicalCrateResult? result;
  final ValueChanged<CrateType> onTypeChanged;
  final VoidCallback onPickDir;
  final VoidCallback onCreate;

  const _PhysicalCratePanel({
    required this.crateType,
    required this.destDir,
    required this.creating,
    required this.progress,
    required this.result,
    required this.onTypeChanged,
    required this.onPickDir,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(28, 8, 28, 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.violet.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(children: [
            const Icon(Icons.folder_special_rounded,
                color: AppTheme.violet, size: 14),
            const SizedBox(width: 8),
            const Text('Create Physical Crate',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),

          // Radio buttons
          Row(children: [
            _CrateTypeRadio(
              label: 'Virtual (M3U)',
              value: CrateType.virtualOnly,
              groupValue: crateType,
              onChanged: onTypeChanged,
            ),
            const SizedBox(width: 16),
            _CrateTypeRadio(
              label: 'Copy Files',
              value: CrateType.copyFiles,
              groupValue: crateType,
              onChanged: onTypeChanged,
            ),
            const SizedBox(width: 16),
            _CrateTypeRadio(
              label: 'Alias Links',
              value: CrateType.aliasLinks,
              groupValue: crateType,
              onChanged: onTypeChanged,
            ),
          ]),

          // Destination folder row (hidden for virtual-only)
          if (crateType != CrateType.virtualOnly) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.panel,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.edge),
                  ),
                  child: Text(
                    destDir ?? 'No folder selected…',
                    style: TextStyle(
                        color: destDir != null
                            ? AppTheme.textPrimary
                            : AppTheme.textTertiary,
                        fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onPickDir,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.cyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppTheme.cyan.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_open_rounded,
                            color: AppTheme.cyan, size: 13),
                        SizedBox(width: 6),
                        Text('Browse',
                            style: TextStyle(
                                color: AppTheme.cyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ]),
                ),
              ),
            ]),
          ],

          const SizedBox(height: 12),

          // Create button + progress
          Row(children: [
            GestureDetector(
              onTap: creating ? null : onCreate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  gradient: creating
                      ? null
                      : const LinearGradient(
                          colors: [AppTheme.violet, Color(0xFF6D4AE6)]),
                  color: creating ? AppTheme.edge : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: creating
                    ? const SizedBox(
                        width: 60,
                        height: 14,
                        child: Center(
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          ),
                        ),
                      )
                    : const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.create_new_folder_rounded,
                            color: Colors.white, size: 13),
                        SizedBox(width: 6),
                        Text('Create Crate',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ]),
              ),
            ),
            if (creating) ...[
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppTheme.edge,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppTheme.violet),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('${(progress * 100).toInt()}%',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11)),
            ],
          ]),

          // Result summary
          if (result != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: result!.errors.isEmpty
                    ? AppTheme.lime.withValues(alpha: 0.08)
                    : AppTheme.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: result!.errors.isEmpty
                        ? AppTheme.lime.withValues(alpha: 0.3)
                        : AppTheme.amber.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(
                      result!.errors.isEmpty
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      color: result!.errors.isEmpty
                          ? AppTheme.lime
                          : AppTheme.amber,
                      size: 13,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${result!.filesCopied} file(s) created  ·  '
                      '${result!.filesSkipped} skipped'
                      '${result!.errors.isNotEmpty ? "  ·  ${result!.errors.length} error(s)" : ""}',
                      style: TextStyle(
                          color: result!.errors.isEmpty
                              ? AppTheme.lime
                              : AppTheme.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(result!.cratePath,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 10),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CrateTypeRadio extends StatelessWidget {
  final String label;
  final CrateType value;
  final CrateType groupValue;
  final ValueChanged<CrateType> onChanged;
  const _CrateTypeRadio(
      {required this.label,
      required this.value,
      required this.groupValue,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? AppTheme.violet : AppTheme.textTertiary,
                width: 2),
            color: selected
                ? AppTheme.violet.withValues(alpha: 0.2)
                : Colors.transparent,
          ),
          child: selected
              ? Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.violet,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: selected
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ]),
    );
  }
}

// ── Export button ─────────────────────────────────────────────────────────────

class _ExportBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;
  const _ExportBtn(
      {required this.label,
      required this.icon,
      required this.loading,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.cyan.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.3)),
        ),
        child: loading
            ? const SizedBox(
                width: 40,
                height: 16,
                child: Center(
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        color: AppTheme.cyan, strokeWidth: 2),
                  ),
                ),
              )
            : Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: AppTheme.cyan, size: 13),
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(
                        color: AppTheme.cyan,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ]),
      ),
    );
  }
}
