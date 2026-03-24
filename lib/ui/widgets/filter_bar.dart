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

    return Focus(
      focusNode: filterFocusNode,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.edge),
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
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search tracks, artists, genres, vibes',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh'),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.edge),
                  ),
                  child: Text(
                    'Cmd+K search · Cmd+F filters',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white60,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
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
                const SizedBox(width: 12),
                Expanded(
                  child: _SelectField(
                    label: 'Vibe',
                    value: filters.vibe,
                    values: vibes,
                    onChanged: (value) =>
                        onFiltersChanged(filters.copyWith(vibe: value)),
                  ),
                ),
                const SizedBox(width: 12),
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
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _SliderField(
                    label: 'BPM range',
                    value: filters.bpmRange,
                    min: 80,
                    max: 160,
                    formatValue: (value) => value.round().toString(),
                    onChanged: (value) =>
                        onFiltersChanged(filters.copyWith(bpmRange: value)),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: _SliderField(
                    label: 'Energy level',
                    value: filters.energyRange,
                    min: 0,
                    max: 1,
                    formatValue: (value) => '${(value * 100).round()}%',
                    onChanged: (value) =>
                        onFiltersChanged(filters.copyWith(energyRange: value)),
                  ),
                ),
              ],
            ),
          ],
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
      decoration: InputDecoration(labelText: label),
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
  });

  final String label;
  final RangeValues value;
  final double min;
  final double max;
  final String Function(double value) formatValue;
  final ValueChanged<RangeValues> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text(
                '${formatValue(value.start)} - ${formatValue(value.end)}',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: Colors.white60),
              ),
            ],
          ),
          RangeSlider(
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
        ],
      ),
    );
  }
}
