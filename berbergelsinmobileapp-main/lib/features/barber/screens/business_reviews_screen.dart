import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/business_reviews.dart';
import '../data/business_reviews_repository.dart';

class BusinessReviewsScreen extends StatefulWidget {
  const BusinessReviewsScreen({super.key, this.repository});

  final BusinessReviewsRepository? repository;

  @override
  State<BusinessReviewsScreen> createState() => _BusinessReviewsScreenState();
}

class _BusinessReviewsScreenState extends State<BusinessReviewsScreen> {
  static const _pageSize = 20;
  late final BusinessReviewsRepository _repository;
  final _scrollController = ScrollController();
  final _reviews = <BusinessReview>[];
  BusinessReviewsSummary _summary = BusinessReviewsSummary.empty;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  String? _loadMoreError;
  int _page = 0;
  int? _ratingFilter;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ApiBusinessReviewsRepository();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 320) _loadMore();
  }

  Future<void> _loadFirstPage({bool preserveOnError = false}) async {
    if (!preserveOnError) {
      setState(() {
        _loading = true;
        _error = null;
        _loadMoreError = null;
      });
    }
    try {
      final result = await _repository.fetch(
        page: 1,
        pageSize: _pageSize,
        rating: _ratingFilter,
      );
      if (!mounted) return;
      setState(() {
        _reviews
          ..clear()
          ..addAll(mergeBusinessReviewsByCustomer(result.items));
        _summary = result.summary;
        _page = 1;
        _hasMore = result.page < result.totalPages;
        _error = null;
        _loadMoreError = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (preserveOnError && _reviews.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Yorumlar yenilenemedi.')));
      } else {
        setState(() {
          _error = 'Yorumlar yüklenemedi';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final nextPage = _page + 1;
      final result = await _repository.fetch(
        page: nextPage,
        pageSize: _pageSize,
        rating: _ratingFilter,
      );
      if (!mounted) return;
      final knownIds = _reviews.map((review) => review.id).toSet();
      setState(() {
        _reviews.addAll(
          result.items.where((review) => knownIds.add(review.id)),
        );
        _page = nextPage;
        _hasMore = result.page < result.totalPages;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadMoreError = 'Daha fazla yorum yüklenemedi';
      });
    }
  }

  List<BusinessReview> _unique(List<BusinessReview> items) {
    final ids = <String>{};
    return items.where((item) => ids.add(item.id)).toList();
  }

  void _selectFilter(int? rating) {
    if (_ratingFilter == rating) return;
    setState(() => _ratingFilter = rating);
    _loadFirstPage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      appBar: AppBar(title: const Text('Tüm Yorumlar')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading && _reviews.isEmpty) return const _ReviewsLoading();
    if (_error != null && _reviews.isEmpty) {
      return _ReviewsError(onRetry: _loadFirstPage);
    }
    return RefreshIndicator(
      onRefresh: () => _loadFirstPage(preserveOnError: true),
      child: CustomScrollView(
        key: const PageStorageKey('business-reviews-scroll'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: ReviewsSummaryCard(summary: _summary),
            ),
          ),
          SliverToBoxAdapter(
            child: RatingFilterBar(
              selectedRating: _ratingFilter,
              onSelected: _selectFilter,
            ),
          ),
          if (_reviews.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _ratingFilter == null
                  ? const _ReviewsEmpty()
                  : const _FilterEmpty(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList.separated(
                itemCount: _reviews.length,
                itemBuilder: (context, index) =>
                    ReviewCard(review: _reviews[index]),
                separatorBuilder: (_, _) => const SizedBox(height: 10),
              ),
            ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (_loadMoreError != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: TextButton.icon(
                  onPressed: _loadMore,
                  icon: const Icon(Icons.refresh),
                  label: Text(_loadMoreError!),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ReviewsSummaryCard extends StatelessWidget {
  const ReviewsSummaryCard({super.key, required this.summary});
  final BusinessReviewsSummary summary;

  @override
  Widget build(BuildContext context) {
    final maxCount = summary.ratingDistribution.values.fold<int>(
      0,
      (max, count) => count > max ? count : max,
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 340;
            final score = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  summary.averageRating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primary,
                  ),
                ),
                ReviewStars(rating: summary.averageRating),
                const SizedBox(height: 4),
                Text(
                  '${summary.totalCount} yorum',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            );
            final distribution = Column(
              children: [
                for (var rating = 5; rating >= 1; rating--)
                  _DistributionRow(
                    rating: rating,
                    count: summary.ratingDistribution[rating] ?? 0,
                    maxCount: maxCount,
                  ),
              ],
            );
            return compact
                ? Column(
                    children: [score, const SizedBox(height: 16), distribution],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(width: 112, child: score),
                      const SizedBox(width: 16),
                      Expanded(child: distribution),
                    ],
                  );
          },
        ),
      ),
    );
  }
}

class _DistributionRow extends StatelessWidget {
  const _DistributionRow({
    required this.rating,
    required this.count,
    required this.maxCount,
  });
  final int rating;
  final int count;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final value = maxCount == 0 ? 0.0 : count / maxCount;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 14, child: Text('$rating')),
          const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF6B51E)),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 7,
                backgroundColor: const Color(0xFFE8E8EA),
                color: const Color(0xFFF6B51E),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(width: 28, child: Text('$count', textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class RatingFilterBar extends StatelessWidget {
  const RatingFilterBar({
    super.key,
    required this.selectedRating,
    required this.onSelected,
  });
  final int? selectedRating;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Tümü'),
            selected: selectedRating == null,
            onSelected: (_) => onSelected(null),
          ),
          for (var rating = 5; rating >= 1; rating--) ...[
            const SizedBox(width: 8),
            ChoiceChip(
              avatar: const Icon(Icons.star_rounded, size: 16),
              label: Text('$rating'),
              selected: selectedRating == rating,
              onSelected: (_) => onSelected(rating),
            ),
          ],
        ],
      ),
    );
  }
}

class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.review});
  final BusinessReview review;

  @override
  Widget build(BuildContext context) {
    final name = review.customerDisplayName.trim().isEmpty
        ? 'Müşteri'
        : review.customerDisplayName.trim();
    final initial = name.characters.first.toUpperCase();
    final comment = review.comment?.trim();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  foregroundColor: AppTheme.primary,
                  child: Text(initial),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 8,
                        runSpacing: 3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (review.rating > 0)
                            ReviewStars(
                              rating: review.rating.toDouble(),
                              size: 17,
                            ),
                          Text(
                            formatBusinessReviewDate(review.createdAt),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (review.serviceName?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                review.serviceName!.trim(),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (comment?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(comment!, style: const TextStyle(height: 1.45)),
            ],
          ],
        ),
      ),
    );
  }
}

class ReviewStars extends StatelessWidget {
  const ReviewStars({super.key, required this.rating, this.size = 18});
  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final safeRating = rating.isFinite ? rating.clamp(0, 5) : 0.0;
    return Semantics(
      label: '${safeRating.toStringAsFixed(1)} üzerinden 5 yıldız',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 1; index <= 5; index++)
              Icon(
                safeRating >= index
                    ? Icons.star_rounded
                    : safeRating >= index - 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_border_rounded,
                size: size,
                color: const Color(0xFFF6B51E),
              ),
          ],
        ),
      ),
    );
  }
}

String formatBusinessReviewDate(DateTime value) {
  const months = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];
  final local = value.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

class _ReviewsLoading extends StatelessWidget {
  const _ReviewsLoading();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Container(
        height: 180,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < 3; i++) ...[
        Container(
          height: 116,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        const SizedBox(height: 10),
      ],
    ],
  );
}

class _ReviewsEmpty extends StatelessWidget {
  const _ReviewsEmpty();
  @override
  Widget build(BuildContext context) => const _CenteredState(
    icon: Icons.chat_bubble_outline,
    title: 'Henüz yorum yok',
    message: 'Tamamlanan işlemlerden sonra müşteri yorumları burada görünecek.',
  );
}

class _FilterEmpty extends StatelessWidget {
  const _FilterEmpty();
  @override
  Widget build(BuildContext context) => const _CenteredState(
    icon: Icons.filter_alt_off_outlined,
    title: 'Bu puanda yorum yok',
    message: 'Başka bir puan filtresi seçebilirsiniz.',
  );
}

class _ReviewsError extends StatelessWidget {
  const _ReviewsError({required this.onRetry});
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => _CenteredState(
    icon: Icons.error_outline,
    title: 'Yorumlar yüklenemedi',
    message: 'Bağlantınızı kontrol edip tekrar deneyin.',
    action: FilledButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('Tekrar Dene'),
    ),
  );
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}
