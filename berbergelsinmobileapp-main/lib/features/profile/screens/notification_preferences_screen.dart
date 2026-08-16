import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/bloc/auth_cubit.dart';
import '../../../core/theme/app_theme.dart';

/// Kullanıcının hangi olaylarda push bildirimi alacağını seçtiği sayfa.
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final Map<String, bool> _prefs = {};
  static const _keys = [
    'new_request',
    'request_accepted',
    'request_rejected',
    'on_the_way',
    'started',
    'completed',
    'cancelled',
    'new_review',
  ];

  static const _labels = {
    'new_request': 'Yeni Talep Geldi',
    'request_accepted': 'Talep Kabul Edildi',
    'request_rejected': 'Talep Reddedildi',
    'on_the_way': 'Berber Yola Çıktı',
    'started': 'Hizmet Başladı',
    'completed': 'İşlem Tamamlandı',
    'cancelled': 'Talep İptal Edildi',
    'new_review': 'Yeni Değerlendirme',
  };

  static const _descriptions = {
    'new_request': 'Yeni bir hizmet talebi geldiğinde',
    'request_accepted': 'Talebiniz kabul edildiğinde',
    'request_rejected': 'Talebiniz reddedildiğinde',
    'on_the_way': 'Berber yola çıktığında',
    'started': 'Hizmet başladığında',
    'completed': 'İşlem tamamlandığında',
    'cancelled': 'Talep iptal edildiğinde',
    'new_review': 'Yeni bir değerlendirme aldığınızda',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs =
          await context.read<AuthCubit>().getNotificationPreferences();
      if (!mounted) return;
      setState(() {
        for (final key in _keys) {
          _prefs[key] = prefs[key] ?? true; // default: all enabled
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Tercihler yüklenemedi. Varsayılanlar gösteriliyor.';
      });
      for (final key in _keys) {
        _prefs[key] = true;
      }
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await context
          .read<AuthCubit>()
          .updateNotificationPreferences(Map.from(_prefs));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Bildirim tercihleri kaydedildi.'),
            backgroundColor: Colors.green,
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Kaydedilemedi. Lütfen tekrar deneyin.'),
            backgroundColor: AppColors.error,
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirim Tercihleri'),
        actions: [
          TextButton(
            onPressed: _busy || _loading ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Kaydet'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppColors.warning, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          color: AppColors.primary, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Hangi olaylarda push bildirimi almak istediğinizi seçin. '
                          'Değişiklikler kaydedildikten sonra geçerli olur.',
                          style: TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ...List.generate(_keys.length, (i) {
                  final key = _keys[i];
                  return Card(
                    child: SwitchListTile(
                      title: Text(
                        _labels[key] ?? key,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _descriptions[key] ?? '',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _prefs[key] ?? true,
                      onChanged:
                          _busy ? null : (v) => setState(() => _prefs[key] = v),
                      secondary: Icon(
                        Icons.notifications_outlined,
                        color: (_prefs[key] ?? true)
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
