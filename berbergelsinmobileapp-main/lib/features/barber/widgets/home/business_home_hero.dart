part of '../../screens/barber_panel_screen.dart';

class BusinessHomeHero extends StatelessWidget {
  const BusinessHomeHero({
    super.key,
    required this.businessName,
    required this.isOnline,
    required this.busy,
    required this.profileScore,
    required this.serviceCount,
    required this.photoCount,
    required this.rating,
    required this.ratingCount,
    required this.onToggleOnline,
    required this.onOpenProfile,
  });

  final String businessName;
  final bool isOnline;
  final bool busy;
  final int profileScore;
  final int serviceCount;
  final int photoCount;
  final double? rating;
  final int ratingCount;
  final Future<void> Function(bool value) onToggleOnline;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final safeScore = profileScore.clamp(0, 100);
        final displayName = businessName.trim().isEmpty
            ? 'İşletmenizi yönetin'
            : businessName.trim();

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 18 : 20,
            vertical: compact ? 20 : 22,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroStatusRow(
                isOnline: isOnline,
                busy: busy,
                onToggleOnline: onToggleOnline,
              ),
              SizedBox(height: compact ? 22 : 24),
              _HeroGreeting(
                businessName: displayName,
                isOnline: isOnline,
                compact: compact,
              ),
              SizedBox(height: compact ? 20 : 22),
              _HeroHealth(
                profileScore: safeScore,
                serviceCount: serviceCount,
                photoCount: photoCount,
                rating: rating,
                ratingCount: ratingCount,
              ),
              const SizedBox(height: 18),
              _HeroPrimaryAction(onOpenProfile: onOpenProfile),
            ],
          ),
        );
      },
    );
  }
}

class _HeroStatusRow extends StatelessWidget {
  const _HeroStatusRow({
    required this.isOnline,
    required this.busy,
    required this.onToggleOnline,
  });

  final bool isOnline;
  final bool busy;
  final Future<void> Function(bool value) onToggleOnline;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _HeroStatusPill(isOnline: isOnline)),
        const SizedBox(width: 12),
        Semantics(
          label: isOnline
              ? 'İşletme çevrimiçi, kapatmak için dokunun'
              : 'İşletme çevrimdışı, açmak için dokunun',
          button: true,
          child: Switch.adaptive(
            value: isOnline,
            onChanged: busy
                ? null
                : (value) {
                    onToggleOnline(value);
                  },
            activeThumbColor: Colors.white,
            activeTrackColor: Colors.white.withValues(alpha: 0.34),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
          ),
        ),
      ],
    );
  }
}

class _HeroStatusPill extends StatelessWidget {
  const _HeroStatusPill({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isOnline
            ? const Color(0xFF1A2A20)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            size: 8,
            color: isOnline ? const Color(0xFF9CE6B0) : Colors.white54,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              child: Text(
                isOnline ? 'ÇEVRİMİÇİ' : 'ÇEVRİMDIŞI',
                key: ValueKey(isOnline),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isOnline ? const Color(0xFFE7F7EA) : Colors.white70,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroGreeting extends StatelessWidget {
  const _HeroGreeting({
    required this.businessName,
    required this.isOnline,
    required this.compact,
  });

  final String businessName;
  final bool isOnline;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hasName = businessName != 'İşletmenizi yönetin';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasName) ...[
          const Text(
            'Merhaba,',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          businessName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 27 : 31,
            fontWeight: FontWeight.w800,
            height: 1.06,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          isOnline
              ? 'Yeni müşteriler sizi görebilir ve talep gönderebilir.'
              : 'Yeni talepler almak için işletmenizi çevrimiçi yapın.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _HeroHealth extends StatelessWidget {
  const _HeroHealth({
    required this.profileScore,
    required this.serviceCount,
    required this.photoCount,
    required this.rating,
    required this.ratingCount,
  });

  final int profileScore;
  final int serviceCount;
  final int photoCount;
  final double? rating;
  final int ratingCount;

  @override
  Widget build(BuildContext context) {
    final ratingText = rating == null || rating == 0
        ? 'Henüz puan yok'
        : '${rating!.toStringAsFixed(1)} puan';
    return Semantics(
      label: 'Vitrin sağlığı yüzde $profileScore tamamlandı',
      value: '%$profileScore tamamlandı',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Vitrin sağlığı',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '%$profileScore',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 6,
              color: Colors.white.withValues(alpha: 0.15),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: profileScore / 100),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value,
                  child: Container(color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$serviceCount hizmet · $photoCount fotoğraf · $ratingText',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPrimaryAction extends StatelessWidget {
  const _HeroPrimaryAction({required this.onOpenProfile});

  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onOpenProfile,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF111111),
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storefront_rounded, size: 19),
            SizedBox(width: 9),
            Flexible(
              child: Text(
                'Vitrini Düzenle',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: 7),
            Icon(Icons.chevron_right_rounded, size: 19),
          ],
        ),
      ),
    );
  }
}
