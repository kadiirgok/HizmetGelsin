import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import 'admin_panel_screen.dart' show barberStatusLabel, barberStatusColor;

class AdminBarberDetailScreen extends StatefulWidget {
  const AdminBarberDetailScreen({super.key, required this.barberProfileId});
  final String barberProfileId;

  @override
  State<AdminBarberDetailScreen> createState() =>
      _AdminBarberDetailScreenState();
}

class _AdminBarberDetailScreenState extends State<AdminBarberDetailScreen> {
  Map<String, dynamic>? _detail;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/admin/barbers/${widget.barberProfileId}',
      );
      if (mounted) setState(() => _detail = data);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        ),
      );
  }

  Future<void> _openDocument(Map<String, dynamic> doc) async {
    setState(() => _busy = true);
    try {
      final bytes = await ApiClient.instance.getBytes(
        '/api/admin/barbers/${widget.barberProfileId}/documents/${doc['id']}',
      );
      final contentType = doc['contentType'] as String;

      if (contentType.startsWith('image/') && mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: InteractiveViewer(
              child: Image.memory(Uint8List.fromList(bytes)),
            ),
          ),
        );
      } else {
        // PDF: geçici dosyaya yaz, sistem görüntüleyiciyle aç
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${doc['id']}.pdf');
        await file.writeAsBytes(bytes);
        await launchUrl(Uri.file(file.path));
      }
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } catch (_) {
      _snack('Belge açılamadı.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      await ApiClient.instance.post(
        '/api/admin/barbers/${widget.barberProfileId}/approve',
      );
      _snack('İşletme onaylandı.');
      await _load();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Başvuruyu Reddet'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Ret gerekçesi (işletmeye iletilir)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reddet'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (controller.text.trim().isEmpty) {
      _snack('Ret gerekçesi zorunludur.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiClient.instance.post(
        '/api/admin/barbers/${widget.barberProfileId}/reject',
        data: {'reason': controller.text.trim()},
      );
      _snack('Başvuru reddedildi.');
      await _load();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(title: const Text('İşletme Başvurusu')),
      body: detail == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${detail['firstName'] ?? ''} ${detail['lastName'] ?? ''}'
                                    .trim(),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: barberStatusColor(
                                  detail['status'] as String,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                barberStatusLabel(detail['status'] as String),
                                style: TextStyle(
                                  color: barberStatusColor(
                                    detail['status'] as String,
                                  ),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        _InfoRow(
                          'İşletme',
                          detail['businessName'] as String? ?? '-',
                        ),
                        _InfoRow('Telefon', '+${detail['phone']}'),
                        _InfoRow('E-posta', detail['email'] as String? ?? '-'),
                        _InfoRow(
                          'T.C. Kimlik No',
                          detail['tcKimlikNo'] as String? ?? '-',
                        ),
                        _InfoRow(
                          'Hizmet Yarıçapı',
                          '${detail['serviceRadiusKm']} km',
                        ),
                        _InfoRow(
                          'Teklif Alıyor',
                          detail['acceptsOffers'] == true ? 'Evet' : 'Hayır',
                        ),
                        _InfoRow(
                          'Telefon Paylaşımı',
                          detail['sharePhone'] == true ? 'Açık' : 'Kapalı',
                        ),
                        if (detail['rejectionReason'] != null)
                          _InfoRow(
                            'Ret Gerekçesi',
                            detail['rejectionReason'] as String,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Belgeler',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                ...(detail['documents'] as List).map(
                  (doc) => Card(
                    child: ListTile(
                      leading: Icon(
                        (doc['contentType'] as String).startsWith('image/')
                            ? Icons.image
                            : Icons.picture_as_pdf,
                        color: AppTheme.primary,
                      ),
                      title: Text(
                        doc['type'] == 'UstalikBelgesi'
                            ? 'Yetkinlik Belgesi'
                            : 'İşletme Kaydı / Ruhsat',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      subtitle: Text(
                        doc['originalFileName'] as String,
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.open_in_new, size: 20),
                      onTap: _busy
                          ? null
                          : () => _openDocument(doc as Map<String, dynamic>),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hizmetler',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: (detail['services'] as List)
                        .map(
                          (s) => ListTile(
                            dense: true,
                            title: Text(s['name'] as String),
                            trailing: Text(
                              '${(s['price'] as num).toStringAsFixed(0)} TL',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 24),
                if (detail['status'] == 'PendingApproval') ...[
                  FilledButton.icon(
                    onPressed: _busy ? null : _approve,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Onayla'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _reject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                    ),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Reddet'),
                  ),
                ],
              ],
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
