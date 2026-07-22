import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';
import '../services/auth_service.dart';
import '../widgets/gradient_button.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  final AuthService authService;
  const AuthScreen({super.key, required this.authService});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _loading = false;
  bool _obscurePass = true;

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_isLogin) {
        await widget.authService.login(_emailCtrl.text.trim(), _passCtrl.text);
      } else {
        await widget.authService.register(
          _nameCtrl.text.trim(),
          _emailCtrl.text.trim(),
          _passCtrl.text,
        );
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(authService: widget.authService),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF080B14), Color(0xFF0D1220), Color(0xFF080B14)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 64),
                _buildBrand(),
                const SizedBox(height: 52),
                _buildForm(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrand() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withAlpha(100),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(Icons.hearing_rounded, color: Colors.white, size: 30),
        )
            .animate()
            .fadeIn(duration: 500.ms)
            .slideY(begin: -0.4, curve: Curves.easeOutCubic),
        const SizedBox(height: 24),
        Text(
          'SciTech\nEar',
          style: GoogleFonts.inter(
            fontSize: 38,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.1,
          ),
        )
            .animate(delay: 80.ms)
            .fadeIn(duration: 500.ms)
            .slideY(begin: 0.2, curve: Curves.easeOut),
        const SizedBox(height: 10),
        Text(
          _isLogin ? 'Bem-vindo de volta.' : 'Crie sua conta gratuita.',
          style: GoogleFonts.inter(
            fontSize: 16,
            color: AppColors.textSecondary,
          ),
        ).animate(delay: 160.ms).fadeIn(duration: 500.ms),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          AnimatedSize(
            duration: 280.ms,
            curve: Curves.easeInOut,
            child: _isLogin
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      _field(
                        ctrl: _nameCtrl,
                        label: 'Nome completo',
                        icon: Icons.person_outline_rounded,
                        validator: (v) => v!.isEmpty ? 'Informe seu nome' : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
          ),
          _field(
            ctrl: _emailCtrl,
            label: _isLogin ? 'E-mail ou usuário' : 'E-mail',
            icon: Icons.alternate_email_rounded,
            type: _isLogin ? TextInputType.text : TextInputType.emailAddress,
            validator: (v) => v!.isEmpty
                ? (_isLogin ? 'Informe seu e-mail ou usuário' : 'Informe o e-mail')
                : null,
          ).animate(delay: 220.ms).fadeIn().slideY(begin: 0.3),
          AnimatedSize(
            duration: 280.ms,
            curve: Curves.easeInOut,
            child: _isLogin
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Você pode entrar com seu nome de usuário ou e-mail cadastrado.',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ).animate(delay: 240.ms).fadeIn(),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 14),
          _field(
            ctrl: _passCtrl,
            label: 'Senha',
            icon: Icons.lock_outline_rounded,
            obscure: _obscurePass,
            validator: (v) =>
                v!.length < 6 ? 'Mínimo 6 caracteres' : null,
            suffix: IconButton(
              icon: Icon(
                _obscurePass
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppColors.textSecondary,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscurePass = !_obscurePass),
            ),
          ).animate(delay: 280.ms).fadeIn().slideY(begin: 0.3),
          const SizedBox(height: 32),
          GradientButton(
            label: _isLogin ? 'Entrar' : 'Criar conta',
            icon: _isLogin ? Icons.login_rounded : Icons.rocket_launch_rounded,
            onPressed: _submit,
            loading: _loading,
          ).animate(delay: 340.ms).fadeIn().slideY(begin: 0.3),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _isLogin ? 'Não tem conta?  ' : 'Já tem conta?  ',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _isLogin = !_isLogin;
                  _formKey.currentState?.reset();
                }),
                child: Text(
                  _isLogin ? 'Criar conta' : 'Entrar',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ).animate(delay: 400.ms).fadeIn(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    TextInputType? type,
    bool obscure = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: type,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
      ),
    );
  }
}
