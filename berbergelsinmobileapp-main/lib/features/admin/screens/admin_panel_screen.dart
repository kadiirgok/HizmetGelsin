import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/signalr/signalr_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/bloc/auth_cubit.dart';

String barberStatusLabel(String status) => switch (status) {
  'Onboarding' => 'Kayıt Sürüyor',
  'PendingApproval' => 'Onay Bekliyor',
  'Approved' => 'Onaylı',
  'Rejected' => 'Reddedildi',
  _ => status,
};

Color barberStatusColor(String status) => switch (status) {
  'PendingApproval' => Colors.orange.shade700,
  'Approved' => Colors.green.shade700,
  'Rejected' => Colors.red.shade700,
  _ => Colors.grey.shade600,
};

/// Admin paneli: bekleyen işletme başvuruları, SignalR canlı yenileme.
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  List<Map<String, dynamic>>? _barbers;
  String _filter = 'PendingApproval';
  String? _loadError;
  final _unsubscribers = <void Function()>[];

  @override
  void initState() {
    super.initState();
    _load();
    for (final event in ['BarberPendingApproval', 'BarberListChanged']) {
      _unsubscribers.add(
        SignalRService.instance.on(event, (_) {
          if (event == 'BarberPendingApproval' && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Yeni işletme başvurusu geldi!'),
                backgroundColor: Colors.green.shade700,
              ),
            );
          }
          _load();
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final unsub in _unsubscribers) {
      unsub();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance.get<List<dynamic>>(
        '/api/admin/barbers',
        query: {'status': _filter},
      );
      final barbers = <Map<String, dynamic>>[];
      for (final item in data) {
        if (item is! Map<String, dynamic> ||
            item['barberProfileId'] is! String ||
            item['status'] is! String) {
          throw ApiException(
            'Başvuru listesi beklenmeyen bir biçimde geldi.',
            kind: ApiErrorKind.invalidResponse,
          );
        }
        barbers.add(item);
      }
      if (mounted) {
        setState(() {
          _barbers = barbers;
          _loadError = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Paneli'),
        actions: [
          IconButton(
            tooltip: 'Çıkış',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthCubit>().logout(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'PendingApproval',
                  label: Text('Bekleyen'),
                ),
                ButtonSegment(value: 'Approved', label: Text('Onaylı')),
                ButtonSegment(value: 'Rejected', label: Text('Reddedilen')),
              ],
              selected: {_filter},
              onSelectionChanged: (selection) {
                setState(() {
                  _filter = selection.first;
                  _barbers = null;
                });
                _load();
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loadError != null
                  ? ListView(
                      padding: const EdgeInsets.all(32),
                      children: [
                        const SizedBox(height: 80),
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 56,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(_loadError!, textAlign: TextAlign.center),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Tekrar Dene'),
                        ),
                      ],
                    )
                  : _barbers == null
                  ? const Center(child: CircularProgressIndicator())
                  : _barbers!.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Icon(
                          Icons.inbox,
                          size: 56,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            'Bu durumda başvuru yok.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _barbers!.length,
                      itemBuilder: (context, i) {
                        final b = _barbers![i];
                        final status = b['status'] as String;
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: AppTheme.primary,
                              child: Icon(
                                Icons.storefront_outlined,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              '${b['firstName'] ?? ''} ${b['lastName'] ?? ''}'
                                      .trim()
                                      .isEmpty
                                  ? (b['businessName'] as String? ?? 'İsimsiz')
                                  : '${b['firstName'] ?? ''} ${b['lastName'] ?? ''}'
                                        .trim(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${b['businessName'] ?? '-'} · +${b['phone']}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: barberStatusColor(
                                  status,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                barberStatusLabel(status),
                                style: TextStyle(
                                  color: barberStatusColor(status),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            onTap: () async {
                              await context.push(
                                '/admin/berber/${b['barberProfileId']}',
                              );
                              _load();
                            },
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
