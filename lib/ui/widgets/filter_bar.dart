import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/track_filters.dart';

class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.filterFocusNode,
    required this.filters,
    required this.genres,
    required this.vibes,
    required this.regions,
    required this.onSearchChanged,
    required this.onFiltersChanged,
    required this.onRefresh,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final FocusNode filterFocusNode;
  final TrackFilters filters;
  final List<String> genres;
  final List<String> vibes;
  final List<String> regions;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<TrackFilters> onFiltersChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  focusNode: searchFocusNode,
                  onChanged: onSearchChanged,
                  maxLength: 100,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textTertiary, size: 18),
                    hintText: 'Search tracks, artists, genres, vibes',
                    hintStyle: const TextStyle(color: AppTheme.textTertiary),
                    counterText: '',
                    filled: true,
                    fillColor: AppTheme.panelRaised,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _ActionButton(
                icon: Icons.refresh_rounded,
                label: 'Refresh',
                onPressed: onRefresh,
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.panelRaised,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.edge.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '⌘K search  ·  ⌘F filters',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SelectField(
                  label: 'Genre',
                  value: filters.genre,
                  values: genres,
                  onChanged: (value) =>
                      onFiltersChanged(filters.copyWith(genre: value)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SelectField(
                  label: 'Vibe',
                  value: filters.vibe,
                  values: vibes,
                  onChanged: (value) =>
                      onFiltersChanged(filters.copyWith(vibe: value)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SelectField(
                  label: 'Region',
                  value: filters.region,
                  values: regions,
                  onChanged: (value) =>
                      onFiltersChanged(filters.copyWith(region: value)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SliderField(
                  label: 'BPM range',
                  value: filters.bpmRange,
                  min: 60,
                  max: 200,
                  formatValue: (value) => value.round().toString(),
                  onChanged: (value) =>
                      onFiltersChanged(filters.copyWith(bpmRange: value)),
                  accentColor: AppTheme.cyan,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _SliderField(
                  label: 'Energy level',
                  value: filters.energyRange,
                  min: 0,
                  max: 1,
                  formatValue: (value) => '${(value * 100).round()}%',
                  onChanged: (value) =>
                      onFiltersChanged(filters.copyWith(energyRange: value)),
                  accentColor: AppTheme.pink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.violet.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.violet, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.violet,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectField extends StatelessWidget {
  const _SelectField({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: values.contains(value) ? value : values.firstOrNull,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
        filled: true,
        fillColor: AppTheme.panelRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      dropdownColor: AppTheme.panelRaised,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      items: values
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.formatValue,
    required this.onChanged,
    required this.accentColor,
  });

  final String label;
  final RangeValues value;
  final double min;
  final double max;
  final String Function(double value) formatValue;
  final ValueChanged<RangeValues> onChanged;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${formatValue(value.start)} – ${formatValue(value.end)}',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accentColor,
              inactiveTrackColor: AppTheme.edge,
              thumbColor: accentColor,
              overlayColor: accentColor.withValues(alpha: 0.1),
              rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 6),
              trackHeight: 3,
            ),
            child: RangeSlider(
              values: value,
              min: min,
              max: max,
              divisions: 20,
              labels: RangeLabels(
                formatValue(value.start),
                formatValue(value.end),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
