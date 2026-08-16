import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/config.dart';
import '../../../core/theme/app_theme.dart';
import '../data/favorites_repo.dart';
import '../../map/widgets/client_bottom_navigation.dart';
import '../../../core/widgets/customer_ui.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key, this.repository});
  final FavoritesRepository? repository;
  @override
  State<FavoritesScreen> createState() => _S();
}

class _S extends State<FavoritesScreen> {
  late final repo = widget.repository ?? FavoritesRepo.instance;
  final items = <FavoriteBusiness>[];
  final removing = <String>{};
  final _scrollController = ScrollController();
  int page = 0;
  bool loading = false, more = true;
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
    if (loading || (!reset && !more)) return;
    setState(() => loading = true);
    try {
      final p = await repo.list(page: reset ? 1 : page + 1);
      if (!mounted) return;
      setState(() {
        if (reset) items.clear();
        final ids = items.map((e) => e.id).toSet();
        items.addAll(p.items.where((e) => ids.add(e.id)));
        for (final item in p.items) {
          FavoriteStore.instance.sync(item.id, true);
        }
        page = p.page;
        more = p.hasNextPage;
        error = null;
        offline = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_scrollController.hasClients ||
            _scrollController.position.maxScrollExtent > 0 ||
            !more) {
          return;
        }
        load();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          offline =
              e is ApiException &&
              (e.kind == ApiErrorKind.network ||
                  e.kind == ApiErrorKind.timeout);
          error = e is ApiException
              ? favoriteErrorMessage(mapFavoriteError(e))
              : 'Favoriler yüklenemedi. Bağlantınızı kontrol edin.';
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> remove(FavoriteBusiness b) async {
    if (!removing.add(b.id)) return;
    final i = items.indexOf(b);
    setState(() => items.remove(b));
    FavoriteStore.instance.sync(b.id, false);
    try {
      await repo.remove(b.id);
    } catch (e) {
      FavoriteStore.instance.sync(b.id, true);
      if (mounted) {
        setState(() => items.insert(i.clamp(0, items.length), b));
        final message = e is ApiException
            ? favoriteErrorMessage(mapFavoriteError(e))
            : 'Favori kaldırılamadı. Değişiklik geri alındı.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        if (e is ApiException &&
            mapFavoriteError(e) == FavoriteError.conflict) {
          await load(reset: true);
        }
      }
    } finally {
      removing.remove(b.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext c) => AppScaffold(
    title: 'Favorilerim',
    bottomNavigationBar: const ClientBottomNavigation(currentIndex: 3),
    body: RefreshIndicator(
      onRefresh: () => load(reset: true),
      child: error != null && items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(c).height * .65,
                  child: ErrorState(
                    message: error!,
                    offline: offline,
                    onRetry: () => load(reset: true),
                  ),
                ),
              ],
            )
          : items.isEmpty && loading
          ? const CustomerListSkeleton(cardHeight: 220, withImage: true)
          : items.isEmpty && !loading
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(c).height * .65,
                  child: EmptyState(
                    title: 'Henüz favori işletmeniz yok',
                    message:
                        'Beğendiğiniz işletmeleri kaydedip burada kolayca bulabilirsiniz.',
                    icon: Icons.favorite_border,
                    actionLabel: 'İşletmeleri Keşfet',
                    onAction: () => c.go('/kesfet'),
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
                96,
              ),
              itemCount:
                  items.length +
                  (error == null ? 0 : 1) +
                  (loading && page > 0 ? 1 : 0),
              itemBuilder: (c, i) {
                if (error != null && i == 0) {
                  return InlineErrorNotice(
                    message: error!,
                    offline: offline,
                    onRetry: () => load(reset: true),
                  );
                }
                final offset = error == null ? 0 : 1;
                final itemIndex = i - offset;
                if (itemIndex >= items.length) {
                  return const _FavoritePaginationSkeleton();
                }
                final b = items[itemIndex];
                final name = b.name ?? 'İşletme';
                final category = [
                  b.category,
                  b.district,
                  b.city,
                ].whereType<String>().where((e) => e.isNotEmpty).join(' • ');
                return Semantics(
                  container: true,
                  label:
                      '$name, ${category.isEmpty ? 'kategori bilgisi yok' : category}, '
                      '${b.rating == null ? 'puan bilgisi yok' : '${b.rating!.toStringAsFixed(1)} puan, ${b.reviewCount} yorum'}, '
                      '${b.minimumPrice == null ? 'minimum fiyat bilgisi yok' : 'minimum ${b.minimumPrice!.toStringAsFixed(0)} Türk lirası'}, '
                      '${b.isOpenNow ? 'açık' : 'kapalı'}',
                  child: BusinessCard(
                    key: ValueKey('favorite-card-${b.id}'),
                    name: name,
                    category: category.isEmpty
                        ? 'Kategori belirtilmemiş'
                        : category,
                    coverUrl: b.coverImageUrl == null
                        ? null
                        : url(b.coverImageUrl!),
                    logoUrl: b.profileImageUrl == null
                        ? null
                        : url(b.profileImageUrl!),
                    rating: b.rating,
                    reviewCount: b.reviewCount,
                    minimumPrice: b.minimumPrice,
                    isOpen: b.isOpenNow,
                    favorite: true,
                    onFavorite: removing.contains(b.id)
                        ? null
                        : () => remove(b),
                    onTap: () => c.push('/isletme/${b.id}'),
                  ),
                );
              },
            ),
    ),
  );
  String url(String x) => x.startsWith('http') ? x : '${AppConfig.baseUrl}$x';
}

class _FavoritePaginationSkeleton extends StatelessWidget {
  const _FavoritePaginationSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Semantics(
      label: 'Daha fazla favori yükleniyor',
      child: const ExcludeSemantics(
        child: LoadingSkeleton(height: 96, radius: AppRadius.lg),
      ),
    ),
  );
}
