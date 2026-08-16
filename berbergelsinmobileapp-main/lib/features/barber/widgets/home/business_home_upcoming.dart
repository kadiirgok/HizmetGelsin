part of '../../screens/barber_panel_screen.dart';

class BusinessHomeUpcoming extends StatelessWidget {
  const BusinessHomeUpcoming({
    super.key,
    required this.requests,
    required this.onOpenAppointments,
    required this.onShowDetail,
  });

  final List<ServiceRequestModel> requests;
  final VoidCallback onOpenAppointments;
  final ValueChanged<ServiceRequestModel> onShowDetail;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nextCandidates = requests
        .where(
          (request) =>
              request.status == 'Accepted' ||
              request.status == 'OnTheWay' ||
              request.status == 'Started',
        )
        .toList();
    nextCandidates.sort((a, b) {
      final priority = _statusPriority(a).compareTo(_statusPriority(b));
      return priority != 0
          ? priority
          : a.requestedTime.compareTo(b.requestedTime);
    });
    final upcomingAllJobs = nextCandidates
        .where(
          (request) => !request.requestedTime.isBefore(
            DateTime(now.year, now.month, now.day),
          ),
        )
        .toList();
    final upcomingJobs = upcomingAllJobs.take(3).toList();
    final todayConfirmedJobs = nextCandidates
        .where((request) => _isSameDay(request.requestedTime, now))
        .toList();

    return _UpcomingJobsSection(
      requests: upcomingJobs,
      totalCount: upcomingAllJobs.length,
      todayCount: todayConfirmedJobs.length,
      onOpenAll: onOpenAppointments,
      onTapRequest: onShowDetail,
    );
  }

  bool _isSameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  int _statusPriority(ServiceRequestModel request) => switch (request.status) {
    'Started' => 0,
    'OnTheWay' => 1,
    _ => 2,
  };
}

class _UpcomingJobsSection extends StatelessWidget {
  const _UpcomingJobsSection({
    required this.requests,
    required this.totalCount,
    required this.todayCount,
    required this.onOpenAll,
    required this.onTapRequest,
  });

  final List<ServiceRequestModel> requests;
  final int totalCount;
  final int todayCount;
  final VoidCallback onOpenAll;
  final ValueChanged<ServiceRequestModel> onTapRequest;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final nextRequest = requests.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BusinessHomeSection(
          title: 'Yaklaşan işler',
          subtitle: 'Sıradaki randevularınız ve aktif işleriniz',
          trailing: totalCount > 3
              ? TextButton(
                  onPressed: onOpenAll,
                  child: const Text('Tümünü Gör'),
                )
              : null,
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          child: Container(
            key: ValueKey(requests.map((request) => request.id).join('|')),
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
            child: requests.isEmpty
                ? _UpcomingEmpty(onOpenAll: onOpenAll)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (todayCount > 0 && nextRequest != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 15, 16, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Bugün $todayCount işiniz var',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF111111),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Sıradaki ${_businessHomeTimeLabel(nextRequest.requestedTime)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      for (var index = 0; index < requests.length; index++) ...[
                        if (index > 0)
                          Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: Colors.black.withValues(alpha: 0.06),
                          ),
                        _UpcomingJobRow(
                          request: requests[index],
                          onTap: () => onTapRequest(requests[index]),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _UpcomingEmpty extends StatelessWidget {
  const _UpcomingEmpty({required this.onOpenAll});

  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Yaklaşan işiniz yok. Onaylanan yeni işler burada görünecek.',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F3F5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.event_available_outlined,
                color: Color(0xFF111111),
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Yaklaşan işiniz yok',
                    style: TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Onaylanan yeni işler burada görünecek.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onOpenAll,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Randevuları Gör'),
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
