import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../requests/screens/my_requests_screen.dart' show formatDateTime;
import '../../../requests/widgets/rating_dialog.dart';
import '../../data/barbers_repo.dart';

class BarberReviewsSection extends StatelessWidget {
  const BarberReviewsSection({super.key, required this.reviews});

  final List<BarberReview> reviews;

  @override
  Widget build(BuildContext context) {
    final visibleReviews = reviews.take(2).toList(growable: false);
    return Column(
      key: const ValueKey('barber-reviews-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: const Text(
            'Değerlendirmeler',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 8),
        if (visibleReviews.isEmpty)
          Semantics(
            label: 'Henüz yorum yok',
            child: ExcludeSemantics(
              child: Container(
                key: const ValueKey('barber-reviews-empty'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.fieldFill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.rate_review_outlined,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Henüz yorum yok',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          for (var index = 0; index < visibleReviews.length; index++)
            _ReviewCard(review: visibleReviews[index], index: index),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review, required this.index});

  final BarberReview review;
  final int index;

  @override
  Widget build(BuildContext context) {
    final score = review.score.clamp(0, 5);
    final name = review.clientName?.trim().isNotEmpty == true
        ? review.clientName!.trim()
        : 'Müşteri';
    final date = formatDateTime(review.createdAt);
    final comment = review.comment?.trim();
    return Semantics(
      label: [
        '$name, 5 üzerinden $score yıldız',
        date,
        if (comment?.isNotEmpty == true) comment!,
      ].join(', '),
      child: ExcludeSemantics(
        child: Container(
          key: ValueKey('barber-review-$index'),
          margin: EdgeInsets.only(bottom: index == 1 ? 0 : 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.fieldFill,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: StarRow(rating: score.toDouble(), size: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      date,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              if (comment?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(
                  comment!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, height: 1.35),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
