import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/customer_ui.dart';
import '../../../core/widgets/osm_attribution.dart';
import '../data/client_addresses_repo.dart';
import '../widgets/customer_address_semantics.dart';

class ClientAddressesScreen extends StatefulWidget {
  const ClientAddressesScreen({super.key, this.repository});
  final ClientAddressesRepository? repository;
  @override
  State<ClientAddressesScreen> createState() => _State();
}

class _State extends State<ClientAddressesScreen> {
  late final _repo = widget.repository ?? ClientAddressesRepo.instance;
  List<ClientAddress>? _items;
  String? _error;
  bool _offline = false;
  final _busy = <String>{};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await _repo.list();
      CustomerAddressSelectionStore.instance.resolve(v);
      if (mounted) {
        setState(() {
          _items = v;
          _error = null;
          _offline = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _offline =
              e.kind == ApiErrorKind.network || e.kind == ApiErrorKind.timeout;
          _error = clientAddressErrorMessage(mapClientAddressError(e));
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _offline = true;
          _error = 'Adreslere ulaşılamadı. Bağlantınızı kontrol edin.';
        });
      }
    }
  }

  Future<void> _run(String key, Future<void> Function() f) async {
    if (!_busy.add(key)) return;
    setState(() {});
    try {
      await f();
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        final m = mapClientAddressError(e);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(clientAddressErrorMessage(m))));
        if (m
            case ClientAddressError.conflict ||
                ClientAddressError.defaultConflict) {
          await _load();
        }
      }
    } finally {
      _busy.remove(key);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Adreslerim',
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('Adres Ekle'),
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: _error != null && (_items?.isEmpty ?? true)
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * .65,
                  child: ErrorState(
                    message: _error!,
                    offline: _offline,
                    onRetry: _load,
                  ),
                ),
              ],
            )
          : _items == null
          ? const CustomerListSkeleton(cardHeight: 190)
          : _items!.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * .65,
                  child: EmptyState(
                    title: 'Henüz kayıtlı adresiniz yok',
                    message:
                        'Hizmet adreslerinizi kaydederek taleplerinizi daha hızlı oluşturabilirsiniz.',
                    icon: Icons.location_on_outlined,
                    actionLabel: 'Adres Ekle',
                    onAction: () => _edit(),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              itemCount: _items!.length + (_error == null ? 0 : 1),
              itemBuilder: (_, i) {
                if (_error != null && i == 0) {
                  return InlineErrorNotice(
                    message: _error!,
                    offline: _offline,
                    onRetry: _load,
                  );
                }
                final itemIndex = i - (_error == null ? 0 : 1);
                return _card(_items![itemIndex]);
              },
            ),
    ),
  );
  Widget _card(ClientAddress a) {
    final locationVerified =
        a.latitude >= -90 &&
        a.latitude <= 90 &&
        a.longitude >= -180 &&
        a.longitude <= 180;
    final locked = _busy.contains(a.id);
    return Semantics(
      container: true,
      label:
          '${customerAddressSemanticsLabel(a, selected: false)}, ${locationVerified ? 'konum doğrulandı' : 'konum doğrulanamadı'}',
      child: Card(
        key: ValueKey('address-card-${a.id}'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: const Icon(
                      Icons.location_on_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (a.isDefault)
                          const Padding(
                            padding: EdgeInsets.only(top: AppSpacing.xxs),
                            child: StatusBadge(
                              label: 'Varsayılan adres',
                              tone: StatusTone.success,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                a.addressLine,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if ([
                a.neighborhood,
                a.district,
                a.province,
              ].whereType<String>().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  [
                    a.neighborhood,
                    a.district,
                    a.province,
                  ].whereType<String>().join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(
                    locationVerified
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                    size: 18,
                    color: locationVerified
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      locationVerified
                          ? 'Harita konumu doğrulandı'
                          : 'Harita konumu doğrulanamadı',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: locked ? null : () => _edit(a),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Düzenle'),
                  ),
                  if (!a.isDefault)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: locked
                          ? null
                          : () => _run(a.id, () => _repo.setDefault(a.id)),
                      icon: const Icon(Icons.home_outlined, size: 18),
                      label: const Text('Varsayılan Yap'),
                    ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: AppColors.error,
                    ),
                    onPressed: locked ? null : () => _remove(a),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Sil'),
                  ),
                ],
              ),
              if (locked)
                Semantics(
                  liveRegion: true,
                  label: 'Adres işlemi sürüyor',
                  child: const LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _remove(ClientAddress a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Adresi listeden kaldır'),
        content: Text(
          '${a.label} adresi kayıtlı adreslerinizden kaldırılsın mı? Geçmiş talepler etkilenmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(a.id, () => _repo.delete(a.id));
  }

  Future<void> _edit([ClientAddress? a]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ClientAddressFormScreen(initial: a, repository: _repo),
      ),
    );
    if (changed == true) await _load();
  }
}

class ClientAddressFormScreen extends StatefulWidget {
  const ClientAddressFormScreen({
    super.key,
    this.initial,
    required this.repository,
  });
  final ClientAddress? initial;
  final ClientAddressesRepository repository;
  @override
  State<ClientAddressFormScreen> createState() => _FormState();
}

class _FormState extends State<ClientAddressFormScreen> {
  late final Map<String, TextEditingController> c;
  late double lat, lng;
  bool def = false, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    lat = a?.latitude ?? 41.0082;
    lng = a?.longitude ?? 28.9784;
    def = a?.isDefault ?? false;
    c = {
      'label': TextEditingController(text: a?.label),
      'province': TextEditingController(text: a?.province),
      'district': TextEditingController(text: a?.district),
      'neighborhood': TextEditingController(text: a?.neighborhood),
      'street': TextEditingController(text: a?.street),
      'number': TextEditingController(text: a?.streetNumber),
      'postal': TextEditingController(text: a?.postalCode),
      'line': TextEditingController(text: a?.addressLine),
      'place': TextEditingController(text: a?.placeId),
    };
  }

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    if (c['label']!.text.trim().isEmpty || c['line']!.text.trim().isEmpty) {
      setState(() => error = 'Etiket ve açık adres zorunludur.');
      return;
    }
    setState(() => busy = true);
    final old = widget.initial;
    final value = ClientAddress(
      id: old?.id ?? '',
      label: c['label']!.text.trim(),
      placeId: c['place']!.text.trim().isEmpty ? null : c['place']!.text.trim(),
      formattedAddress: c['line']!.text.trim(),
      province: c['province']!.text.trim(),
      district: c['district']!.text.trim(),
      neighborhood: c['neighborhood']!.text.trim(),
      street: c['street']!.text.trim(),
      streetNumber: c['number']!.text.trim(),
      postalCode: c['postal']!.text.trim(),
      addressLine: c['line']!.text.trim(),
      latitude: lat,
      longitude: lng,
      isDefault: def,
      createdAt: old?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      version: old?.version ?? '',
    );
    try {
      if (old == null) {
        await widget.repository.create(value);
      } else {
        await widget.repository.update(value);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => error = clientAddressErrorMessage(mapClientAddressError(e)),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: widget.initial == null ? 'Yeni Adres' : 'Adresi Düzenle',
    body: ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 30,
      ),
      children: [
        field('label', 'Etiket *'),
        field('place', 'Adres ara / Place ID (opsiyonel)'),
        Row(
          children: [
            Expanded(child: field('province', 'İl')),
            const SizedBox(width: 8),
            Expanded(child: field('district', 'İlçe')),
          ],
        ),
        field('neighborhood', 'Mahalle'),
        Row(
          children: [
            Expanded(child: field('street', 'Cadde / Sokak')),
            const SizedBox(width: 8),
            SizedBox(width: 100, child: field('number', 'Bina No')),
          ],
        ),
        field('line', 'Açık Adres *', lines: 3),
        field('postal', 'Posta Kodu'),
        const Text('Harita konumu (dokunarak doğrulayın)'),
        SizedBox(
          height: 180,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(lat, lng),
              initialZoom: 14,
              onTap: (_, p) => setState(() {
                lat = p.latitude;
                lng = p.longitude;
              }),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.berbergelsin.berbergelsin',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(lat, lng),
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.location_pin,
                      size: 40,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const OsmAttribution(),
        SwitchListTile(
          value: def,
          onChanged: (v) => setState(() => def = v),
          title: const Text('Varsayılan adres yap'),
        ),
        if (error != null)
          Semantics(
            container: true,
            liveRegion: true,
            label: 'Manuel adres hatası: $error',
            child: ExcludeSemantics(
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Kaydediliyor…' : 'Kaydet'),
        ),
      ],
    ),
  );
  Widget field(String key, String label, {int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: c[key],
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
    ),
  );
}
