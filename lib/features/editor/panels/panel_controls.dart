import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';

class PanelSection extends StatelessWidget {
  const PanelSection({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class SliderRow extends StatelessWidget {
  const SliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.valueLabel,
    this.onReset,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;
  final String? valueLabel;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            if (onReset != null)
              GestureDetector(
                onTap: onReset,
                child: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.restart_alt_rounded,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            Text(
              valueLabel ?? value.toStringAsFixed(2),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textPrimary,
                fontFamily: AppFonts.mono,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class SegmentedRow<T> extends StatelessWidget {
  const SegmentedRow({
    super.key,
    required this.options,
    required this.labelOf,
    required this.selected,
    required this.onSelected,
  });

  final List<T> options;
  final String Function(T value) labelOf;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final option in options)
          _SegmentChip(
            label: labelOf(option),
            selected: option == selected,
            onTap: () => onSelected(option),
          ),
      ],
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.alpha(AppColors.accent, 0.16)
              : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.alpha(AppColors.accent, 0.55)
                : AppColors.stroke,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.accent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.accent = AppColors.accent,
    this.danger = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color accent;
  final bool danger;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.alpha(color, 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class ColorSwatches extends StatelessWidget {
  const ColorSwatches({
    super.key,
    required this.selected,
    required this.onSelected,
    this.options = defaultColors,
  });

  static const List<int> defaultColors = <int>[
    0xFFFFFFFF,
    0xFFFFE082,
    0xFFF2B24A,
    0xFFFF6B81,
    0xFF4FE0B0,
    0xFF63C7FF,
    0xFF8B7BFF,
    0xFF111111,
  ];

  final int selected;
  final ValueChanged<int> onSelected;
  final List<int> options;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final color in options)
          GestureDetector(
            onTap: () => onSelected(color),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Color(color),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected == color
                      ? AppColors.accent
                      : AppColors.stroke,
                  width: selected == color ? 2 : 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class InfoNote extends StatelessWidget {
  const InfoNote({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.color = AppColors.textMuted,
  });

  final String message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.alpha(color, 0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.alpha(color, 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 11, height: 1.4, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
