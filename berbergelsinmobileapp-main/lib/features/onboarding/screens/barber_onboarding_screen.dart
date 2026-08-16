import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/data/selection_options.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/widgets/auth_widgets.dart';
import '../../map/data/barbers_repo.dart';
import '../data/onboarding_repo.dart';
import '../widgets/kvkk_sheet.dart';

bool isValidTcKimlik(String tc) {
  if (tc.length != 11 || int.tryParse(tc) == null || tc[0] == '0') {
    return false;
  }
  final d = tc.split('').map(int.parse).toList();
  final oddSum = d[0] + d[2] + d[4] + d[6] + d[8];
  final evenSum = d[1] + d[3] + d[5] + d[7];
  var d10 = ((oddSum * 7) - evenSum) % 10;
  if (d10 < 0) d10 += 10;
  final d11 = d.sublist(0, 10).reduce((a, b) => a + b) % 10;
  return d[9] == d10 && d[10] == d11;
}

class BarberOnboardingScreen extends StatefulWidget {
  const BarberOnboardingScreen({
    super.key,
    this.initialStep,
    this.statusLoader,
  });

  /// Test ve izole görsel harness'lerinde sunucu çağrısı olmadan adım açar.
  final int? initialStep;
  final Future<OnboardingStatus> Function()? statusLoader;

  @override
  State<BarberOnboardingScreen> createState() => _BarberOnboardingScreenState();
}

class _ServiceRow {
  _ServiceRow({String name = '', String price = ''})
    : nameController = TextEditingController(text: name),
      priceController = TextEditingController(text: price);

  final TextEditingController nameController;
  final TextEditingController priceController;

  void dispose() {
    nameController.dispose();
    priceController.dispose();
  }
}

class _DecimalPriceFormatter extends TextInputFormatter {
  const _DecimalPriceFormatter();

  static final _pattern = RegExp(r'^\d{0,6}([\.,]\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => _pattern.hasMatch(newValue.text) ? newValue : oldValue;
}

class _BarberOnboardingScreenState extends State<BarberOnboardingScreen> {
  static const _stepTitles = ['İşletme bilgileri', 'Hizmetler', 'Son ayarlar'];

  int _step = 0;
  bool _busy = false;
  bool _resuming = true;
  String? _resumeError;

  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  String? _scilName, _ikametName;
  bool _scilUploaded = false, _ikametUploaded = false;
  bool _uploadingScil = false, _uploadingIkamet = false;
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _tcKimlik = TextEditingController();
  final _businessName = TextEditingController();
  final _category = TextEditingController();
  List<String> _categoryOptions = ServiceSelectionOptions.categories;
  bool _kvkkAccepted = false;

  final List<_ServiceRow> _services = [
    _ServiceRow(name: 'Standart Hizmet'),
    _ServiceRow(name: 'Ek Hizmet'),
  ];
  bool _acceptsOffers = false;
  bool _sharePhone = false;
  double _radiusKm = 5;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthCubit>().state.user;
    if (user != null) {
      _firstName.text = user.firstName ?? '';
      _lastName.text = user.lastName ?? '';
      _email.text = user.email ?? '';
      _phone.text = formatTurkishMobile(user.phone);
    }
    _loadCategories();
    final initialStep = widget.initialStep;
    if (initialStep != null) {
      _step = initialStep.clamp(0, 2).toInt();
      _resuming = false;
    } else {
      _resumeFromServer();
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await BarbersRepo.instance.categories();
      if (mounted) {
        setState(() => _categoryOptions = categories);
      }
    } catch (_) {
      // fallback: ServiceSelectionOptions.categories zaten atanmış
    }
  }

  Future<void> _resumeFromServer() async {
    if (mounted) {
      setState(() {
        _resuming = true;
        _resumeError = null;
      });
    }
    try {
      final status =
          await (widget.statusLoader ?? OnboardingRepo.instance.status)();
      if (!mounted) return;
      setState(() {
        _step = status.hasServices ? 2 : (status.hasProfileStep ? 1 : 0);
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _resumeError = 'Kayıt durumunuz alınamadı: ${e.message}',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _resumeError =
              'Kayıt durumunuz şu anda alınamıyor. Lütfen tekrar deneyin.',
        );
      }
    } finally {
      if (mounted) setState(() => _resuming = false);
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _tcKimlik.dispose();
    _businessName.dispose();
    _category.dispose();
    for (final service in _services) {
      service.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDocument({required bool isScil}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null) return;

    setState(() {
      if (isScil) {
        _uploadingScil = true;
      } else {
        _uploadingIkamet = true;
      }
    });

    try {
      final type = isScil ? 'ScilBelgesi' : 'IkametAdresi';
      await OnboardingRepo.instance.uploadDocument(
        bytes: file.bytes!,
        fileName: file.name,
        contentType: file.extension?.toLowerCase() == 'png'
            ? 'image/png'
            : file.extension?.toLowerCase() == 'pdf'
                ? 'application/pdf'
                : 'image/jpeg',
        type: type,
      );
      if (mounted) {
        setState(() {
          if (isScil) {
            _scilUploaded = true;
            _scilName = file.name;
            _uploadingScil = false;
          } else {
            _ikametUploaded = true;
            _ikametName = file.name;
            _uploadingIkamet = false;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (isScil) {
            _uploadingScil = false;
          } else {
            _uploadingIkamet = false;
          }
        });
        _showError('Belge yüklenemedi: ${e is ApiException ? e.message : 'Tekrar deneyin.'}');
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('İşlem tamamlanamadı. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitStep1() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_kvkkAccepted) {
      _showError('Devam etmek için KVKK metnini kabul etmelisiniz.');
      return;
    }
    if (!_scilUploaded) {
      _showError('SCİL belgesi yüklemeden devam edemezsiniz.');
      return;
    }
    if (!_ikametUploaded) {
      _showError('İkamet adresi yüklemeden devam edemezsiniz.');
      return;
    }
    await _run(() async {
      await OnboardingRepo.instance.submitBarberProfile(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        email: _email.text.trim(),
        phone: normalizeTurkishMobile(_phone.text),
        tcKimlikNo: _tcKimlik.text.trim(),
        businessName: _businessName.text.trim(),
        category: _category.text.trim(),
      );
      if (mounted) setState(() => _step = 1);
    });
  }

  Future<void> _submitStep2() async {
    final services = <({String name, double price})>[];
    for (final row in _services) {
      final name = row.nameController.text.trim();
      final price = double.tryParse(
        row.priceController.text.trim().replaceAll(',', '.'),
      );
      if (name.isEmpty) continue;
      if (price == null || price < 1) {
        _showError('"$name" için geçerli bir fiyat girin.');
        return;
      }
      services.add((name: name, price: price));
    }
    if (services.isEmpty) {
      _showError('En az bir hizmet eklemelisiniz.');
      return;
    }
    await _run(() async {
      await OnboardingRepo.instance.submitServices(
        services: services,
        acceptsOffers: _acceptsOffers,
      );
      if (mounted) setState(() => _step = 2);
    });
  }

  Future<void> _submitFinal() async {
    await _run(() async {
      await OnboardingRepo.instance.complete(
        sharePhone: _sharePhone,
        serviceRadiusKm: _radiusKm.round(),
      );
      if (!mounted) return;
      await context.read<AuthCubit>().refreshUser();
    });
  }

  void _removeService(int index) {
    if (_busy) return;
    final removed = _services.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('İşletme kaydı'),
        actions: [
          TextButton(
            onPressed: _busy || _resuming
                ? null
                : () => context.read<AuthCubit>().logout(),
            child: const Text('Çıkış'),
          ),
        ],
      ),
      body: SafeArea(
        child: _resuming
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: AppSpacing.md),
                    Text('Kayıt durumunuz yükleniyor…'),
                  ],
                ),
              )
            : _resumeError != null
            ? _ResumeError(message: _resumeError!, onRetry: _resumeFromServer)
            : Column(
                children: [
                  _StepProgress(step: _step, title: _stepTitles[_step]),
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.md,
                        AppSpacing.xl,
                        AppSpacing.xxl,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: switch (_step) {
                            0 => _buildStep1(),
                            1 => _buildStep2(),
                            _ => _buildStep3(),
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStep1() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('İşletmenizi tanıyalım', style: AppTypography.headline),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Kişisel bilgileriniz ve müşterilerin göreceği işletme adını ekleyin.',
            style: AppTypography.bodyLarge.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          TextFormField(
            controller: _firstName,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Ad'),
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Ad zorunludur.' : null,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _lastName,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Soyad'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Soyad zorunludur.'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'E-posta'),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (email.isEmpty) return 'E-posta zorunludur.';
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                return 'Geçerli bir e-posta girin.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            readOnly: true,
            label: 'Doğrulanmış telefon numarası',
            child: TextFormField(
              controller: _phone,
              readOnly: true,
              enableInteractiveSelection: false,
              decoration: const InputDecoration(
                labelText: 'Doğrulanmış telefon',
                prefixText: '+90 ',
                fillColor: AppColors.primaryContainer,
                suffixIcon: Icon(
                  Icons.verified,
                  color: AppColors.success,
                  semanticLabel: 'Doğrulandı',
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _tcKimlik,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            maxLength: 11,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'T.C. Kimlik No',
              counterText: '',
              helperText: 'Kimlik doğrulaması için kullanılır',
            ),
            validator: (value) =>
                value == null || !isValidTcKimlik(value.trim())
                ? 'Geçerli bir T.C. Kimlik No girin.'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _businessName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'İşletme adı'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'İşletme adı zorunludur.'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: ServiceSelectionOptions.validOrNull(
              _categoryOptions,
              _category.text,
            ),
            decoration: const InputDecoration(
              labelText: 'Kategori',
              helperText: 'Müşteriler sizi bu kategoride bulur',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: [
              for (final item in _categoryOptions)
                DropdownMenuItem(
                  value: item,
                  child: Text(item, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _category.text = value ?? ''),
            validator: (value) =>
                value == null || value.toString().trim().isEmpty
                    ? 'Lütfen bir kategori seçin.'
                    : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          CheckboxListTile(
            value: _kvkkAccepted,
            onChanged: _busy
                ? null
                : (value) => setState(() => _kvkkAccepted = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Kullanım Koşullarını ve KVKK Aydınlatma Metnini okudum, kabul ediyorum.',
            ),
            subtitle: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => showKvkkSheet(context),
                child: const Text('Metni görüntüle'),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // ── Belge Yükleme ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFECECEF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.upload_file_rounded, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text('Zorunlu Belgeler',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('SCİL belgesi ve ikamet adresi yükleyin',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 14),
                // SCİL belgesi
                _DocumentUploadTile(
                  label: 'SCİL Belgesi',
                  hint: 'PDF veya fotoğraf',
                  fileName: _scilName,
                  uploaded: _scilUploaded,
                  uploading: _uploadingScil,
                  onPick: () => _pickDocument(isScil: true),
                ),
                const SizedBox(height: 10),
                // İkamet adresi
                _DocumentUploadTile(
                  label: 'İkamet Adresi',
                  hint: 'PDF veya fotoğraf',
                  fileName: _ikametName,
                  uploaded: _ikametUploaded,
                  uploading: _uploadingIkamet,
                  onPick: () => _pickDocument(isScil: false),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          LoadingPrimaryButton(
            label: 'Devam et',
            loading: _busy,
            onPressed: _busy ? null : _submitStep1,
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Hizmetler ve fiyatlar', style: AppTypography.headline),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Müşterilerin seçebileceği hizmetleri ve başlangıç fiyatlarını ekleyin.',
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (var i = 0; i < _services.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _buildServiceRow(i),
          ),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => setState(() => _services.add(_ServiceRow())),
          icon: const Icon(Icons.add),
          label: const Text('Yeni hizmet ekle'),
        ),
        const SizedBox(height: AppSpacing.lg),
        SwitchListTile(
          title: const Text('Müşterilerden pazarlık teklifi al'),
          subtitle: const Text(
            'Belirlediğiniz fiyat üzerinden indirim teklifi almaya izin verir.',
          ),
          value: _acceptsOffers,
          onChanged: _busy
              ? null
              : (value) => setState(() => _acceptsOffers = value),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: AppSpacing.xl),
        LoadingPrimaryButton(
          label: 'Devam et',
          loading: _busy,
          onPressed: _busy ? null : _submitStep2,
        ),
      ],
    );
  }

  Widget _buildServiceRow(int index) {
    final service = _services[index];
    final nameField = TextField(
      controller: service.nameController,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(labelText: 'Hizmet'),
    );
    final priceField = TextField(
      controller: service.priceController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [_DecimalPriceFormatter()],
      decoration: const InputDecoration(labelText: 'Fiyat', suffixText: '₺'),
    );
    final removeButton = IconButton(
      key: Key('remove_service_$index'),
      tooltip: 'Hizmeti sil',
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: _busy ? null : () => _removeService(index),
      color: AppColors.error,
      icon: const Icon(Icons.remove_circle_outline),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              nameField,
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: priceField),
                  const SizedBox(width: AppSpacing.xs),
                  removeButton,
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 3, child: nameField),
            const SizedBox(width: AppSpacing.sm),
            Expanded(flex: 2, child: priceField),
            removeButton,
          ],
        );
      },
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Son ayarlar', style: AppTypography.headline),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'İletişim tercihinizi ve hizmet vereceğiniz mesafeyi belirleyin.',
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        SwitchListTile(
          title: const Text('Telefon numaramı müşterilerle paylaş'),
          subtitle: const Text(
            'Müşteriler randevu öncesi veya sonrası size ulaşabilir.',
          ),
          value: _sharePhone,
          onChanged: _busy
              ? null
              : (value) => setState(() => _sharePhone = value),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: AppSpacing.xl),
        const Text(
          'Hizmet verilecek yarıçap',
          style: AppTypography.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Şu anki konumunuzdan en fazla ${_radiusKm.round()} km uzağa hizmet vereceksiniz.',
          key: const Key('barber_radius_text'),
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          label: 'Hizmet yarıçapı ${_radiusKm.round()} kilometre',
          child: Slider(
            key: const Key('barber_radius_slider'),
            value: _radiusKm,
            min: 1,
            max: 20,
            divisions: 19,
            label: '${_radiusKm.round()} km',
            onChanged: _busy
                ? null
                : (value) => setState(() => _radiusKm = value),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        LoadingPrimaryButton(
          label: 'Kaydı Tamamla',
          loading: _busy,
          onPressed: _busy ? null : _submitFinal,
        ),
      ],
    );
  }
}

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.step, required this.title});

  final int step;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Kayıt ilerlemesi: ${step + 1}/3 $title',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.md,
        ),
        color: AppColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${step + 1}/3 $title',
              key: const Key('barber_step_indicator'),
              style: AppTypography.labelMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            LinearProgressIndicator(
              value: (step + 1) / 3,
              minHeight: 6,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              backgroundColor: AppColors.primaryContainer,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumeError extends StatelessWidget {
  const _ResumeError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 52),
              const SizedBox(height: AppSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                key: const Key('barber_resume_retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar dene'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Belge Yükleme Tile ──

class _DocumentUploadTile extends StatelessWidget {
  const _DocumentUploadTile({
    required this.label,
    required this.hint,
    required this.fileName,
    required this.uploaded,
    required this.uploading,
    required this.onPick,
  });

  final String label, hint;
  final String? fileName;
  final bool uploaded, uploading;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: uploading ? null : onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: uploaded ? AppColors.success.withValues(alpha: 0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: uploaded ? AppColors.success.withValues(alpha: 0.3) : const Color(0xFFE0E0E0),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: uploaded ? AppColors.success.withValues(alpha: 0.15) : AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: uploading
                  ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(uploaded ? Icons.check_circle : Icons.upload_file,
                      color: uploaded ? AppColors.success : AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(
                    uploaded && fileName != null ? fileName! : uploading ? 'Yükleniyor...' : hint,
                    style: TextStyle(color: uploaded ? AppColors.success : AppColors.textSecondary, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (!uploaded && !uploading)
              const Icon(Icons.add_rounded, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}
