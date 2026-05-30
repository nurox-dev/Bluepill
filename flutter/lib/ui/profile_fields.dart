import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/profile_options.dart';

class CityAutocompleteField extends StatefulWidget {
  const CityAutocompleteField({
    super.key,
    required this.controller,
    this.required = false,
  });

  final TextEditingController controller;
  final bool required;

  @override
  State<CityAutocompleteField> createState() => _CityAutocompleteFieldState();
}

class _CityAutocompleteFieldState extends State<CityAutocompleteField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return cityOptions.take(8);
        return cityOptions
            .where((city) => city.toLowerCase().contains(query))
            .take(10);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: 'Location',
            hintText: 'Search city',
            prefixIcon: Icon(Icons.location_city_outlined),
          ),
          textInputAction: TextInputAction.next,
          validator: widget.required
              ? (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null
              : null,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final colorScheme = Theme.of(context).colorScheme;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            clipBehavior: Clip.antiAlias,
            color: colorScheme.surfaceContainerHigh,
            elevation: 3,
            shadowColor: Colors.black.withValues(alpha: 0.16),
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 420),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  final highlighted =
                      AutocompleteHighlightedOption.of(context) == index;
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Container(
                      color:
                          highlighted ? colorScheme.secondaryContainer : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(option),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class DatePickerField extends StatelessWidget {
  const DatePickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return FormField<DateTime>(
      initialValue: value,
      validator: (_) => required && value == null ? 'Required' : null,
      builder: (field) {
        final hasValue = value != null;
        final shape = RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(18),
        );
        return InkWell(
          customBorder: shape,
          onTap: () async {
            final now = DateTime.now();
            final selected = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime(now.year - 18, now.month, now.day),
              firstDate: DateTime(now.year - 100),
              lastDate: now,
            );
            if (selected == null) return;
            field.didChange(selected);
            onChanged(selected);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.cake_outlined),
              errorText: field.errorText,
            ),
            child: Text(
              hasValue
                  ? DateFormat('MMM d, yyyy').format(value!)
                  : 'Select date',
              style: TextStyle(
                color: hasValue
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}

class MultiSelectChipsField extends StatefulWidget {
  const MultiSelectChipsField({
    super.key,
    required this.label,
    required this.icon,
    required this.options,
    required this.selectedValues,
    required this.onChanged,
    this.required = false,
  });

  final String label;
  final IconData icon;
  final List<String> options;
  final List<String> selectedValues;
  final ValueChanged<List<String>> onChanged;
  final bool required;

  @override
  State<MultiSelectChipsField> createState() => _MultiSelectChipsFieldState();
}

class _MultiSelectChipsFieldState extends State<MultiSelectChipsField> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormField<List<String>>(
      initialValue: widget.selectedValues,
      validator: (_) {
        if (widget.required && widget.selectedValues.isEmpty) {
          return 'Choose at least one';
        }
        return null;
      },
      builder: (field) {
        final query = _filter.text.trim().toLowerCase();
        final filtered = widget.options
            .where(
              (option) => query.isEmpty || option.toLowerCase().contains(query),
            )
            .take(16)
            .toList();
        final canAdd = query.isNotEmpty &&
            !widget.options.any((option) => option.toLowerCase() == query) &&
            !widget.selectedValues
                .any((option) => option.toLowerCase() == query);

        void update(List<String> next) {
          widget.onChanged(next);
          field.didChange(next);
        }

        void addCustom() {
          final value = _titleCase(_filter.text.trim());
          if (value.isEmpty) return;
          update([...widget.selectedValues, value]);
          _filter.clear();
          setState(() {});
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  widget.label,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _filter,
              decoration: InputDecoration(
                hintText: 'Search or add ${widget.label.toLowerCase()}',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: canAdd
                    ? IconButton(
                        tooltip: 'Add',
                        onPressed: addCustom,
                        icon: const Icon(Icons.add_circle_outline),
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (canAdd) addCustom();
              },
            ),
            if (widget.selectedValues.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in widget.selectedValues)
                    InputChip(
                      label: Text(value),
                      onDeleted: () => update(
                        widget.selectedValues
                            .where((item) => item != value)
                            .toList(),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in filtered)
                  FilterChip(
                    label: Text(option),
                    selected: widget.selectedValues.contains(option),
                    onSelected: (selected) {
                      if (selected) {
                        update([...widget.selectedValues, option]);
                      } else {
                        update(widget.selectedValues
                            .where((item) => item != option)
                            .toList());
                      }
                    },
                  ),
                if (canAdd)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text('Add "${_titleCase(_filter.text.trim())}"'),
                    onPressed: addCustom,
                  ),
              ],
            ),
            if (field.hasError) ...[
              const SizedBox(height: 6),
              Text(
                field.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        );
      },
    );
  }
}

String _titleCase(String value) {
  return value
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join(' ');
}
