import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../onboarding/widgets/kvkk_sheet.dart';
import '../bloc/auth_cubit.dart';
import '../widgets/auth_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String _selectedRole = 'Musteri';
  String? _error;

  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) => email.contains('@') && email.contains('.');
  bool _isValidPhone(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    return d.length == 10 && d.startsWith('5');
  }

  Future<void> _register() async {
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (email.isEmpty || !_isValidEmail(email)) {
      setState(() => _error = 'Geçerli bir e-posta adresi girin.');
      return;
    }
    if (!_isValidPhone(phone)) {
      setState(() => _error = 'Geçerli bir telefon numarası girin (5XX XXX XX XX).');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Şifre en az 8 karakter olmalıdır.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Şifreler eşleşmiyor.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    final result = await context.read<AuthCubit>().register(
      email: email,
      phone: phone,
      password: password,
      role: _selectedRole,
    );

    if (!mounted) return;
    if (result.error != null) {
      setState(() { _loading = false; _error = result.error; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                // Back button
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                  ),
                ),

                // Title
                Text(
                  'Hesap oluştur',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Bilgilerinizi girerek kayıt olun.\nEmail ve telefon doğrulamasını daha sonra\nayarlardan yapabilirsiniz.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),

                // Email
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  enabled: !_loading,
                  decoration: InputDecoration(
                    labelText: 'E-posta',
                    hintText: 'ornek@email.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Phone
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  enabled: !_loading,
                  decoration: InputDecoration(
                    labelText: 'Telefon',
                    hintText: '5XX XXX XX XX',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Password
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  enabled: !_loading,
                  decoration: InputDecoration(
                    labelText: 'Şifre',
                    hintText: 'En az 6 karakter',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Confirm password
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  enabled: !_loading,
                  onSubmitted: (_) => _register(),
                  decoration: InputDecoration(
                    labelText: 'Şifre Tekrar',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Role selection
                Text('Hesap türü', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _RoleCard(
                        icon: Icons.person_outline,
                        title: 'Müşteri',
                        subtitle: 'Hizmet alacağım',
                        selected: _selectedRole == 'Musteri',
                        onTap: () => setState(() => _selectedRole = 'Musteri'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RoleCard(
                        icon: Icons.store_outlined,
                        title: 'İşletme',
                        subtitle: 'Hizmet vereceğim',
                        selected: _selectedRole == 'Berber',
                        onTap: () => setState(() => _selectedRole = 'Berber'),
                      ),
                    ),
                  ],
                ),

                // Error
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // Register button
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _loading ? null : _register,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Kayıt Ol', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 16),

                // Login link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Zaten hesabınız var mı?', style: TextStyle(color: Colors.grey.shade600)),
                    TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('Giriş yapın', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),

                // KVKK
                GestureDetector(
                  onTap: () => showKvkkSheet(context),
                  child: const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Kayıt olarak KVKK ve Kullanım Koşullarını\nkabul etmiş olursunuz.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
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

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primaryContainer.withAlpha(60) : cs.surfaceContainerHighest.withAlpha(60),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? cs.primary : Colors.transparent,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 28, color: selected ? cs.primary : Colors.grey),
              const SizedBox(height: 6),
              Text(title, style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal, color: selected ? cs.primary : null)),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
