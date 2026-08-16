import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../data/barbers_repo.dart';

Future<DiscoveryFilters?> showDiscoveryFilterSheet(
  BuildContext context,
  DiscoveryFilters initial,
) {
  return showModalBottomSheet<DiscoveryFilters>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _DiscoveryFilterSheet(initial: initial),
  );
}

class _DiscoveryFilterSheet extends StatefulWidget {
  const _DiscoveryFilterSheet({required this.initial});
  final DiscoveryFilters initial;
  @override
  State<_DiscoveryFilterSheet> createState() => _DiscoveryFilterSheetState();
}

class _DiscoveryFilterSheetState extends State<_DiscoveryFilterSheet> {
  late final TextEditingController minPrice, maxPrice;
  late double radius, rating;
  late DiscoverySort sort;
  List<CategoryGroup> _groups = [];
  String? _category, _subCategory, serviceId;

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    minPrice = TextEditingController(text: f.minPrice?.toStringAsFixed(0) ?? '');
    maxPrice = TextEditingController(text: f.maxPrice?.toStringAsFixed(0) ?? '');
    radius = f.radiusKm;
    rating = f.minRating ?? 0;
    sort = f.sort;
    _category = f.category;
    serviceId = f.serviceId;
    BarbersRepo.instance.categoryGroups().then((g) => setState(() => _groups = g));
  }

  @override
  void dispose() {
    minPrice.dispose();
    maxPrice.dispose();
    super.dispose();
  }

  double? _number(String v) => double.tryParse(v.trim().replaceAll(',', '.'));
  DiscoveryFilters _value() => DiscoveryFilters(
    query: widget.initial.query,
    category: _subCategory ?? _category,
    serviceId: serviceId,
    minPrice: _number(minPrice.text),
    maxPrice: _number(maxPrice.text),
    minRating: rating == 0 ? null : rating,
    radiusKm: radius,
    sort: sort,
  );

  List<SubCategory> get _subCategories {
    if (_category == null) return [];
    return _groups.where((g) => g.name == _category).firstOrNull?.categories ?? [];
  }

  static const _border = Color(0xFFECECEF);

  Widget _dropdown<T>({required T? value, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged, String? hint}) =>
    InputDecorator(
      decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _border)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.any((i) => i.value == value) ? value : null,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          isDense: true,
          hint: hint != null ? Text(hint, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)) : null,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
        ),
      ),
    );

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: DraggableScrollableSheet(
      expand: false, initialChildSize: .88, maxChildSize: .95, minChildSize: .55,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(children: [
            const Expanded(child: Text('Keşif Filtreleri', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
            TextButton(onPressed: () => Navigator.pop(context, const DiscoveryFilters()), child: const Text('Temizle')),
          ]),
          const SizedBox(height: 12),

          // ── Kategori ──
          _dropdown<String>(
            value: _category,
            hint: 'Kategori seçin',
            items: [const DropdownMenuItem(value: null, child: Text('Tüm kategoriler')), ..._groups.map((g) => DropdownMenuItem(value: g.name, child: Text(g.name)))],
            onChanged: (v) => setState(() { _category = v; _subCategory = null; serviceId = null; }),
          ),
          // ── Alt kategori (sadece seçili ana kategori varsa) ──
          if (_subCategories.isNotEmpty) ...[
            const SizedBox(height: 8),
            _dropdown<String>(
              value: _subCategory,
              hint: 'Alt kategori seçin',
              items: [const DropdownMenuItem(value: null, child: Text('Tüm alt kategoriler')), ..._subCategories.map((s) => DropdownMenuItem(value: s.name, child: Text(s.name)))],
              onChanged: (v) => setState(() => _subCategory = v),
            ),
          ],
          const SizedBox(height: 10),

          // ── Hizmet ──
          FutureBuilder<List<ServiceCatalogItem>>(
            future: BarbersRepo.instance.serviceCatalog(category: _category),
            builder: (context, snap) {
              final items = snap.data ?? [];
              return _dropdown<String>(
                value: serviceId,
                hint: 'Hizmet seçin',
                items: [const DropdownMenuItem(value: null, child: Text('Tüm hizmetler')), ...items.map((e) => DropdownMenuItem(value: e.id, child: Text(e.name, overflow: TextOverflow.ellipsis)))],
                onChanged: (v) => setState(() => serviceId = v),
              );
            },
          ),
          const SizedBox(height: 12),

          // ── Fiyat ──
          Row(children: [
            Expanded(child: TextField(controller: minPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Min TL', isDense: true))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: maxPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Max TL', isDense: true))),
          ]),
          const SizedBox(height: 14),

          // ── Puan ──
          Row(children: [
            const Text('Minimum puan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const Spacer(),
            if (rating > 0) TextButton(onPressed: () => setState(() => rating = 0), child: const Text('Temizle', style: TextStyle(fontSize: 12))),
          ]),
          const SizedBox(height: 4),
          Row(children: List.generate(5, (i) {
            final s = i + 1; final active = s <= rating;
            return GestureDetector(
              onTap: () => setState(() => rating = rating == s ? 0 : s.toDouble()),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: active ? AppColors.warning.withValues(alpha: 0.1) : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: active ? AppColors.warning.withValues(alpha: 0.3) : _border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.star_rounded, color: active ? AppColors.warning : AppColors.textSecondary, size: 15),
                  const SizedBox(width: 3),
                  Text('$s', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: active ? AppColors.warning : AppColors.textSecondary)),
                ]),
              ),
            );
          })),
          const SizedBox(height: 14),

          // ── Mesafe ──
          Row(children: [
            const Text('Mesafe', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const Spacer(),
            Text('${radius.round()} km', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
          ]),
          Slider(value: radius.clamp(1, 50), min: 1, max: 50, divisions: 49, onChanged: (v) => setState(() => radius = v)),
          const SizedBox(height: 10),

          // ── Sıralama ──
          _dropdown<DiscoverySort>(
            value: sort,
            hint: 'Sıralama',
            items: const [
              DropdownMenuItem(value: DiscoverySort.distance, child: Text('Mesafeye göre')),
              DropdownMenuItem(value: DiscoverySort.rating, child: Text('Puana göre')),
              DropdownMenuItem(value: DiscoverySort.priceAsc, child: Text('Fiyat artan')),
              DropdownMenuItem(value: DiscoverySort.priceDesc, child: Text('Fiyat azalan')),
            ],
            onChanged: (v) => setState(() => sort = v!),
          ),
          const SizedBox(height: 20),

          FilledButton(
            onPressed: () => Navigator.pop(context, _value()),
            child: const Text('Filtreleri Uygula'),
          ),
        ],
      ),
    ),
  );
}
