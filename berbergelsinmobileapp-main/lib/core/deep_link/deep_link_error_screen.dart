import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DeepLinkErrorScreen extends StatelessWidget {
  const DeepLinkErrorScreen({super.key, required this.reason, this.onRetry});
  final String reason;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final data = switch (reason) {
      'unauthorized' => (
        Icons.lock_outline,
        'Yetkisiz erişim',
        'Bu içeriği görüntülemek için hesabınızın yetkisi bulunmuyor.',
      ),
      'notFound' => (
        Icons.search_off,
        'İçerik bulunamadı',
        'İçerik silinmiş, pasif veya süresi dolmuş olabilir.',
      ),
      'network' => (
        Icons.cloud_off,
        'Bağlantı kurulamadı',
        'Ağ bağlantınızı kontrol edip yeniden deneyin.',
      ),
      'invalid' => (
        Icons.link_off,
        'Geçersiz bağlantı',
        'Bu bağlantı güvenli veya geçerli değil.',
      ),
      _ => (
        Icons.link_off,
        'Bağlantı desteklenmiyor',
        'Bu bağlantı uygulamada açılamıyor.',
      ),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Bağlantı')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(data.$1, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    data.$2,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(data.$3, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  if (reason == 'network' && onRetry != null)
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('Tekrar Dene'),
                    )
                  else
                    FilledButton(
                      onPressed: () => context.go('/'),
                      child: const Text('Ana sayfaya dön'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
