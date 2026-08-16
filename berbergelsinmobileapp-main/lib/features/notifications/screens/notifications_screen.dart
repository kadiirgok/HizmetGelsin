import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/customer_ui.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../controllers/notification_store.dart';
import '../data/notifications_repo.dart';
import '../../../core/deep_link/app_deep_link.dart';
import '../../../core/deep_link/deep_link_coordinator.dart';
import '../../../core/deep_link/deep_link_parser.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.store,
    this.sessionUserId,
    this.isCustomerOverride,
  });
  final NotificationStore? store;
  final String? sessionUserId;
  final bool? isCustomerOverride;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationStore store =
      widget.store ?? NotificationStore.instance;
  final _scrollController = ScrollController();
  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 280) store.loadMore();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = widget.sessionUserId ?? context.read<AuthCubit>().state.user?.id;
    if (id != null) store.bindSession(id);
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    _scrollController.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scrollController.hasClients ||
          _scrollController.position.maxScrollExtent > 0 ||
          !store.hasMore) {
        return;
      }
      store.loadMore();
    });
  }

  Future<void> _open(AppNotification notification) async {
    final read = await store.read(notification);
    if (!read || !mounted) return;
    if (notification.route.trim().isEmpty) return;
    final opened = await context.read<DeepLinkCoordinator>().open(
      notification.route,
      source: DeepLinkSource.notification,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu bildirim bağlantısı açılamıyor.')),
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Bildirimlerim',
    actions: [
      Semantics(
        button: true,
        label: 'Tüm bildirimleri okundu olarak işaretle',
        child: TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed:
              store.unread == 0 ||
                  store.state == NotificationLoadState.markingAllRead
              ? null
              : store.readAll,
          child: const Text('Tümünü oku'),
        ),
      ),
    ],
    body: RefreshIndicator(onRefresh: store.refresh, child: _body()),
  );

  Widget _body() {
    if (store.items.isEmpty &&
        (store.state == NotificationLoadState.loading ||
            store.state == NotificationLoadState.initial)) {
      return const CustomerListSkeleton(cardHeight: 132, withImage: true);
    }
    if (store.items.isEmpty &&
        (store.state == NotificationLoadState.networkError ||
            store.state == NotificationLoadState.rateLimited)) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: ErrorState(
              message: store.error ?? 'Bildirimler yüklenemedi.',
              offline: store.offline,
              onRetry: store.refresh,
            ),
          ),
        ],
      );
    }
    if (store.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: const EmptyState(
              title: 'Yeni bildiriminiz yok',
              message:
                  'Talep, teklif ve randevu güncellemeleri burada görünür.',
              icon: Icons.notifications_none,
            ),
          ),
        ],
      );
    }
    final hasInlineError =
        store.state == NotificationLoadState.networkError ||
        store.state == NotificationLoadState.rateLimited;
    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      itemCount:
          store.items.length +
          (hasInlineError ? 1 : 0) +
          (store.state == NotificationLoadState.loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasInlineError && index == 0) {
          return InlineErrorNotice(
            message: store.error ?? 'Bildirimler yenilenemedi.',
            offline: store.offline,
            onRetry: store.refresh,
          );
        }
        final offset = hasInlineError ? 1 : 0;
        final itemIndex = index - offset;
        if (itemIndex >= store.items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Semantics(
              label: 'Daha fazla bildirim yükleniyor',
              child: const ExcludeSemantics(
                child: LoadingSkeleton(height: 88, radius: AppRadius.lg),
              ),
            ),
          );
        }
        final notification = store.items[itemIndex];
        final busy = store.busyIds.contains(notification.id);
        final typeLabel = notificationTypeLabel(notification.type);
        return Semantics(
          container: true,
          label:
              '$typeLabel. ${notification.title}. ${notification.body}. ${_time(notification.createdAt)}. ${notification.isRead ? 'Okundu' : 'Okunmadı'}${notification.route.trim().isEmpty ? '' : '. Açmak için dokunun'}',
          child: Card(
            key: Key('notification-${notification.id}'),
            color: notification.isRead
                ? AppColors.surface
                : AppColors.primaryContainer.withValues(alpha: .55),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: busy ? null : () => _open(notification),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: notification.isRead
                                ? AppColors.surfaceVariant
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Icon(
                            notificationIcon(notification.type),
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: notification.isRead
                                      ? FontWeight.w600
                                      : FontWeight.w800,
                                ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        StatusBadge(
                          label: notification.isRead ? 'Okundu' : 'Okunmadı',
                          tone: notification.isRead
                              ? StatusTone.neutral
                              : StatusTone.success,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      notification.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xxs,
                      children: [
                        Text(
                          typeLabel,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        Text(
                          _time(notification.createdAt),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    if (busy)
                      Semantics(
                        liveRegion: true,
                        label: 'Bildirim işlemi sürüyor',
                        child: const LinearProgressIndicator(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _time(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

String notificationTypeLabel(String type) => switch (type) {
  'NewRequest' => 'Yeni talep bildirimi',
  'NewOffer' => 'Yeni teklif bildirimi',
  'OfferUpdated' => 'Teklif güncellemesi',
  'RequestUpdated' => 'Talep güncellemesi',
  'RequestTimelineUpdated' => 'Talep zaman çizelgesi güncellemesi',
  'RatingReceived' => 'Değerlendirme bildirimi',
  _ => 'Genel bildirim',
};

IconData notificationIcon(String type) => switch (type) {
  'NewRequest' => Icons.assignment_outlined,
  'NewOffer' => Icons.local_offer_outlined,
  'OfferUpdated' => Icons.price_change_outlined,
  'RequestUpdated' => Icons.update,
  'RequestTimelineUpdated' => Icons.timeline,
  'RatingReceived' => Icons.star_outline,
  _ => Icons.notifications_outlined,
};

/// Eski çağrı noktaları için uyumluluk katmanı; karar yine ortak parser'dan geçer.
String? safeNotificationTarget(String route, {required bool isCustomer}) {
  final link = DeepLinkParser(
    trustedHosts: const [],
  ).parse(route, source: DeepLinkSource.notification);
  return switch (link.type) {
    AppDeepLinkType.businessDetail =>
      isCustomer ? '/isletme/${link.entityId}' : null,
    AppDeepLinkType.requestDetail ||
    AppDeepLinkType.appointmentDetail => '/talep/${link.entityId}',
    AppDeepLinkType.offerDetail => isCustomer ? '/taleplerim' : '/berber',
    AppDeepLinkType.notifications => '/bildirimler',
    AppDeepLinkType.favorites => isCustomer ? '/favorilerim' : null,
    AppDeepLinkType.ratings => isCustomer ? '/yorumlarim' : null,
    AppDeepLinkType.addresses => isCustomer ? '/adreslerim' : null,
    AppDeepLinkType.unknown => null,
  };
}
