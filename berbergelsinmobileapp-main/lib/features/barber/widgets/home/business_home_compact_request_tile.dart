part of '../../screens/barber_panel_screen.dart';

class BusinessHomeCompactRequestTile extends StatelessWidget {
  const BusinessHomeCompactRequestTile({
    super.key,
    required this.request,
    required this.onTap,
  });

  final ServiceRequestModel request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = requestStatusColor(request.status);
    final clientName = request.clientName?.trim().isNotEmpty == true
        ? request.clientName!.trim()
        : 'Müşteri';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: ExcludeSemantics(
          child: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(Icons.work_outline, color: color),
          ),
        ),
        title: Text(
          clientName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          request.items.map((item) => item.serviceName).join(', '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              requestStatusLabel(request.status),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              formatDateTime(request.requestedTime),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpcomingJobRow extends StatelessWidget {
  const _UpcomingJobRow({required this.request, required this.onTap});

  final ServiceRequestModel request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final serviceName = _requestServiceName(request);
    final customerName = _requestCustomerName(request);
    final timeText = _businessHomeTimeLabel(request.requestedTime);
    final locationText = _requestLocationSummary(request);
    final statusText = _businessStatusLabel(request.status);
    final semanticsLabel =
        '$serviceName. $customerName. ${_dateSemanticLabel(request.requestedTime)} saat $timeText. $statusText.';

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RequestDateBadge(date: request.requestedTime),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        serviceName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF111111),
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          height: 1.16,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _BusinessUpcomingMetaText(
                            icon: Icons.schedule_rounded,
                            text: timeText,
                          ),
                          _BusinessUpcomingMetaText(
                            icon: Icons.place_outlined,
                            text: locationText,
                          ),
                          _RequestStatusBadge(label: statusText),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ExcludeSemantics(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.black.withValues(alpha: 0.34),
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestDateBadge extends StatelessWidget {
  const _RequestDateBadge({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final isToday = _isSameDay(date, DateTime.now());
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F3F5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isToday ? 'BUGÜN' : date.day.toString().padLeft(2, '0'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF111111),
              fontSize: isToday ? 10.5 : 17,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            isToday
                ? _businessHomeTimeLabel(date)
                : _monthShortLabel(date.month),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestStatusBadge extends StatelessWidget {
  const _RequestStatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F3F5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE6E6EA)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF111111),
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _BusinessUpcomingMetaText extends StatelessWidget {
  const _BusinessUpcomingMetaText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}

bool _isSameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

String _requestServiceName(ServiceRequestModel request) {
  final names = request.items
      .map((item) => item.serviceName.trim())
      .where((name) => name.isNotEmpty)
      .toList();
  if (names.isEmpty) return 'Hizmet talebi';
  return names.join(', ');
}

String _requestCustomerName(ServiceRequestModel request) =>
    request.clientName?.trim().isNotEmpty == true
    ? request.clientName!.trim()
    : 'Müşteri';

String _requestLocationSummary(ServiceRequestModel request) {
  final address = request.addressNote?.trim();
  if (address == null || address.isEmpty) return 'Konum bilgisi yok';
  final parts = address
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length >= 2) return parts.take(2).join(', ');
  final words = address.split(RegExp(r'\s+'));
  if (words.length > 4) return '${words.take(4).join(' ')}…';
  return address;
}

String _businessStatusLabel(String status) => switch (status) {
  'Pending' => 'Yeni Talep',
  'Accepted' => 'Onaylandı',
  'OnTheWay' => 'Yolda',
  'Started' => 'Devam Ediyor',
  'Completed' => 'Tamamlandı',
  'Cancelled' => 'İptal Edildi',
  'Rejected' => 'Reddedildi',
  _ => 'Durum bilinmiyor',
};

String _businessHomeTimeLabel(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String _dateSemanticLabel(DateTime date) {
  if (_isSameDay(date, DateTime.now())) return 'Bugün';
  return '${date.day} ${_monthLongLabel(date.month)}';
}

String _monthShortLabel(int month) => switch (month) {
  1 => 'OCA',
  2 => 'ŞUB',
  3 => 'MAR',
  4 => 'NİS',
  5 => 'MAY',
  6 => 'HAZ',
  7 => 'TEM',
  8 => 'AĞU',
  9 => 'EYL',
  10 => 'EKİ',
  11 => 'KAS',
  12 => 'ARA',
  _ => '',
};

String _monthLongLabel(int month) => switch (month) {
  1 => 'Ocak',
  2 => 'Şubat',
  3 => 'Mart',
  4 => 'Nisan',
  5 => 'Mayıs',
  6 => 'Haziran',
  7 => 'Temmuz',
  8 => 'Ağustos',
  9 => 'Eylül',
  10 => 'Ekim',
  11 => 'Kasım',
  12 => 'Aralık',
  _ => '',
};
