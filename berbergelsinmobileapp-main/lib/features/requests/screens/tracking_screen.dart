import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/session/customer_session_events.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/osm_attribution.dart';
import '../data/requests_repo.dart';

/// Yemeksepeti tarzı canlı işletme takibi: hizmet veren pini haritada hareket eder,
/// mesafe + tahmini varış anlık akar; hizmet veren 200 m'ye girince randevu
/// otomatik başlar ve ekran durumu günceller.
class TrackingScreen extends StatefulWidget {
  const TrackingScreen({
    super.key,
    required this.request,
    this.realtimeClient,
    this.sessionSource,
  });
  final ServiceRequestModel request;
  final CustomerRealtimeClient? realtimeClient;
  final CustomerSessionVersionSource? sessionSource;

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final _mapController = MapController();

  LatLng? _barberLocation;
  double? _distanceMeters;
  int? _etaMinutes;
  late String _status;
  late final CustomerSessionEventSubscriptions _sessionEvents;

  LatLng get _clientLocation =>
      LatLng(widget.request.lat!, widget.request.lng!);

  @override
  void initState() {
    super.initState();
    _sessionEvents = CustomerSessionEventSubscriptions(
      session: widget.sessionSource ?? CustomerSessionScope.instance,
      realtime: widget.realtimeClient ?? SignalRCustomerRealtimeClient.instance,
    );
    _status = widget.request.status;
    if (widget.request.barberLat != null && widget.request.barberLng != null) {
      _barberLocation = LatLng(
        widget.request.barberLat!,
        widget.request.barberLng!,
      );
    }

    _sessionEvents.on('TrackingUpdate', (args) {
      final payload = args?.firstOrNull;
      if (payload is! Map || payload['requestId'] != widget.request.id) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _barberLocation = LatLng(
          (payload['lat'] as num).toDouble(),
          (payload['lng'] as num).toDouble(),
        );
        _distanceMeters = (payload['distanceMeters'] as num?)?.toDouble();
        _etaMinutes = (payload['etaMinutes'] as num?)?.toInt();
        _status = payload['status'] as String? ?? _status;
      });
    });

    _sessionEvents.on('RequestUpdated', (args) {
      final payload = args?.firstOrNull;
      if (payload is! Map || payload['requestId'] != widget.request.id) {
        return;
      }
      if (!mounted) return;
      setState(() => _status = payload['status'] as String? ?? _status);
    });
  }

  @override
  void dispose() {
    _sessionEvents.dispose();
    super.dispose();
  }

  String get _bannerText {
    if (_status == 'Started') return 'Hizmet veren geldi! Randevunuz başladı.';
    if (_etaMinutes != null && _distanceMeters != null) {
      final distance = _distanceMeters! >= 1000
          ? '${(_distanceMeters! / 1000).toStringAsFixed(1)} km'
          : '${_distanceMeters!.round()} m';
      return 'Hizmet veren yolda — tahmini varış $_etaMinutes dk ($distance)';
    }
    return 'Hizmet veren yola çıktı, konum bekleniyor...';
  }

  @override
  Widget build(BuildContext context) {
    final started = _status == 'Started';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.request.barberBusinessName ?? 'Canlı Takip'),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: started ? const Color(0xFFE8F7EC) : AppTheme.fieldFill,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  started ? Icons.check_circle : Icons.directions_car,
                  color: started ? Colors.green.shade700 : AppTheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _bannerText,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _barberLocation ?? _clientLocation,
                initialZoom: 14.5,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.berbergelsin.berbergelsin',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _clientLocation,
                      width: 42,
                      height: 42,
                      child: const Column(
                        children: [
                          Icon(Icons.home, color: AppTheme.primary, size: 30),
                          Text(
                            'Siz',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_barberLocation != null)
                      Marker(
                        point: _barberLocation!,
                        width: 46,
                        height: 46,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: const [
                              BoxShadow(blurRadius: 8, color: Colors.black38),
                            ],
                          ),
                          child: const Icon(
                            Icons.storefront_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                  ],
                ),
                const OsmAttribution(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
