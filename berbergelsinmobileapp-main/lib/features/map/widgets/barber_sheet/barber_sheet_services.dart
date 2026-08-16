import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/barbers_repo.dart';

class BarberServicesSection extends StatefulWidget {
  const BarberServicesSection({
    super.key,
    required this.services,
    required this.previewOnly,
    required this.selectedServiceIds,
    required this.onSelectionChanged,
  });

  final List<BarberServiceItem> services;
  final bool previewOnly;
  final Set<String> selectedServiceIds;
  final void Function(String serviceId, bool selected) onSelectionChanged;

  @override
  State<BarberServicesSection> createState() => _BarberServicesSectionState();
}

class _BarberServicesSectionState extends State<BarberServicesSection> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final services = widget.services
        .where((service) {
          final query = _query.trim().toLowerCase();
          return query.isEmpty ||
              service.name.toLowerCase().contains(query) ||
              (service.description ?? '').toLowerCase().contains(query);
        })
        .toList(growable: false);
    return Column(
      key: const ValueKey('barber-services-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hizmetler',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: widget.previewOnly ? 2 : 8),
        if (!widget.previewOnly && widget.services.length > 4) ...[
          TextField(
            key: const Key('service-search-field'),
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              labelText: 'Hizmet ara',
              prefixIcon: Icon(Icons.search),
              hintText: 'Hizmet adına göre arayın',
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (services.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Henüz hizmet eklenmemiş.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          )
        else
          ...services.map(
            (service) => Padding(
              padding: EdgeInsets.only(bottom: widget.previewOnly ? 1 : 8),
              child: _ServiceRow(
                service: service,
                previewOnly: widget.previewOnly,
                selected: widget.selectedServiceIds.contains(service.id),
                onSelectionChanged: widget.onSelectionChanged,
              ),
            ),
          ),
      ],
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.service,
    required this.previewOnly,
    required this.selected,
    required this.onSelectionChanged,
  });

  final BarberServiceItem service;
  final bool previewOnly;
  final bool selected;
  final void Function(String serviceId, bool selected) onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final price = _formatServicePrice(service);
    final duration = service.durationMinutes == null
        ? null
        : '${service.durationMinutes} dk';
    final description = service.description?.trim();
    final semanticsParts = [
      service.name,
      if (duration != null) duration,
      if (description?.isNotEmpty == true) description!,
      price,
      if (service.isPopular) 'Popüler',
      if (!previewOnly) selected ? 'seçili' : 'seçili değil',
    ];

    final content = Container(
      key: ValueKey('barber-service-${service.id}'),
      constraints: BoxConstraints(minHeight: previewOnly ? 34 : 48),
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: previewOnly ? 2 : 7,
      ),
      decoration: BoxDecoration(
        color: selected && !previewOnly
            ? AppTheme.primary.withValues(alpha: 0.06)
            : AppTheme.fieldFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected && !previewOnly
              ? AppTheme.primary
              : const Color(0xFFE5E6EA),
          width: selected && !previewOnly ? 1.4 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!previewOnly) ...[
            _SelectionIndicator(selected: selected),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                if (duration != null || service.isPopular) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (duration != null)
                        Text(
                          duration,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (service.isPopular) const _PopularBadge(),
                    ],
                  ),
                ],
                if (description?.isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 112),
            child: Text(
              price,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
              ),
            ),
          ),
        ],
      ),
    );

    if (previewOnly) {
      return Semantics(
        container: true,
        key: ValueKey('barber-service-info-'),
        label: semanticsParts.join(', '),
        child: ExcludeSemantics(child: content),
      );
    }

    return Semantics(
      container: true,
      key: ValueKey('barber-service-control-${service.id}'),
      label: semanticsParts.join(', '),
      button: true,
      selected: selected,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onSelectionChanged(service.id, !selected),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('barber-service-selection-indicator'),
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppTheme.primary : const Color(0xFFC5C6CC),
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
          : null,
    );
  }
}

class _PopularBadge extends StatelessWidget {
  const _PopularBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Popüler',
        style: TextStyle(
          color: AppTheme.primary,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _formatServicePrice(BarberServiceItem service) {
  final prefix = switch (service.priceType) {
    'From' => 'Başlangıç ',
    'Quote' => 'Tahmini ',
    _ => '',
  };
  final raw = service.price.toStringAsFixed(2);
  final parts = raw.split('.');
  final integer = _groupThousands(parts.first);
  final decimals = parts[1].replaceFirst(RegExp(r'0+$'), '');
  return '$prefix$integer${decimals.isEmpty ? '' : ',$decimals'} TL';
}

String _groupThousands(String value) {
  return value.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
}
