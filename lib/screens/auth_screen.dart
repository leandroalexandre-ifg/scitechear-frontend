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

  /// Recusa do servidor referente ao e-mail digitado (domínio fora da
  /// allowlist institucional, endereço já cadastrado). Fica visível no campo
  /// até o próximo envio, porque nenhuma das duas causas se resolve tentando
  /// de novo com o mesmo endereço — o usuário precisa ler e corrigir.
  String? _serverEmailError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// Checagem só para pegar erro de digitação antes da viagem à rede — a
  /// validação que vale é a do backend (`EmailStr`).
  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Informe o e-mail';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'E-mail inválido';
    }
    return _serverEmailError;
  }

  Future<void> _submit() async {
    // Limpa antes de validar: senão a recusa anterior reprovaria o formulário
    // mesmo depois de o usuário corrigir o endereço.
    _serverEmailError = null;
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
      final message = e.toString().replaceAll('Exception: ', '');
      if (e is AuthException && e.field == 'email') {
        // Erro do endereço: mostra no campo, onde fica visível enquanto o
        // usuário corrige, em vez de num snackbar que some em segundos.
        setState(() => _serverEmailError = message);
        _formKey.currentState!.validate();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
          ),
        );
      }
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
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => v!.isEmpty ? 'Informe seu nome' : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
          ),
          // Só e-mail: o backend valida o campo como EmailStr, então um nome
          // de usuário seria recusado com 422 antes de chegar a qualquer
          // verificação de credencial.
          _field(
            ctrl: _emailCtrl,
            label: 'E-mail',
            icon: Icons.alternate_email_rounded,
            type: TextInputType.emailAddress,
            validator: _validateEmail,
          ).animate(delay: 220.ms).fadeIn().slideY(begin: 0.3),
          const SizedBox(height: 14),
          _field(
            ctrl: _passCtrl,
            label: 'Senha',
            icon: Icons.lock_outline_rounded,
            obscure: _obscurePass,
            // No cadastro, o mínimo de 8 é o mesmo do backend, para o erro
            // aparecer aqui em vez de voltar como um 422 do servidor. No
            // login não se valida tamanho: quem tem uma senha antiga mais
            // curta precisa conseguir entrar, e quem erra recebe a resposta
            // do servidor.
            validator: (v) {
              if (v == null || v.isEmpty) return 'Informe a senha';
              if (!_isLogin && v.length < 8) return 'Mínimo 8 caracteres';
              return null;
            },
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
                  // A recusa é do cadastro (domínio, e-mail duplicado): não
                  // faz sentido continuar aparecendo depois de trocar para o
                  // login, onde as duas causas não se aplicam.
                  _serverEmailError = null;
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
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: type,
      textCapitalization: textCapitalization,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
        // O `detail` do servidor pode ser uma frase inteira; com o padrão de
        // uma linha ela sairia cortada com reticências.
        errorMaxLines: 3,
      ),
    );
  }
}
