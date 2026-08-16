part of '../../screens/barber_panel_screen.dart';

class BusinessHomeInitialLoading extends StatelessWidget {
  const BusinessHomeInitialLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'İşletme ana sayfası yükleniyor',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HomeSkeletonBlock(height: 178, radius: 28),
          const SizedBox(height: 14),
          Row(
            children: const [
              Expanded(child: _HomeSkeletonBlock(height: 104, radius: 22)),
              SizedBox(width: 10),
              Expanded(child: _HomeSkeletonBlock(height: 104, radius: 22)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              Expanded(child: _HomeSkeletonBlock(height: 104, radius: 22)),
              SizedBox(width: 10),
              Expanded(child: _HomeSkeletonBlock(height: 104, radius: 22)),
            ],
          ),
          const SizedBox(height: 16),
          const _HomeSkeletonBlock(height: 92, radius: 24),
          const SizedBox(height: 12),
          const _HomeSkeletonBlock(height: 128, radius: 24),
        ],
      ),
    );
  }
}

class BusinessHomeErrorCard extends StatelessWidget {
  const BusinessHomeErrorCard({
    super.key,
    this.title = 'Bilgiler alınamadı',
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final RefreshCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title. Tekrar dene.',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFECECEF)),
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
                  Icons.error_outline_rounded,
                  color: Color(0xFF111111),
                  size: 21,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('Tekrar Dene'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BusinessHomeInlineError extends StatelessWidget {
  const BusinessHomeInlineError({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final RefreshCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title. Tekrar dene.',
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F8),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFECECEF)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(
              child: Icon(
                Icons.info_outline_rounded,
                color: Color(0xFF111111),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('Dene'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeSkeletonBlock extends StatelessWidget {
  const _HomeSkeletonBlock({required this.height, required this.radius});

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: AppTheme.fieldFill.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}
