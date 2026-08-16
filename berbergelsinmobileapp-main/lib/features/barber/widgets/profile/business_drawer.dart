import 'dart:io' show File;
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Premium drawer — işletme paneli için sade menü.
class BusinessDrawer extends StatelessWidget {
  const BusinessDrawer({
    super.key,
    required this.businessName,
    required this.isOnline,
    this.logoPath,
    this.avgRating,
    this.ratingCount,
    this.category,
    required this.onProfileSettings,
    required this.onServices,
    required this.onPhotos,
    required this.onReviews,
    required this.onCustomerPreview,
    required this.onNotifications,
    required this.onLogout,
  });

  final String? businessName;
  final bool isOnline;
  final String? logoPath;
  final double? avgRating;
  final int? ratingCount;
  final String? category;
  final VoidCallback onProfileSettings;
  final VoidCallback onServices;
  final VoidCallback onPhotos;
  final VoidCallback onReviews;
  final VoidCallback onCustomerPreview;
  final VoidCallback onNotifications;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.78,
      child: SafeArea(
        child: Column(
          children: [
            _DrawerHeader(
              businessName: businessName ?? 'İşletme',
              isOnline: isOnline,
              logoPath: logoPath,
              avgRating: avgRating,
              ratingCount: ratingCount,
              category: category,
            ),
            const Divider(height: 1, indent: 0, endIndent: 0),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _SectionLabel('Vitrin'),
                  _DrawerItem(
                    icon: Icons.tune_rounded,
                    label: 'Profil Ayarları',
                    onTap: onProfileSettings,
                  ),
                  _DrawerItem(
                    icon: Icons.storefront_rounded,
                    label: 'Hizmetlerim',
                    onTap: onServices,
                  ),
                  _DrawerItem(
                    icon: Icons.photo_library_rounded,
                    label: 'Fotoğraf Galerisi',
                    onTap: onPhotos,
                  ),
                  _DrawerItem(
                    icon: Icons.star_rounded,
                    label: 'Yorumlarım',
                    onTap: onReviews,
                  ),
                  _DrawerItem(
                    icon: Icons.visibility_rounded,
                    label: 'Müşteri Önizlemesi',
                    onTap: onCustomerPreview,
                  ),
                  const SizedBox(height: 8),
                  _SectionLabel('Diğer'),
                  _DrawerItem(
                    icon: Icons.notifications_rounded,
                    label: 'Bildirimler',
                    onTap: onNotifications,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _DrawerItem(
              icon: Icons.logout_rounded,
              label: 'Çıkış Yap',
              onTap: onLogout,
              isDestructive: true,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Drawer header: koyu arka plan, logo, isim, online chip, puan.
class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({
    required this.businessName,
    required this.isOnline,
    this.logoPath,
    this.avgRating,
    this.ratingCount,
    this.category,
  });

  final String businessName;
  final bool isOnline;
  final String? logoPath;
  final double? avgRating;
  final int? ratingCount;
  final String? category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      color: const Color(0xFF111111),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _LogoAvatar(logoPath: logoPath, businessName: businessName),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      businessName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    if (category != null && category!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          category!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _OnlineChip(isOnline: isOnline),
              if (avgRating != null && ratingCount != null) ...[
                const SizedBox(width: 10),
                _RatingChip(avgRating: avgRating!, ratingCount: ratingCount!),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LogoAvatar extends StatelessWidget {
  const _LogoAvatar({this.logoPath, required this.businessName});

  final String? logoPath;
  final String businessName;

  @override
  Widget build(BuildContext context) {
    final hasLogo = logoPath != null && File(logoPath!).existsSync();
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLogo
          ? Image.file(File(logoPath!), fit: BoxFit.cover)
          : Center(
              child: Text(
                (businessName.isNotEmpty ? businessName[0] : 'İ').toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
    );
  }
}

class _OnlineChip extends StatelessWidget {
  const _OnlineChip({required this.isOnline});
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isOnline
            ? const Color(0xFF267A45).withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline ? const Color(0xFF267A45) : Colors.white.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isOnline ? 'Çevrimiçi' : 'Çevrimdışı',
            style: TextStyle(
              color: isOnline ? const Color(0xFF4ADE80) : Colors.white.withValues(alpha: 0.5),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.avgRating, required this.ratingCount});
  final double avgRating;
  final int ratingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: Color(0xFFF6B51E), size: 14),
          const SizedBox(width: 4),
          Text(
            avgRating.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            ' ($ratingCount)',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = isActive
        ? const Color(0xFF111111)
        : Colors.transparent;
    final fgColor = isDestructive
        ? const Color(0xFFBA1A1A)
        : isActive
            ? Colors.white
            : colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.of(context).pop(); // drawer'ı kapat
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: fgColor.withValues(alpha: isActive || isDestructive ? 1 : 0.7),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: fgColor,
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (isActive)
                  Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
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
