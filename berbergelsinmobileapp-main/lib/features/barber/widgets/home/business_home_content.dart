part of '../../screens/barber_panel_screen.dart';

class BusinessHomeContent extends StatelessWidget {
  const BusinessHomeContent({
    super.key,
    this.scrollController,
    required this.user,
    required this.profile,
    required this.dashboard,
    required this.requests,
    required this.reviews,
    required this.isOnline,
    required this.busy,
    required this.loadError,
    required this.isInitialLoading,
    required this.isRefreshing,
    required this.profileError,
    required this.dashboardError,
    required this.requestsError,
    required this.reviewsError,
    required this.profileScore,
    required this.serviceCount,
    required this.photoCount,
    required this.onRefresh,
    required this.onToggleOnline,
    required this.onOpenProfile,
    required this.onOpenAppointments,
    required this.onOpenCustomers,
    required this.onOpenServices,
    required this.onOpenProfileSettings,
    required this.onShowDetail,
  });

  final ScrollController? scrollController;
  final AppUser? user;
  final Map<String, dynamic>? profile;
  final BusinessDashboard? dashboard;
  final List<ServiceRequestModel>? requests;
  final List<BarberReview> reviews;
  final bool isOnline;
  final bool busy;
  final String? loadError;
  final bool isInitialLoading;
  final bool isRefreshing;
  final String? profileError;
  final String? dashboardError;
  final String? requestsError;
  final String? reviewsError;
  final int profileScore;
  final int serviceCount;
  final int photoCount;
  final RefreshCallback onRefresh;
  final Future<void> Function(bool value) onToggleOnline;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenCustomers;
  final VoidCallback onOpenServices;
  final VoidCallback onOpenProfileSettings;
  final ValueChanged<ServiceRequestModel> onShowDetail;

  @override
  Widget build(BuildContext context) {
    final loadedRequests = requests ?? const <ServiceRequestModel>[];
    final completed = loadedRequests
        .where((r) => r.status == 'Completed')
        .toList();
    final pendingRequests = loadedRequests
        .where((r) => r.status == 'Pending')
        .toList();
    final activeRequests = loadedRequests.where((r) => r.isActive).toList();
    final safeDashboard = dashboard ?? BusinessDashboard();
    final allPrimarySourcesFailed =
        profile == null &&
        dashboard == null &&
        requests == null &&
        profileError != null &&
        dashboardError != null &&
        requestsError != null;
    final now = DateTime.now();
    final todayAppointments = loadedRequests.where((request) {
      return _isSameDay(request.requestedTime, now) &&
          request.status != 'Rejected' &&
          request.status != 'Cancelled';
    }).toList();
    final todayCompleted = completed.where((request) {
      return _isSameDay(request.completedAt ?? request.requestedTime, now);
    }).toList();
    final todayRevenue = todayCompleted.fold<double>(
      0,
      (sum, request) => sum + request.totalPrice,
    );
    final todayConfirmedJobCount = loadedRequests
        .where(
          (request) =>
              request.status == 'Accepted' ||
              request.status == 'OnTheWay' ||
              request.status == 'Started',
        )
        .where((request) => _isSameDay(request.requestedTime, now))
        .length;
    final actionRequests = [
      ...pendingRequests,
      ...activeRequests.where((r) => r.status != 'Pending'),
    ].take(3).toList();
    final rating = dashboard?.avgRating ?? user?.avgRating;
    final ratingCount = dashboard?.ratingCount ?? user?.ratingCount ?? 0;
    final businessName =
        (profile?['businessName'] as String?)?.trim().isNotEmpty == true
        ? (profile!['businessName'] as String).trim()
        : (user?.firstName?.trim().isNotEmpty == true
              ? 'Merhaba, ${user!.firstName!.trim()}'
              : 'İşletme paneli');
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth < 390 ? 16.0 : 20.0;
          return ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              90,
            ),
            children: [
              BusinessHomeHeader(onRefresh: onRefresh),
              if (isRefreshing && !isInitialLoading) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: AppTheme.fieldFill,
                    color: AppTheme.primary.withValues(alpha: 0.55),
                  ),
                ),
              ],
              if (loadError != null) ...[
                const SizedBox(height: 12),
                BusinessHomeErrorCard(
                  title: 'Bilgiler alınamadı',
                  message: 'Bağlantınızı kontrol edip tekrar deneyin.',
                  onRetry: onRefresh,
                ),
              ],
              const SizedBox(height: 18),
              if (isInitialLoading)
                const BusinessHomeInitialLoading()
              else if (allPrimarySourcesFailed)
                BusinessHomeErrorCard(
                  title: 'Ana sayfa yüklenemedi',
                  message: 'Bilgiler alınırken bir sorun oluştu.',
                  onRetry: onRefresh,
                )
              else ...[
                if (profileError != null && profile == null) ...[
                  BusinessHomeInlineError(
                    title: 'İşletme bilgileri yüklenemedi',
                    message: 'Bağlantınızı kontrol edip tekrar deneyin.',
                    onRetry: onRefresh,
                  ),
                  const SizedBox(height: 14),
                ],
                BusinessHomeHero(
                  businessName: businessName,
                  isOnline: isOnline,
                  busy: busy,
                  profileScore: profileScore,
                  serviceCount: serviceCount,
                  photoCount: photoCount,
                  rating: rating,
                  ratingCount: ratingCount,
                  onToggleOnline: onToggleOnline,
                  onOpenProfile: onOpenProfile,
                ),
                const SizedBox(height: 16),
                BusinessHomeSection(
                  title: 'Bugün',
                  child: requestsError != null && requests == null
                      ? BusinessHomeInlineError(
                          title: 'Randevular yüklenemedi',
                          message: 'Bağlantınızı kontrol edip tekrar deneyin.',
                          onRetry: onRefresh,
                        )
                      : BusinessHomeTodaySummary(
                          appointmentCount: todayAppointments.length,
                          completedCount: todayCompleted.length,
                          revenue: todayRevenue,
                        ),
                ),
                const SizedBox(height: 14),
                BusinessHomeMetricGrid(
                  metrics: [
                    BusinessHomeMetricData(
                      icon: Icons.inbox_rounded,
                      value: requestsError != null && requests == null
                          ? '—'
                          : '${pendingRequests.length}',
                      title: 'Gelen Talep',
                      helper: requestsError != null && requests == null
                          ? 'Randevular yüklenemedi'
                          : pendingRequests.isEmpty
                          ? 'Yeni talep yok'
                          : 'Yanıt bekliyor',
                      semanticLabel: requestsError != null && requests == null
                          ? 'Gelen talep: Randevular yüklenemedi'
                          : 'Gelen talep: ${pendingRequests.length}',
                    ),
                    BusinessHomeMetricData(
                      icon: Icons.timelapse_rounded,
                      value: requestsError != null && requests == null
                          ? '—'
                          : '${activeRequests.length}',
                      title: 'Aktif İşlem',
                      helper: requestsError != null && requests == null
                          ? 'İşlemler yüklenemedi'
                          : activeRequests.isEmpty
                          ? 'Aktif işlem yok'
                          : 'Devam ediyor',
                      semanticLabel: requestsError != null && requests == null
                          ? 'Aktif işlem: İşlemler yüklenemedi'
                          : 'Aktif işlem: ${activeRequests.length}',
                    ),
                    BusinessHomeMetricData(
                      icon: Icons.check_circle_outline_rounded,
                      value: requestsError != null && requests == null
                          ? '—'
                          : '${completed.length}',
                      title: 'Tamamlanan İş',
                      helper: requestsError != null && requests == null
                          ? 'Randevular yüklenemedi'
                          : 'Toplam tamamlanan',
                      semanticLabel: requestsError != null && requests == null
                          ? 'Tamamlanan iş: Randevular yüklenemedi'
                          : 'Tamamlanan iş: ${completed.length}',
                    ),
                    BusinessHomeMetricData(
                      icon: Icons.star_outline_rounded,
                      value: rating == null || rating == 0
                          ? '—'
                          : rating.toStringAsFixed(1),
                      title: 'Ortalama Puan',
                      helper: rating == null || rating == 0
                          ? 'Henüz puan yok'
                          : '$ratingCount yorum',
                      semanticLabel: rating == null || rating == 0
                          ? 'Ortalama puan: Henüz puan yok'
                          : 'Ortalama puan: ${rating.toStringAsFixed(1)}, $ratingCount yorum',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                BusinessHomeFocus(
                  pendingRequestCount: pendingRequests.length,
                  profileScore: profileScore,
                  serviceCount: serviceCount,
                  photoCount: photoCount,
                  isOnline: isOnline,
                  todayConfirmedJobCount: todayConfirmedJobCount,
                  onOpenAppointments: onOpenAppointments,
                  onOpenProfile: onOpenProfile,
                  onOpenProfileSettings: onOpenProfileSettings,
                  onOpenServices: onOpenServices,
                  onToggleOnline: onToggleOnline,
                ),
                const SizedBox(height: 18),
                if (requestsError != null && requests == null)
                  BusinessHomeSection(
                    title: 'Yaklaşan işler',
                    subtitle: 'Sıradaki randevularınız ve aktif işleriniz',
                    child: BusinessHomeInlineError(
                      title: 'Randevular yüklenemedi',
                      message: 'Bağlantınızı kontrol edip tekrar deneyin.',
                      onRetry: onRefresh,
                    ),
                  )
                else
                  BusinessHomeUpcoming(
                    requests: loadedRequests,
                    onOpenAppointments: onOpenAppointments,
                    onShowDetail: onShowDetail,
                  ),
                if (actionRequests.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  BusinessHomeSection(
                    title: 'Yaklaşan aksiyonlar',
                    trailing: TextButton(
                      onPressed: onOpenAppointments,
                      child: const Text('Tümünü Gör'),
                    ),
                  ),
                  ...actionRequests
                      .take(2)
                      .map(
                        (request) => BusinessHomeCompactRequestTile(
                          request: request,
                          onTap: () => onShowDetail(request),
                        ),
                      ),
                ],
                const SizedBox(height: 18),
                BusinessHomeSection(
                  title: 'Performans',
                  subtitle: 'İşletmenizin son dönem görünümü',
                  child: dashboardError != null && dashboard == null
                      ? BusinessHomeInlineError(
                          title: 'Performans verileri yüklenemedi',
                          message: 'Bağlantınızı kontrol edip tekrar deneyin.',
                          onRetry: onRefresh,
                        )
                      : BusinessHomePerformance(
                          weekRevenue: safeDashboard.weekRevenue,
                          totalRevenue: safeDashboard.totalRevenue,
                          averageResponseMinutes:
                              safeDashboard.averageResponseMinutes,
                          conversionRate: safeDashboard.conversionRate,
                          completedThisWeek: safeDashboard.completedThisWeek,
                          uniqueCustomerCount:
                              safeDashboard.uniqueCustomerCount,
                        ),
                ),
                const SizedBox(height: 18),
                BusinessHomeSection(
                  title: 'Hızlı işlemler',
                  subtitle: 'Sık kullandığınız işlemlere hızlıca ulaşın',
                  child: BusinessHomeQuickActions(
                    onOpenServices: onOpenServices,
                    onOpenProfile: onOpenProfile,
                    onOpenProfileSettings: onOpenProfileSettings,
                    onOpenAppointments: onOpenAppointments,
                    onOpenCustomers: onOpenCustomers,
                  ),
                ),
                const SizedBox(height: 18),
                BusinessHomeSection(
                  title: 'Son yorumlar',
                  subtitle: 'Müşterilerinizin son değerlendirmeleri',
                  child: reviewsError != null && reviews.isEmpty
                      ? BusinessHomeInlineError(
                          title: 'Yorumlar yüklenemedi',
                          message: 'Bağlantınızı kontrol edip tekrar deneyin.',
                          onRetry: onRefresh,
                        )
                      : Column(
                          children: [
                            if (reviewsError != null) ...[
                              BusinessHomeInlineError(
                                title: 'Yorumlar yenilenemedi',
                                message:
                                    'Mevcut yorumları göstermeye devam ediyoruz.',
                                onRetry: onRefresh,
                              ),
                              const SizedBox(height: 10),
                            ],
                            BusinessHomeReviews(reviews: reviews),
                          ],
                        ),
                ),
                const SizedBox(height: 24),
                BusinessHomeSection(
                  title: 'Günün ipucu',
                  child: BusinessHomeTip(
                    profileScore: profileScore,
                    serviceCount: serviceCount,
                    photoCount: photoCount,
                    rating: rating,
                    ratingCount: ratingCount,
                    isOnline: isOnline,
                    pendingRequestCount: pendingRequests.length,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ],
          );
        },
      ),
    );
  }

  bool _isSameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}