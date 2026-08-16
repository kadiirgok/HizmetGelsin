part of '../../screens/barber_panel_screen.dart';

class BusinessHomeTip extends StatelessWidget {
  const BusinessHomeTip({
    super.key,
    required this.profileScore,
    required this.serviceCount,
    required this.photoCount,
    required this.rating,
    required this.ratingCount,
    required this.isOnline,
    required this.pendingRequestCount,
  });

  final int profileScore;
  final int serviceCount;
  final int photoCount;
  final double? rating;
  final int ratingCount;
  final bool isOnline;
  final int pendingRequestCount;

  @override
  Widget build(BuildContext context) {
    final tip = _selectTip();
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Günün ipucu. ${tip.title}. ${tip.description}',
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFECECEF)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.025),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F3F5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: Color(0xFF111111),
                  size: 21,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tip.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      height: 1.18,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tip.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.32,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _TipContent _selectTip() {
    if (profileScore < 70) {
      return const _TipContent(
        title: 'Profilini güçlendir',
        description:
            'Eksiksiz işletme bilgileri müşterilerin size daha hızlı güvenmesini sağlar.',
      );
    }
    if (serviceCount == 0) {
      return const _TipContent(
        title: 'Hizmetlerini ekle',
        description:
            'Net hizmet başlıkları ve açıklamalar müşterilerin doğru seçim yapmasını kolaylaştırır.',
      );
    }
    if (photoCount < 3) {
      return const _TipContent(
        title: 'Vitrinini zenginleştir',
        description:
            'Gerçek çalışma fotoğrafları işletmenizin güvenilirliğini artırır.',
      );
    }
    if (!isOnline) {
      return const _TipContent(
        title: 'Görünürlüğünü artır',
        description:
            'Çevrimiçi olduğunuzda yakınınızdaki müşteriler işletmenizi daha kolay keşfedebilir.',
      );
    }
    if (pendingRequestCount > 0) {
      return const _TipContent(
        title: 'Hızlı dönüş yap',
        description:
            'Taleplere zamanında yanıt vermek iş alma ihtimalinizi artırır.',
      );
    }
    if (rating == null || rating! <= 0 || ratingCount == 0) {
      return const _TipContent(
        title: 'İlk yorumlarını kazan',
        description:
            'Tamamlanan işlerden sonra müşterilerden değerlendirme istemeyi unutmayın.',
      );
    }
    return const _TipContent(
      title: 'Kaliteni görünür kıl',
      description:
          'Güncel hizmetler, iyi fotoğraflar ve hızlı yanıtlar güçlü bir işletme vitrini oluşturur.',
    );
  }
}

class _TipContent {
  const _TipContent({required this.title, required this.description});

  final String title;
  final String description;
}
