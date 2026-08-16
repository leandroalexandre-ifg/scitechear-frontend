import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';
import '../models/participant.dart';
import '../services/offline_service.dart';
import '../services/status_service.dart';
import '../widgets/glass_card.dart';
import 'result_screen.dart';

class ProcessingScreen extends StatefulWidget {
  final String jobId;
  final List<Participant> participants;

  const ProcessingScreen({
    super.key,
    required this.jobId,
    this.participants = const [],
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  final _status = StatusService();
  final _resultCache = LocalResultCache();
  String _currentStatus = 'queued';
  bool _navigated = false;

  bool _failed = false;
  String _errorTitle = '';
  String _errorMessage = '';

  static const _steps = [
    (key: 'queued',       label: 'Na fila',                    icon: Icons.hourglass_empty_rounded,    color: AppColors.textSecondary),
    (key: 'transcribing', label: 'Transcrevendo (Whisper)',     icon: Icons.text_fields_rounded,        color: AppColors.primary),
    (key: 'diarizing',    label: 'Separando falantes',          icon: Icons.groups_rounded,             color: AppColors.secondary),
    (key: 'identifying',  label: 'Identificando participantes', icon: Icons.record_voice_over_rounded,  color: Color(0xFFA78BFA)),
    (key: 'summarizing',  label: 'Gerando resumo',               icon: Icons.summarize_rounded,          color: Color(0xFFFBBF24)),
    (key: 'extracting',   label: 'Extraindo perguntas',         icon: Icons.psychology_rounded,         color: Color(0xFFF472B6)),
    (key: 'done',         label: 'Concluído',                   icon: Icons.check_circle_rounded,       color: AppColors.success),
  ];

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  void _listen() {
    if (widget.jobId.startsWith('local_')) {
      if (kDemoModeEnabled) {
        // Modo demonstração explícito: reunião já foi salva localmente
        // (backend indisponível no momento do envio) — simula as etapas e
        // mostra o resultado de demonstração já salvo.
        _simulateOfflineProcessing();
      } else {
        // Não deveria acontecer fora do modo demo — trata como erro real
        // em vez de fabricar um resultado.
        _showError(
          title: 'Reunião não enviada',
          message: 'Esta reunião não chegou a ser enviada ao servidor.',
        );
      }
      return;
    }

    _status.watchStatus(widget.jobId).listen((status) async {
      if (!mounted || _navigated) return;
      if (status == 'offline') {
        _navigated = true;
        _showError(
          title: 'Sem conexão com o servidor',
          message:
              'Não foi possível verificar o status. Verifique sua conexão e tente novamente.',
        );
        return;
      }
      setState(() => _currentStatus = status);
      if (status == 'done') {
        _navigated = true;
        try {
          final result = await _status.fetchResult(widget.jobId);
          await _resultCache.save(widget.jobId, result);
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ResultScreen(
                result: result,
                participants: widget.participants,
              ),
            ),
          );
        } catch (_) {
          _showError(
            title: 'Erro ao carregar o resultado',
            message:
                'O processamento terminou, mas não foi possível carregar o resultado. Tente novamente.',
          );
        }
      } else if (status == 'error') {
        _navigated = true;
        final detail = await _status.fetchStatusDetail(widget.jobId);
        final backendError = detail?['error'];
        final backendMessage = backendError is Map
            ? backendError['message']?.toString()
            : null;
        _showError(
          title: 'Falha no processamento',
          message: backendMessage ?? 'O processamento falhou no servidor.',
        );
      }
    });
  }

  Future<void> _simulateOfflineProcessing() async {
    for (final step
        in ['transcribing', 'diarizing', 'identifying', 'summarizing', 'extracting', 'done']) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      setState(() => _currentStatus = step);
    }
    final cached = await _resultCache.load(widget.jobId);
    final result = cached ??
        generateDemoResult(
          jobId: widget.jobId,
          participantNames: widget.participants.map((p) => p.name).toList(),
        );
    if (cached == null) {
      await _resultCache.save(widget.jobId, result);
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          result: result,
          participants: widget.participants,
        ),
      ),
    );
  }

  void _showError({required String title, required String message}) {
    if (!mounted) return;
    setState(() {
      _failed = true;
      _errorTitle = title;
      _errorMessage = message;
    });
  }

  void _retry() {
    setState(() {
      _failed = false;
      _navigated = false;
      _currentStatus = 'queued';
    });
    _listen();
  }

  int get _currentIndex {
    final i = _steps.indexWhere((s) => s.key == _currentStatus);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF080B14), Color(0xFF0F1729)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _failed ? _buildErrorView() : _buildProcessingView(),
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopBar(),
        const SizedBox(height: 24),
        _buildHeader(),
        const SizedBox(height: 48),
        _buildSteps(),
        const Spacer(),
        _buildJobId(),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildErrorView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.error.withAlpha(30),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 36),
        ).animate().fadeIn(duration: 400.ms).scale(),
        const SizedBox(height: 24),
        Text(
          _errorTitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _errorMessage,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Tentar novamente'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Voltar'),
          ),
        ),
        const SizedBox(height: 12),
        _buildJobId(),
      ],
    );
  }

  Widget _buildTopBar() {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        icon: const Icon(Icons.home_rounded,
            color: AppColors.textPrimary, size: 22),
        tooltip: 'Voltar às suas reuniões',
        onPressed: () {
          Navigator.of(context).popUntil((r) => r.isFirst);
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withAlpha(80),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.sync_rounded, color: Colors.white, size: 28),
        )
            .animate(onPlay: (c) => c.repeat())
            .rotate(duration: 2000.ms, curve: Curves.linear),
        const SizedBox(height: 20),
        Text(
          'Processando\nSua Reunião',
          style: GoogleFonts.inter(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Aguarde enquanto a IA analisa o áudio.',
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.2);
  }

  Widget _buildSteps() {
    return GlassCard(
      child: Column(
        children: List.generate(_steps.length, (i) {
          final step = _steps[i];
          final isDone = i < _currentIndex;
          final isActive = i == _currentIndex && _currentStatus != 'done';
          final isPending = i > _currentIndex;

          return Padding(
            padding: EdgeInsets.only(
              bottom: i < _steps.length - 1 ? 24 : 0,
            ),
            child: Row(
              children: [
                // Ícone/spinner
                SizedBox(
                  width: 36,
                  height: 36,
                  child: isActive
                      ? _ActiveSpinner(color: step.color)
                      : Container(
                          decoration: BoxDecoration(
                            color: isDone
                                ? AppColors.success.withAlpha(30)
                                : step.color.withAlpha(isPending ? 15 : 30),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isDone
                                ? Icons.check_rounded
                                : step.icon,
                            color: isDone
                                ? AppColors.success
                                : isPending
                                    ? AppColors.textMuted
                                    : step.color,
                            size: 18,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    step.label,
                    style: GoogleFonts.inter(
                      color: isPending
                          ? AppColors.textMuted
                          : isDone
                              ? AppColors.success
                              : AppColors.textPrimary,
                      fontWeight: isActive
                          ? FontWeight.w600
                          : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (isDone)
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 16),
              ],
            ),
          ).animate(delay: (i * 80).ms).fadeIn().slideX(begin: 0.2);
        }),
      ),
    ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.3);
  }

  Widget _buildJobId() {
    return Center(
      child: Text(
        'Job ID: ${widget.jobId}',
        style: GoogleFonts.robotoMono(
          color: AppColors.textMuted,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _ActiveSpinner extends StatefulWidget {
  final Color color;
  const _ActiveSpinner({required this.color});

  @override
  State<_ActiveSpinner> createState() => _ActiveSpinnerState();
}

class _ActiveSpinnerState extends State<_ActiveSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          color: widget.color.withAlpha(
              (20 + 20 * _ctrl.value).round()),
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.color.withAlpha(
                (100 + 60 * _ctrl.value).round()),
            width: 1.5,
          ),
        ),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(widget.color),
          ),
        ),
      ),
    );
  }
}
