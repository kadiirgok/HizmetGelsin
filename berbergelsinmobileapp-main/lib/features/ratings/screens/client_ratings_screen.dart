import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/customer_ui.dart';
import '../../requests/widgets/rating_dialog.dart';
import '../data/client_ratings_repo.dart';

class ClientRatingsScreen extends StatefulWidget {
  const ClientRatingsScreen({super.key, this.repository});
  final ClientRatingsRepository? repository;

  @override
  State<ClientRatingsScreen> createState() => _ClientRatingsScreenState();
}

class _ClientRatingsScreenState extends State<ClientRatingsScreen> {
  late final ClientRatingsRepository repository =
      widget.repository ?? ClientRatingsRepo.instance;
  final items = <ClientRating>[];
  final busy = <String>{};
  final expanded = <String>{};
  final _scrollController = ScrollController();
  int page = 0;
  bool loading = false, hasMore = true;
  String? error;
  bool offline = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    load(reset: true);
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 280) load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    if (loading || (!reset && !hasMore)) return;
    setState(() => loading = true);
    try {
      final result = await repository.list(page: reset ? 1 : page + 1);
      if (!mounted) return;
      setState(() {
        if (reset) items.clear();
        final ids = items.map((e) => e.id).toSet();
        items.addAll(result.items.where((e) => ids.add(e.id)));
        page = result.page;
        hasMore = result.hasNextPage;
        error = null;
        offline = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_scrollController.hasClients ||
            _scrollController.position.maxScrollExtent > 0 ||
            !hasMore) {
          return;
        }
        load();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        offline =
            e is ApiException &&
            (e.kind == ApiErrorKind.network || e.kind == ApiErrorKind.timeout);
        error = e is ApiException
            ? ratingErrorMessage(mapRatingError(e))
            : e is RatingError
            ? ratingErrorMessage(e)
            : 'Yorumlar yüklenemedi. Bağlantınızı kontrol edin.';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit(ClientRating rating) async {
    final result = await showRatingDialog(
      context,
      title: 'Yorumu düzenle',
      initialScore: rating.rating,
      initialComment: rating.comment,
      maxLength: 600,
    );
    if (result == null || !busy.add(rating.id)) return;
    setState(() {});
    try {
      final updated = await repository.update(
        rating.id,
        score: result.score,
        comment: result.comment,
        version: rating.version,
      );
      if (mounted) {
        setState(
          () => items[items.indexWhere((e) => e.id == rating.id)] = updated,
        );
      }
    } on ApiException catch (e) {
      final mapped = mapRatingError(e);
      if (mapped == RatingError.conflict) await load(reset: true);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ratingErrorMessage(mapped))));
      }
    } finally {
      busy.remove(rating.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> remove(ClientRating rating) async {
    final yes =
        await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Yorumu kaldır'),
            content: const Text(
              'Yorumunuz profilinizden ve işletme değerlendirmelerinden kaldırılacak.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Kaldır'),
              ),
            ],
          ),
        ) ??
        false;
    if (!yes || !busy.add(rating.id)) return;
    final index = items.indexOf(rating);
    setState(() => items.remove(rating));
    try {
      await repository.delete(rating.id);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => items.insert(index, rating));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ratingErrorMessage(mapRatingError(e)))),
        );
        if (mapRatingError(e) == RatingError.conflict) {
          await load(reset: true);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => items.insert(index, rating));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yorum kaldırılamadı. Tekrar deneyin.')),
        );
      }
    } finally {
      busy.remove(rating.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Yorumlarım',
    body: RefreshIndicator(
      onRefresh: () => load(reset: true),
      child: error != null && items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * .65,
                  child: ErrorState(
                    message: error!,
                    offline: offline,
                    onRetry: () => load(reset: true),
                  ),
                ),
              ],
            )
          : items.isEmpty && loading
          ? const CustomerListSkeleton(cardHeight: 210)
          : items.isEmpty && !loading
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * .65,
                  child: const EmptyState(
                    title: 'Henüz yorum yapmadınız',
                    message:
                        'Tamamlanan hizmetlerin ardından değerlendirmeleriniz burada görünür.',
                    icon: Icons.rate_review_outlined,
                  ),
                ),
              ],
            )
          : ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              itemCount:
                  items.length +
                  (error == null ? 0 : 1) +
                  (loading && page > 0 ? 1 : 0),
              itemBuilder: (context, index) {
                if (error != null && index == 0) {
                  return InlineErrorNotice(
                    message: error!,
                    offline: offline,
                    onRetry: () => load(reset: true),
                  );
                }
                final offset = error == null ? 0 : 1;
                final itemIndex = index - offset;
                if (itemIndex >= items.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Semantics(
                      label: 'Daha fazla yorum yükleniyor',
                      child: const ExcludeSemantics(
                        child: LoadingSkeleton(
                          height: 96,
                          radius: AppRadius.lg,
                        ),
                      ),
                    ),
                  );
                }
                final rating = items[itemIndex];
                final locked = busy.contains(rating.id);
                final moderation = _moderationInfo(rating.moderationStatus);
                final comment = rating.comment?.trim() ?? '';
                final longComment = comment.length > 180;
                final isExpanded = expanded.contains(rating.id);
                return Semantics(
                  container: true,
                  label:
                      '${rating.businessName ?? 'İşletme'}, 5 üzerinden ${rating.rating} puan, ${moderation.$1}, oluşturulma tarihi ${_date(rating.createdAt)}${rating.updatedAt == null ? '' : ', güncellenme tarihi ${_date(rating.updatedAt!)}'}',
                  child: Card(
                    key: ValueKey('rating-card-${rating.id}'),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  rating.businessName ?? 'İşletme',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              StatusBadge(
                                label: moderation.$1,
                                tone: moderation.$2,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Semantics(
                            label: '5 üzerinden ${rating.rating} puan',
                            child: ExcludeSemantics(
                              child: StarRow(
                                rating: rating.rating.toDouble(),
                                size: 22,
                              ),
                            ),
                          ),
                          if (comment.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              comment,
                              maxLines: isExpanded ? null : 4,
                              overflow: isExpanded
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                            ),
                            if (longComment)
                              TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 44),
                                  padding: EdgeInsets.zero,
                                ),
                                onPressed: () => setState(() {
                                  isExpanded
                                      ? expanded.remove(rating.id)
                                      : expanded.add(rating.id);
                                }),
                                child: Text(
                                  isExpanded ? 'Daralt' : 'Devamını göster',
                                ),
                              ),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Oluşturuldu: ${_date(rating.createdAt)}${rating.updatedAt == null ? '' : '  •  Güncellendi: ${_date(rating.updatedAt!)}'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const Divider(height: AppSpacing.lg),
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                ),
                                onPressed: !rating.isEditable || locked
                                    ? null
                                    : () => edit(rating),
                                icon: const Icon(Icons.edit_outlined),
                                label: Text(
                                  rating.isEditable
                                      ? 'Düzenle'
                                      : rating.isVisible
                                      ? 'Düzenleme süresi doldu'
                                      : 'Düzenleme kullanılamıyor',
                                ),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                  foregroundColor: AppColors.error,
                                ),
                                onPressed: locked ? null : () => remove(rating),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Kaldır'),
                              ),
                            ],
                          ),
                          if (locked)
                            Semantics(
                              liveRegion: true,
                              label: 'Yorum işlemi sürüyor',
                              child: const LinearProgressIndicator(),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    ),
  );

  (String, StatusTone) _moderationInfo(String value) => switch (value) {
    'UnderReview' => ('İnceleniyor', StatusTone.warning),
    'Hidden' => ('Yayından kaldırıldı', StatusTone.error),
    _ => ('Yayında', StatusTone.success),
  };

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
}
