import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.bottomNavigationBar,
    this.floatingActionButton,
  });
  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: title == null ? null : AppTopBar(title: title!, actions: actions),
    body: SafeArea(top: title == null, child: body),
    bottomNavigationBar: bottomNavigationBar,
    floatingActionButton: floatingActionButton,
  );
}

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({super.key, required this.title, this.actions, this.leading});
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) => AppBar(
    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    actions: actions,
    leading: leading,
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: FilledButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
    ),
  );
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon ?? Icons.arrow_forward, size: 20),
    label: Text(label, overflow: TextOverflow.ellipsis),
  );
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    required this.label,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.loading = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.prefixIcon,
    this.clearable = false,
  });
  final TextEditingController? controller;
  final String label;
  final String? helperText, errorText;
  final bool enabled, loading, clearable;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled && !loading,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    onSubmitted: onSubmitted,
    decoration: InputDecoration(
      labelText: label,
      helperText: helperText,
      errorText: errorText,
      prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
      suffixIcon: loading
          ? const Padding(
              padding: EdgeInsets.all(14),
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : clearable && controller?.text.isNotEmpty == true
          ? IconButton(
              tooltip: 'Temizle',
              onPressed: controller!.clear,
              icon: const Icon(Icons.clear),
            )
          : null,
    ),
  );
}

class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    this.controller,
    this.hintText = 'Hizmet veya işletme ara',
    this.onSubmitted,
    this.onFilter,
  });
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onFilter;
  @override
  Widget build(BuildContext context) => Semantics(
    textField: true,
    label: hintText,
    child: TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(AppIcons.search),
        suffixIcon: onFilter == null
            ? null
            : IconButton(
                tooltip: 'Filtreler',
                onPressed: onFilter,
                icon: const Icon(Icons.tune),
              ),
      ),
    ),
  );
}

class AddressSelector extends StatelessWidget {
  const AddressSelector({
    super.key,
    required this.address,
    required this.onTap,
    this.loading = false,
  });
  final String address;
  final VoidCallback onTap;
  final bool loading;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Arama konumu: $address',
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: loading ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            const Icon(AppIcons.location, color: AppColors.primary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Arama konumu',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down),
          ],
        ),
      ),
    ),
  );
}

class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.label,
    this.selected = false,
    required this.onSelected,
    this.icon,
  });
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    avatar: icon == null ? null : Icon(icon, size: 18),
    selected: selected,
    onSelected: onSelected,
    selectedColor: AppColors.primaryContainer,
    side: const BorderSide(color: AppColors.border),
  );
}

class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: selected,
    onSelected: onSelected,
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String? subtitle, actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null)
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
      if (actionLabel != null)
        TextButton(onPressed: onAction, child: Text(actionLabel!)),
    ],
  );
}

class RatingView extends StatelessWidget {
  const RatingView({super.key, required this.rating, this.count});
  final double rating;
  final int? count;
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${rating.toStringAsFixed(1)} puan${count == null ? '' : ', $count yorum'}',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, color: AppColors.warning, size: 18),
        const SizedBox(width: 4),
        Text(rating.toStringAsFixed(1), style: AppTypography.labelMedium),
        if (count != null)
          Text(
            ' ($count)',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
      ],
    ),
  );
}

class PriceView extends StatelessWidget {
  const PriceView({super.key, required this.price, this.prefix = 'Başlangıç'});
  final num price;
  final String prefix;
  @override
  Widget build(BuildContext context) => Text(
    '$prefix ${price.toStringAsFixed(price % 1 == 0 ? 0 : 2)} ₺',
    style: Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: AppColors.primary),
  );
}

enum StatusTone { neutral, success, warning, error }

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
  });
  final String label;
  final StatusTone tone;
  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      StatusTone.success => AppColors.success,
      StatusTone.warning => AppColors.warning,
      StatusTone.error => AppColors.error,
      StatusTone.neutral => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppTypography.bodySmall.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });
  final String title, message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => _StateLayout(
    icon: icon,
    title: title,
    message: message,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.title = 'Bir sorun oluştu',
    required this.message,
    this.onRetry,
    this.offline = false,
  });
  final String title, message;
  final VoidCallback? onRetry;
  final bool offline;
  @override
  Widget build(BuildContext context) => _StateLayout(
    icon: offline ? Icons.cloud_off_outlined : Icons.error_outline,
    title: offline ? 'İnternet bağlantısı yok' : title,
    message: message,
    actionLabel: onRetry == null ? null : 'Tekrar dene',
    onAction: onRetry,
  );
}

class _StateLayout extends StatelessWidget {
  const _StateLayout({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(label: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    ),
  );
}

class LoadingSkeleton extends StatefulWidget {
  const LoadingSkeleton({
    super.key,
    this.height = 16,
    this.width = double.infinity,
    this.radius = AppRadius.sm,
  });
  final double height, width, radius;
  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class CustomerListSkeleton extends StatelessWidget {
  const CustomerListSkeleton({
    super.key,
    this.itemCount = 3,
    this.cardHeight = 132,
    this.withImage = false,
  });

  final int itemCount;
  final double cardHeight;
  final bool withImage;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'İçerik yükleniyor',
    child: ExcludeSemantics(
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) => Card(
          child: SizedBox(
            height: cardHeight,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (withImage) ...[
                    const LoadingSkeleton(height: 72, width: 72),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const LoadingSkeleton(height: 18, width: 170),
                        const SizedBox(height: AppSpacing.sm),
                        const LoadingSkeleton(height: 14),
                        const SizedBox(height: AppSpacing.xs),
                        const LoadingSkeleton(height: 14, width: 220),
                        const Spacer(),
                        LoadingSkeleton(
                          height: 34,
                          width: withImage ? 120 : 190,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class InlineErrorNotice extends StatelessWidget {
  const InlineErrorNotice({
    super.key,
    required this.message,
    required this.onRetry,
    this.offline = false,
  });

  final String message;
  final VoidCallback onRetry;
  final bool offline;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: '${offline ? 'İnternet bağlantısı yok. ' : ''}$message',
    child: Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: (offline ? AppColors.warning : AppColors.error).withValues(
          alpha: .08,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            offline ? Icons.cloud_off_outlined : Icons.error_outline,
            color: offline ? AppColors.warning : AppColors.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
          TextButton(onPressed: onRetry, child: const Text('Yenile')),
        ],
      ),
    ),
  );
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: FadeTransition(
      opacity: Tween(begin: .45, end: .9).animate(_controller),
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    ),
  );
}

class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });
  final String title;
  final Widget content;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) =>
      AlertDialog(title: Text(title), content: content, actions: actions);
}

class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({super.key, this.title, required this.child});
  final String? title;
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.disabled,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (title != null) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title!,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    ),
  );
}

class ServiceCard extends StatelessWidget {
  const ServiceCard({
    super.key,
    required this.name,
    required this.category,
    this.description,
    this.price,
    this.icon = Icons.handyman_outlined,
    this.onTap,
  });
  final String name, category;
  final String? description;
  final num? price;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    category,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (description != null)
                    Text(
                      description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (price != null) PriceView(price: price!),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class BusinessCard extends StatelessWidget {
  const BusinessCard({
    super.key,
    required this.name,
    required this.category,
    this.coverUrl,
    this.logoUrl,
    this.rating,
    this.reviewCount,
    this.distanceText,
    this.minimumPrice,
    this.isOpen,
    this.favorite = false,
    this.onFavorite,
    this.onTap,
  });
  final String name, category;
  final String? coverUrl, logoUrl, distanceText;
  final double? rating;
  final int? reviewCount;
  final num? minimumPrice;
  final bool? isOpen;
  final bool favorite;
  final VoidCallback? onFavorite, onTap;
  static IconData _iconForCategory(String category) => switch (category.toLowerCase()) {
    final c when c.contains('tesisat') || c.contains('su') => Icons.plumbing_rounded,
    final c when c.contains('elektrik') => Icons.bolt_rounded,
    final c when c.contains('temiz') => Icons.cleaning_services_rounded,
    final c when c.contains('oto') || c.contains('ara') => Icons.car_repair_rounded,
    final c when c.contains('ders') || c.contains('eğitim') => Icons.school_rounded,
    final c when c.contains('kuaf') || c.contains('berber') || c.contains('güzellik') => Icons.content_cut_rounded,
    final c when c.contains('nakliye') || c.contains('taşı') => Icons.local_shipping_rounded,
    _ => Icons.handyman_rounded,
  };

  Widget _coverImage(String? url) => url == null || url.isEmpty
      ? Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2D2D2F), Color(0xFF3A3A3C)],
            ),
          ),
          child: Center(
            child: Icon(
              _iconForCategory(category),
              size: 48,
              color: Colors.white24,
            ),
          ),
        )
      : Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2D2D2F), Color(0xFF3A3A3C)],
              ),
            ),
            child: Center(
              child: Icon(
                _iconForCategory(category),
                size: 48,
                color: Colors.white24,
              ),
            ),
          ),
        );

  Widget _logoFallback() => Container(
    decoration: BoxDecoration(
      color: AppColors.primary,
      shape: BoxShape.circle,
    ),
    child: Center(
      child: Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.lg),
                ),
                child: SizedBox(
                  height: 128,
                  width: double.infinity,
                  child: _coverImage(coverUrl),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Semantics(
                  button: true,
                  label: favorite ? 'Favorilerden çıkar' : 'Favorilere ekle',
                  child: IconButton.filledTonal(
                    tooltip: favorite
                        ? 'Favorilerden çıkar'
                        : 'Favorilere ekle',
                    onPressed: onFavorite,
                    icon: AnimatedSwitcher(
                      duration: AppDurations.fast,
                      child: Icon(
                        favorite ? Icons.favorite : Icons.favorite_border,
                        key: ValueKey(favorite),
                        color: favorite
                            ? AppColors.error
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                bottom: 8,
                child: Container(
                  width: 48,
                  height: 48,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                  child: logoUrl != null && logoUrl!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          child: Image.network(logoUrl!, fit: BoxFit.cover),
                        )
                      : _logoFallback(),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (isOpen != null)
                      StatusBadge(
                        label: isOpen! ? 'Açık' : 'Kapalı',
                        tone: isOpen! ? StatusTone.success : StatusTone.neutral,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (rating != null)
                      RatingView(rating: rating!, count: reviewCount),
                    if (distanceText != null)
                      Text(
                        distanceText!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (minimumPrice != null) PriceView(price: minimumPrice!),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class ProfileMenuTile extends StatelessWidget {
  const ProfileMenuTile({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.onTap,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 52,
    leading: Icon(icon, color: AppColors.primary),
    title: Text(title),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: trailing ?? const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class NotificationCard extends StatelessWidget {
  const NotificationCard({
    super.key,
    required this.title,
    required this.message,
    this.time,
    this.read = false,
    this.onTap,
  });
  final String title, message;
  final String? time;
  final bool read;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    color: read ? AppColors.surface : AppColors.primaryContainer,
    child: ListTile(
      minTileHeight: 72,
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
      trailing: time == null
          ? null
          : Text(time!, style: Theme.of(context).textTheme.bodySmall),
      onTap: onTap,
    ),
  );
}

class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    super.key,
    required this.businessName,
    required this.dateText,
    required this.status,
    this.onTap,
  });
  final String businessName, dateText, status;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      minTileHeight: 76,
      leading: const CircleAvatar(
        backgroundColor: AppColors.primaryContainer,
        child: Icon(Icons.calendar_month, color: AppColors.primary),
      ),
      title: Text(businessName, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(dateText),
      trailing: StatusBadge(label: status),
      onTap: onTap,
    ),
  );
}

class OfferCard extends StatelessWidget {
  const OfferCard({
    super.key,
    required this.businessName,
    required this.price,
    required this.status,
    this.onTap,
  });
  final String businessName, status;
  final num price;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      minTileHeight: 76,
      title: Text(businessName, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: PriceView(price: price, prefix: 'Teklif'),
      trailing: StatusBadge(label: status),
      onTap: onTap,
    ),
  );
}
