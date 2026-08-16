import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/customer_ui.dart';
import 'customer_smoke_repository.dart';

class CustomerSmokeApp extends StatelessWidget {
  const CustomerSmokeApp({super.key, required this.dependencies});

  final CustomerSmokeDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    final baseTheme = AppTheme.light;
    final smokeTheme = baseTheme.copyWith(
      appBarTheme: baseTheme.appBarTheme.copyWith(
        titleTextStyle: AppTypography.titleMedium.copyWith(
          color: AppColors.textPrimary,
        ),
      ),
    );
    return MaterialApp(
      title: 'HizmetGelsin Customer Smoke',
      debugShowCheckedModeBanner: false,
      theme: smokeTheme,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: CustomerSmokeJourney(dependencies: dependencies),
    );
  }
}

enum CustomerSmokeStep {
  home('Ana Sayfa'),
  savedAddress('Kayıtlı Adres Seçimi'),
  manualAddress('Manuel Adres Seçimi'),
  category('Kategori'),
  search('Arama'),
  discovery('Keşif Listesi'),
  map('Harita'),
  businessDetail('İşletme Detay'),
  service('Hizmet Seçimi'),
  requestForm('Talep Formu'),
  requestSummary('Talep Özeti'),
  success('Başarılı'),
  offers('Teklifler'),
  offerDetail('Teklif Detayı'),
  offerActions('Teklif Aksiyonları'),
  appointments('Randevular'),
  requestDetail('Talep Detayı'),
  timeline('Timeline'),
  profile('Profil'),
  addresses('Adresler'),
  favorites('Favoriler'),
  ratings('Yorumlar'),
  notifications('Bildirimler'),
  deepLinkFallback('Bağlantı Hatası'),
  backNavigation('Geri Navigasyon');

  const CustomerSmokeStep(this.title);
  final String title;
}

class CustomerSmokeJourney extends StatefulWidget {
  const CustomerSmokeJourney({super.key, required this.dependencies});

  final CustomerSmokeDependencies dependencies;

  @override
  State<CustomerSmokeJourney> createState() => _CustomerSmokeJourneyState();
}

class _CustomerSmokeJourneyState extends State<CustomerSmokeJourney> {
  int _index = 0;
  late final TextEditingController _manualAddressController;
  late final TextEditingController _searchController;

  CustomerSmokeStep get _step => CustomerSmokeStep.values[_index];
  InMemoryCustomerSmokeRepository get _repo => widget.dependencies.repository;

  @override
  void initState() {
    super.initState();
    _manualAddressController = TextEditingController(
      text: 'Sinanpaşa Mahallesi, Beşiktaş',
    );
    _searchController = TextEditingController(text: 'saç kesimi');
  }

  @override
  void dispose() {
    _manualAddressController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _next() {
    if (_index >= CustomerSmokeStep.values.length - 1) return;
    setState(() => _index++);
  }

  void _back() {
    if (_index == 0) return;
    setState(() => _index--);
  }

  void _message(String value) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$value · yalnız bellekte')));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _index == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: AppScaffold(
      title: _step.title,
      actions: const [
        Tooltip(
          message: 'Ağ erişimi kapalı',
          child: Padding(
            padding: EdgeInsets.only(right: AppSpacing.md),
            child: Icon(
              Icons.shield_outlined,
              semanticLabel: 'Ağ erişimi kapalı',
            ),
          ),
        ),
      ],
      body: Column(
        children: [
          const _IsolationBanner(),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppDurations.fast,
              child: ListView(
                key: ValueKey('smoke-step-${_step.name}'),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                children: _contentFor(_step),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _JourneyFooter(
        index: _index,
        total: CustomerSmokeStep.values.length,
        onBack: _index == 0 ? null : _back,
        onNext: _index == CustomerSmokeStep.values.length - 1 ? null : _next,
      ),
    ),
  );

  List<Widget> _contentFor(CustomerSmokeStep step) => switch (step) {
    CustomerSmokeStep.home => _home(),
    CustomerSmokeStep.savedAddress => _savedAddress(),
    CustomerSmokeStep.manualAddress => _manualAddress(),
    CustomerSmokeStep.category => _category(),
    CustomerSmokeStep.search => _search(),
    CustomerSmokeStep.discovery => _discovery(),
    CustomerSmokeStep.map => _map(),
    CustomerSmokeStep.businessDetail => _businessDetail(),
    CustomerSmokeStep.service => _service(),
    CustomerSmokeStep.requestForm => _requestForm(),
    CustomerSmokeStep.requestSummary => _requestSummary(),
    CustomerSmokeStep.success => _success(),
    CustomerSmokeStep.offers => _offers(),
    CustomerSmokeStep.offerDetail => _offerDetail(),
    CustomerSmokeStep.offerActions => _offerActions(),
    CustomerSmokeStep.appointments => _appointments(),
    CustomerSmokeStep.requestDetail => _requestDetail(),
    CustomerSmokeStep.timeline => _timeline(),
    CustomerSmokeStep.profile => _profile(),
    CustomerSmokeStep.addresses => _addresses(),
    CustomerSmokeStep.favorites => _favorites(),
    CustomerSmokeStep.ratings => _ratings(),
    CustomerSmokeStep.notifications => _notifications(),
    CustomerSmokeStep.deepLinkFallback => _deepLinkFallback(),
    CustomerSmokeStep.backNavigation => _backNavigation(),
  };

  List<Widget> _home() => [
    Text(
      'Merhaba, ${_repo.customer.displayName}',
      style: AppTypography.titleLarge,
    ),
    const SizedBox(height: AppSpacing.xs),
    const Text(
      'Bugün hangi hizmete ihtiyacınız var?',
      style: AppTypography.bodyLarge,
    ),
    const SizedBox(height: AppSpacing.lg),
    _SmokeCard(
      icon: Icons.location_on_outlined,
      title: 'Aktif adres',
      subtitle: 'Ev · Beşiktaş, İstanbul',
      trailing: const StatusBadge(
        label: 'Varsayılan',
        tone: StatusTone.success,
      ),
    ),
    const SizedBox(height: AppSpacing.md),
    const _SearchPreview(),
    const SizedBox(height: AppSpacing.lg),
    const Text('Öne çıkan hizmetler', style: AppTypography.titleMedium),
    const SizedBox(height: AppSpacing.sm),
    Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: _repo.categories
          .map((category) => Chip(label: Text(category.name)))
          .toList(),
    ),
    const SizedBox(height: AppSpacing.lg),
    _BusinessCard(business: _repo.businesses.first),
  ];

  List<Widget> _savedAddress() => [
    const _SectionIntro(
      title: 'Hizmet adresini seçin',
      description: 'Seçiminiz yalnız bu izole oturumda tutulur.',
    ),
    for (final address in _repo.addresses)
      Semantics(
        label:
            '${address.label}, ${address.shortAddress}, ${address.isDefault ? 'varsayılan adres' : 'varsayılan değil'}, ${_repo.selectedAddressId == address.id ? 'seçili' : 'seçili değil'}',
        selected: _repo.selectedAddressId == address.id,
        button: true,
        child: Card(
          child: ListTile(
            onTap: () => setState(() => _repo.selectAddress(address.id)),
            title: Text(address.label),
            subtitle: Text(address.shortAddress),
            leading: address.isDefault
                ? const Icon(
                    Icons.verified_outlined,
                    semanticLabel: 'Varsayılan',
                  )
                : const Icon(Icons.location_on_outlined),
            trailing: Icon(
              _repo.selectedAddressId == address.id
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              semanticLabel: _repo.selectedAddressId == address.id
                  ? 'Seçili'
                  : 'Seçili değil',
            ),
          ),
        ),
      ),
  ];

  List<Widget> _manualAddress() => [
    const _SectionIntro(
      title: 'Manuel adres gir',
      description: 'Koordinat veya gerçek kullanıcı verisi kullanılmaz.',
    ),
    AppTextField(
      controller: _manualAddressController,
      label: 'Adres tarifi',
      helperText: 'Fixture adresi; yalnız bellekte',
      prefixIcon: Icons.edit_location_alt_outlined,
    ),
    const SizedBox(height: AppSpacing.md),
    PrimaryButton(
      key: const Key('use-manual-address'),
      label: 'Manuel adresi kullan',
      icon: Icons.check_circle_outline,
      onPressed: () {
        setState(() => _repo.useManualAddress(_manualAddressController.text));
        _message('Manuel adres seçildi');
      },
    ),
    if (_repo.manualAddress != null) ...[
      const SizedBox(height: AppSpacing.sm),
      const StatusBadge(label: 'Manuel adres seçili', tone: StatusTone.success),
    ],
  ];

  List<Widget> _category() => [
    const _SectionIntro(
      title: 'Kategori seçin',
      description: 'Uzun etiketlerde satır taşması olmadan seçim yapılabilir.',
    ),
    Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: _repo.categories.map((category) {
        final selected = category.id == _repo.selectedCategoryId;
        return ChoiceChip(
          label: Text(category.name),
          selected: selected,
          onSelected: (_) => setState(() => _repo.selectCategory(category.id)),
        );
      }).toList(),
    ),
  ];

  List<Widget> _search() => [
    const _SectionIntro(
      title: 'Hizmet veya işletme ara',
      description: 'Arama fixture listesinde yerel olarak çalışır.',
    ),
    AppTextField(
      controller: _searchController,
      label: 'Arama',
      prefixIcon: Icons.search,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _message('Yerel arama tamamlandı'),
      clearable: true,
    ),
    const SizedBox(height: AppSpacing.md),
    PrimaryButton(
      label: 'Ara',
      icon: Icons.search,
      onPressed: () => _message('2 fixture sonucu bulundu'),
    ),
  ];

  List<Widget> _discovery() => [
    const _SectionIntro(
      title: 'Yakındaki işletmeler',
      description: 'Beşiktaş çevresi · 2 sonuç',
    ),
    for (final business in _repo.businesses) ...[
      _BusinessCard(business: business),
      const SizedBox(height: AppSpacing.sm),
    ],
  ];

  List<Widget> _map() => [
    const _SectionIntro(
      title: 'Haritada keşfet',
      description:
          'Harita yerel bir çizimdir; tile veya konum isteği yapılmaz.',
    ),
    _FakeMap(
      business: _repo.businesses.first,
      onMarkerTap: () => _message('Fixture marker seçildi'),
    ),
    const SizedBox(height: AppSpacing.md),
    _BusinessCard(business: _repo.businesses.first),
  ];

  List<Widget> _businessDetail() {
    final business = _repo.businesses.first;
    final favorite = _repo.favoriteBusinessIds.contains(business.id);
    return [
      Container(
        height: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          gradient: const LinearGradient(
            colors: [AppColors.primary, Color(0xFF3A8C7B)],
          ),
        ),
        child: const Center(
          child: Icon(Icons.content_cut, size: 64, color: Colors.white),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          Expanded(child: Text(business.name, style: AppTypography.titleLarge)),
          IconButton(
            tooltip: favorite ? 'Favoriden çıkar' : 'Favoriye ekle',
            onPressed: () => setState(() => _repo.toggleFavorite(business.id)),
            icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
          ),
        ],
      ),
      Text('${business.rating} puan · ${business.reviewCount} yorum'),
      const SizedBox(height: AppSpacing.md),
      const _SmokeCard(
        icon: Icons.location_on_outlined,
        title: 'Konum',
        subtitle: 'Beşiktaş, İstanbul · fixture konumu',
      ),
      const SizedBox(height: AppSpacing.sm),
      const _SmokeCard(
        icon: Icons.schedule_outlined,
        title: 'Bugün açık',
        subtitle: '09.00–21.00',
        trailing: StatusBadge(label: 'Açık', tone: StatusTone.success),
      ),
    ];
  }

  List<Widget> _service() => [
    const _SectionIntro(
      title: 'Hizmet seçin',
      description: 'Fiyat ve süreler deterministik fixture değerleridir.',
    ),
    for (final service in _repo.services)
      Card(
        child: ListTile(
          onTap: () => setState(() => _repo.selectService(service.id)),
          title: Text(service.name),
          subtitle: Text('${service.minutes} dakika'),
          leading: Icon(
            _repo.selectedServiceId == service.id
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
          ),
          trailing: Text('${service.price} ₺', style: AppTypography.labelLarge),
        ),
      ),
  ];

  List<Widget> _requestForm() => [
    const _SectionIntro(
      title: 'Talebinizi oluşturun',
      description: 'Bu form gerçek bir talep göndermez.',
    ),
    const _SmokeCard(
      icon: Icons.content_cut,
      title: 'Saç Kesimi',
      subtitle: '40 dakika · seçili hizmet',
    ),
    const SizedBox(height: AppSpacing.sm),
    const _SmokeCard(
      icon: Icons.home_outlined,
      title: 'Ev',
      subtitle: 'Beşiktaş, İstanbul · varsayılan adres',
    ),
    const SizedBox(height: AppSpacing.sm),
    const AppTextField(
      label: 'Talep notu',
      helperText: 'İsteğe bağlı',
      prefixIcon: Icons.notes_outlined,
    ),
    const SizedBox(height: AppSpacing.sm),
    const _SmokeCard(
      icon: Icons.schedule_outlined,
      title: 'Tercih edilen zaman',
      subtitle: 'Bugün · 18.30',
    ),
  ];

  List<Widget> _requestSummary() => [
    const _SectionIntro(
      title: 'Talep özeti',
      description: 'Göndermeden önce bilgilerinizi kontrol edin.',
    ),
    _SummaryCard(
      rows: const [
        ('Hizmet', 'Saç Kesimi'),
        ('Adres', 'Ev · Beşiktaş'),
        ('Zaman', 'Bugün · 18.30'),
        ('Bütçe', '350–550 ₺'),
      ],
    ),
    const SizedBox(height: AppSpacing.md),
    PrimaryButton(
      label: 'Talebi güvenli biçimde simüle et',
      icon: Icons.lock_outline,
      onPressed: () => _message('Bellek içi talep hazırlandı'),
    ),
  ];

  List<Widget> _success() => const [
    SizedBox(height: AppSpacing.xxl),
    Icon(Icons.check_circle, size: 88, color: AppColors.success),
    SizedBox(height: AppSpacing.lg),
    Text(
      'Talep simülasyonu tamamlandı',
      textAlign: TextAlign.center,
      style: AppTypography.titleLarge,
    ),
    SizedBox(height: AppSpacing.sm),
    Text(
      'Hiçbir backend isteği veya gerçek kayıt oluşturulmadı.',
      textAlign: TextAlign.center,
      style: AppTypography.bodyLarge,
    ),
  ];

  List<Widget> _offers() => [
    const _SectionIntro(
      title: 'Teklifleriniz',
      description: '1 aktif, 1 süresi dolmuş fixture teklif',
    ),
    for (final offer in _repo.offers) ...[
      _OfferCard(offer: offer),
      const SizedBox(height: AppSpacing.sm),
    ],
  ];

  List<Widget> _offerDetail() {
    final offer = _repo.offers.first;
    return [
      _SectionIntro(
        title: offer.businessName,
        description: 'Teklif ayrıntıları',
      ),
      _SummaryCard(
        rows: [
          ('Fiyat', '${offer.price} ₺'),
          ('Hizmet', 'Saç Kesimi'),
          ('Zaman', 'Bugün · 18.30'),
          ('Kalan süre', '24 dakika'),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      const StatusBadge(label: 'Aktif teklif', tone: StatusTone.success),
    ];
  }

  List<Widget> _offerActions() => [
    const _SectionIntro(
      title: 'Teklif aksiyonları',
      description: 'Kontroller yalnız UI durumunu gösterir; işlem göndermez.',
    ),
    PrimaryButton(
      label: 'Teklifi kabul et',
      icon: Icons.check,
      onPressed: () => _message('Kabul UI doğrulandı'),
    ),
    const SizedBox(height: AppSpacing.sm),
    SecondaryButton(
      label: 'Teklifi reddet',
      icon: Icons.close,
      onPressed: () => _message('Red UI doğrulandı'),
    ),
    const SizedBox(height: AppSpacing.sm),
    SecondaryButton(
      label: 'Karşı teklif ver',
      icon: Icons.swap_horiz,
      onPressed: () => _message('Karşı teklif UI doğrulandı'),
    ),
    const SizedBox(height: AppSpacing.lg),
    Semantics(
      label: 'Teklif süresi doldu. Bu teklif için işlem yapılamaz.',
      child: const _SmokeCard(
        icon: Icons.timer_off_outlined,
        title: 'Süresi dolmuş teklif',
        subtitle: 'Kabul, red ve karşı teklif aksiyonları kullanılamaz.',
        trailing: StatusBadge(label: 'İşlem kapalı', tone: StatusTone.warning),
      ),
    ),
  ];

  List<Widget> _appointments() => [
    const _SectionIntro(
      title: 'Randevularım',
      description: 'Aktif ve geçmiş filtreleri yerel olarak kullanılabilir.',
    ),
    SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'active', label: Text('Aktif')),
        ButtonSegment(value: 'past', label: Text('Geçmiş')),
      ],
      selected: const {'active'},
      onSelectionChanged: (_) => _message('Randevu filtresi değişti'),
    ),
    const SizedBox(height: AppSpacing.md),
    for (final appointment in _repo.appointments)
      _SmokeCard(
        icon: Icons.calendar_month_outlined,
        title: appointment.businessName,
        subtitle: '${appointment.timeLabel} · ${appointment.status}',
        trailing: const StatusBadge(
          label: 'Onaylandı',
          tone: StatusTone.success,
        ),
      ),
  ];

  List<Widget> _requestDetail() => [
    const _SectionIntro(
      title: 'Talep ve randevu detayı',
      description: 'Fixture talep durumu',
    ),
    _SummaryCard(
      rows: [
        ('Durum', _repo.request.status),
        ('Hizmet', 'Saç Kesimi'),
        ('İşletme', _repo.businesses.first.name),
        ('Randevu', 'Bugün · 18.30'),
      ],
    ),
    const SizedBox(height: AppSpacing.md),
    const _SmokeCard(
      icon: Icons.info_outline,
      title: 'İşlem geçmişi',
      subtitle: 'Timeline ekranında 4 adım var',
    ),
  ];

  List<Widget> _timeline() => const [
    _SectionIntro(
      title: 'Talep zaman çizelgesi',
      description: 'En güncel durum üstte gösterilir.',
    ),
    _TimelineTile('Randevu onaylandı', 'Bugün · 12.18', true),
    _TimelineTile('Teklif kabul edildi', 'Bugün · 12.14', true),
    _TimelineTile('Yeni teklif alındı', 'Bugün · 12.08', true),
    _TimelineTile('Talep oluşturuldu', 'Bugün · 12.00', true),
  ];

  List<Widget> _profile() => [
    const _SmokeCard(
      icon: Icons.person_outline,
      title: 'Smoke Müşteri',
      subtitle: 'İzole fixture profili · iletişim bilgisi yok',
      trailing: StatusBadge(label: 'Müşteri', tone: StatusTone.success),
    ),
    const SizedBox(height: AppSpacing.lg),
    const _MenuTile(
      Icons.location_on_outlined,
      'Adreslerim',
      '2 kayıtlı adres',
    ),
    const _MenuTile(Icons.favorite_outline, 'Favorilerim', '1 işletme'),
    const _MenuTile(Icons.star_outline, 'Yorumlarım', '1 yorum'),
    const _MenuTile(
      Icons.notifications_outlined,
      'Bildirimlerim',
      '1 okunmamış',
    ),
  ];

  List<Widget> _addresses() => [
    const _SectionIntro(
      title: 'Adreslerim',
      description:
          'Kart aksiyonları yalnız bellek içi fixture üzerinde çalışır.',
    ),
    for (final address in _repo.addresses)
      _SmokeCard(
        icon: address.isDefault ? Icons.home_outlined : Icons.business_outlined,
        title: address.label,
        subtitle: address.shortAddress,
        trailing: address.isDefault
            ? const StatusBadge(label: 'Varsayılan', tone: StatusTone.success)
            : const Icon(Icons.more_horiz),
      ),
  ];

  List<Widget> _favorites() => [
    const _SectionIntro(
      title: 'Favorilerim',
      description: 'Favori state’i izole repository ile senkron.',
    ),
    _BusinessCard(business: _repo.businesses.first),
    const SizedBox(height: AppSpacing.sm),
    SecondaryButton(
      label: _repo.favoriteBusinessIds.contains(_repo.businesses.first.id)
          ? 'Favoriden çıkar'
          : 'Favoriye ekle',
      icon: Icons.favorite_border,
      onPressed: () =>
          setState(() => _repo.toggleFavorite(_repo.businesses.first.id)),
    ),
  ];

  List<Widget> _ratings() => [
    const _SectionIntro(
      title: 'Yorumlarım',
      description: 'Moderasyon durumu kullanıcı dostu ifadeyle gösterilir.',
    ),
    for (final rating in _repo.ratings)
      _SmokeCard(
        icon: Icons.star,
        title: '${rating.businessName} · ${rating.score} yıldız',
        subtitle: '${rating.comment}\n${rating.moderation}',
        trailing: const Icon(
          Icons.edit_outlined,
          semanticLabel: 'Yorumu düzenle',
        ),
      ),
  ];

  List<Widget> _notifications() => [
    Row(
      children: [
        const Expanded(
          child: _SectionIntro(
            title: 'Bildirimlerim',
            description: 'Okunmamış durum yalnız renkle anlatılmaz.',
          ),
        ),
        TextButton(
          onPressed: () => setState(_repo.markAllNotificationsRead),
          child: const Text('Tümünü oku'),
        ),
      ],
    ),
    for (final notification in _repo.notifications)
      _SmokeCard(
        icon: notification.isRead
            ? Icons.notifications_none
            : Icons.notifications_active_outlined,
        title: notification.title,
        subtitle:
            '${notification.body}\n${notification.isRead ? 'Okundu' : 'Okunmadı'}',
        trailing: notification.isRead
            ? null
            : const StatusBadge(label: 'Yeni', tone: StatusTone.warning),
      ),
  ];

  List<Widget> _deepLinkFallback() => const [
    SizedBox(height: AppSpacing.xxl),
    Icon(Icons.link_off_outlined, size: 80, color: AppColors.warning),
    SizedBox(height: AppSpacing.lg),
    Text(
      'Bu bağlantı açılamıyor',
      textAlign: TextAlign.center,
      style: AppTypography.titleLarge,
    ),
    SizedBox(height: AppSpacing.sm),
    Text(
      'Bağlantı güvenli route listesinde değil veya artık geçerli değil. Ana sayfaya dönebilirsiniz.',
      textAlign: TextAlign.center,
      style: AppTypography.bodyLarge,
    ),
  ];

  List<Widget> _backNavigation() => [
    const SizedBox(height: AppSpacing.xxl),
    const Icon(Icons.task_alt, size: 88, color: AppColors.success),
    const SizedBox(height: AppSpacing.lg),
    const Text(
      'Güvenli müşteri UI turu tamamlandı',
      textAlign: TextAlign.center,
      style: AppTypography.titleLarge,
    ),
    const SizedBox(height: AppSpacing.sm),
    Text(
      '${CustomerSmokeStep.values.length} ekran adımı · 0 HTTP · 0 SignalR · 0 push kaydı',
      textAlign: TextAlign.center,
      style: AppTypography.bodyLarge,
    ),
    const SizedBox(height: AppSpacing.lg),
    SecondaryButton(
      key: const Key('verify-back-navigation'),
      label: 'Geri navigasyonu doğrula',
      icon: Icons.arrow_back,
      onPressed: _back,
    ),
  ];
}

class _IsolationBanner extends StatelessWidget {
  const _IsolationBanner();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'İzole müşteri smoke modu. Ağ, push ve SignalR kapalı.',
    child: Container(
      width: double.infinity,
      color: AppColors.primaryContainer,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, size: 18),
          SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'İzole UI Smoke · Ağ / Push / SignalR kapalı',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelMedium,
            ),
          ),
        ],
      ),
    ),
  );
}

class _JourneyFooter extends StatelessWidget {
  const _JourneyFooter({
    required this.index,
    required this.total,
    required this.onBack,
    required this.onNext,
  });

  final int index;
  final int total;
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Material(
      color: AppColors.surface,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(value: (index + 1) / total),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('${index + 1}/$total', style: AppTypography.labelMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('smoke-back'),
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Geri'),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('smoke-next'),
                    onPressed: onNext,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(onNext == null ? 'Bitti' : 'Sonraki'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _SectionIntro extends StatelessWidget {
  const _SectionIntro({required this.title, required this.description});
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(description, style: AppTypography.bodyMedium),
      ],
    ),
  );
}

class _SmokeCard extends StatelessWidget {
  const _SmokeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                Text(title, style: AppTypography.labelLarge),
                const SizedBox(height: AppSpacing.xxs),
                Text(subtitle, style: AppTypography.bodyMedium),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.xs),
            Flexible(child: trailing!),
          ],
        ],
      ),
    ),
  );
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({required this.business});
  final SmokeBusiness business;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label:
        '${business.name}, ${business.category}, ${business.rating} puan, ${business.reviewCount} yorum, minimum ${business.minimumPrice} Türk lirası, ${business.isOpen ? 'açık' : 'kapalı'}',
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.storefront_outlined, size: 34),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    business.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge,
                  ),
                  Text(business.category, style: AppTypography.bodySmall),
                  const SizedBox(height: AppSpacing.xxs),
                  Text('★ ${business.rating} · ${business.reviewCount} yorum'),
                  Text('${business.minimumPrice} ₺’den başlayan'),
                ],
              ),
            ),
            StatusBadge(
              label: business.isOpen ? 'Açık' : 'Kapalı',
              tone: business.isOpen ? StatusTone.success : StatusTone.neutral,
            ),
          ],
        ),
      ),
    ),
  );
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer});
  final SmokeOffer offer;

  @override
  Widget build(BuildContext context) {
    final expired = offer.status == 'Süresi doldu';
    return Semantics(
      label: expired
          ? '${offer.businessName}, ${offer.price} Türk lirası. Teklif süresi doldu. Bu teklif için işlem yapılamaz.'
          : '${offer.businessName}, ${offer.price} Türk lirası, aktif teklif.',
      child: _SmokeCard(
        icon: expired ? Icons.timer_off_outlined : Icons.local_offer_outlined,
        title: offer.businessName,
        subtitle:
            '${offer.price} ₺ · ${expired ? 'İşlem yapılamaz' : '24 dakika kaldı'}',
        trailing: StatusBadge(
          label: offer.status,
          tone: expired ? StatusTone.warning : StatusTone.success,
        ),
      ),
    );
  }
}

class _FakeMap extends StatelessWidget {
  const _FakeMap({required this.business, required this.onMarkerTap});
  final SmokeBusiness business;
  final VoidCallback onMarkerTap;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('offline-smoke-map'),
    height: 280,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xFFE9F0ED),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.border),
    ),
    child: Stack(
      children: [
        const Positioned(
          left: -20,
          top: 74,
          right: -20,
          child: Divider(thickness: 12, color: Colors.white),
        ),
        const Positioned(
          left: 100,
          top: -30,
          bottom: -30,
          child: VerticalDivider(thickness: 10, color: Colors.white),
        ),
        const Positioned(
          right: 24,
          top: 26,
          child: Text('Fixture haritası', style: AppTypography.labelMedium),
        ),
        Center(
          child: Semantics(
            button: true,
            label: '${business.name} harita işaretçisi',
            child: IconButton.filled(
              key: const Key('smoke-map-marker'),
              tooltip: business.name,
              onPressed: onMarkerTap,
              icon: const Icon(Icons.content_cut),
            ),
          ),
        ),
        const Positioned(
          left: AppSpacing.sm,
          bottom: AppSpacing.sm,
          child: StatusBadge(
            label: 'Çevrimdışı çizim',
            tone: StatusTone.neutral,
          ),
        ),
      ],
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.rows});
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(rows[i].$1, style: AppTypography.bodyMedium),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    rows[i].$2,
                    textAlign: TextAlign.end,
                    style: AppTypography.labelMedium,
                  ),
                ),
              ],
            ),
            if (i < rows.length - 1) const Divider(height: AppSpacing.lg),
          ],
        ],
      ),
    ),
  );
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile(this.title, this.time, this.completed);
  final String title;
  final String time;
  final bool completed;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      completed ? Icons.check_circle : Icons.radio_button_unchecked,
      color: completed ? AppColors.success : AppColors.disabled,
    ),
    title: Text(title),
    subtitle: Text(time),
  );
}

class _MenuTile extends StatelessWidget {
  const _MenuTile(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      minVerticalPadding: AppSpacing.sm,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}

class _SearchPreview extends StatelessWidget {
  const _SearchPreview();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: AppTextField(
      label: 'Hizmet veya işletme ara',
      prefixIcon: Icons.search,
    ),
  );
}
