part of '../../screens/barber_panel_screen.dart';

class BusinessHomeReviews extends StatelessWidget {
  const BusinessHomeReviews({super.key, required this.reviews});

  final List<BarberReview> reviews;

  @override
  Widget build(BuildContext context) {
    final visibleReviews = [...reviews]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final items = visibleReviews.take(3).toList();
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFECECEF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: items.isEmpty
          ? const _BusinessReviewsEmpty()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  _BusinessReviewRow(review: items[index]),
                ],
              ],
            ),
    );
  }
}

class _BusinessReviewRow extends StatelessWidget {
  const _BusinessReviewRow({required this.review});

  final BarberReview review;

  @override
  Widget build(BuildContext context) {
    final customerName = _customerName(review);
    final rating = review.score.clamp(0, 5);
    final comment = review.comment?.trim().isNotEmpty == true
        ? review.comment!.trim()
        : 'Puan verildi, yorum yazılmadı.';

    return Semantics(
      label: 'Müşteri adı: $customerName. Puan: $rating. Yorum: $comment',
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BusinessReviewAvatar(name: review.clientName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF111111),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _dateLabel(review.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _ReviewRating(score: rating),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              comment,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF222222),
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _customerName(BarberReview review) =>
      review.clientName?.trim().isNotEmpty == true
      ? review.clientName!.trim()
      : 'Müşteri';

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Bugün';
    }
    return '${date.day} ${_monthShortLabel(date.month)} ${date.year}';
  }

  String _monthShortLabel(int month) => switch (month) {
    1 => 'Oca',
    2 => 'Şub',
    3 => 'Mar',
    4 => 'Nis',
    5 => 'May',
    6 => 'Haz',
    7 => 'Tem',
    8 => 'Ağu',
    9 => 'Eyl',
    10 => 'Eki',
    11 => 'Kas',
    12 => 'Ara',
    _ => '',
  };
}

class _BusinessReviewAvatar extends StatelessWidget {
  const _BusinessReviewAvatar({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    return ExcludeSemantics(
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F3F5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: initials == null
            ? const Icon(
                Icons.person_outline_rounded,
                color: Color(0xFF111111),
                size: 20,
              )
            : Text(
                initials,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF111111),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
      ),
    );
  }

  String? _initials(String? name) {
    final parts = name
        ?.trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts == null || parts.isEmpty) return null;
    return parts.take(2).map((part) => part.substring(0, 1)).join();
  }
}

class _ReviewRating extends StatelessWidget {
  const _ReviewRating({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$score',
          style: const TextStyle(
            color: Color(0xFF111111),
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 4),
        ExcludeSemantics(
          child: Icon(
            Icons.star_rounded,
            size: 16,
            color: const Color(0xFFB58A00).withValues(alpha: 0.78),
          ),
        ),
      ],
    );
  }
}

class _BusinessReviewsEmpty extends StatelessWidget {
  const _BusinessReviewsEmpty();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Henüz yorum yok. Tamamlanan işlerden sonra müşteri yorumları burada görünecek.',
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EmptyReviewIcon(),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Henüz yorum yok',
                    style: TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Tamamlanan işlerden sonra müşteri yorumları burada görünecek.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
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
}

class _EmptyReviewIcon extends StatelessWidget {
  const _EmptyReviewIcon();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Color(0xFFF3F3F5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(
          Icons.reviews_outlined,
          color: Color(0xFF111111),
          size: 21,
        ),
      ),
    );
  }
}
