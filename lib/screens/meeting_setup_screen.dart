import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:record/record.dart';
import '../core/theme/app_colors.dart';
import '../models/participant.dart';
import '../services/audio_service.dart';
import '../services/auth_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../widgets/participant_avatar.dart';
import 'recording_screen.dart';

class MeetingSetupScreen extends StatefulWidget {
  final AuthService authService;
  const MeetingSetupScreen({super.key, required this.authService});

  @override
  State<MeetingSetupScreen> createState() => _MeetingSetupScreenState();
}

class _MeetingSetupScreenState extends State<MeetingSetupScreen> {
  final _titleCtrl = TextEditingController();
  final List<Participant> _participants = [];
  int _colorCursor = 0;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  void _addParticipant() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 28,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Adicionar participante',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Nome do participante',
                prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
              ),
            ),
            const SizedBox(height: 24),
            GradientButton(
              label: 'Adicionar',
              icon: Icons.add_rounded,
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isNotEmpty) {
                  setState(() {
                    _participants.add(Participant(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      name: name,
                      colorIndex: _colorCursor++ %
                          AppColors.participantColors.length,
                    ));
                  });
                }
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _recordVoiceSample(Participant participant) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _VoiceSampleSheet(
        participant: participant,
        onSaved: (path) {
          setState(() {
            final idx = _participants.indexWhere((p) => p.id == participant.id);
            if (idx != -1) {
              _participants[idx] =
                  _participants[idx].copyWith(voiceSamplePath: path);
            }
          });
        },
      ),
    );
  }

  void _removeParticipant(String id) {
    setState(() => _participants.removeWhere((p) => p.id == id));
  }

  void _startRecording() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordingScreen(
          participants: _participants,
          meetingTitle: _titleCtrl.text.trim().isEmpty
              ? null
              : _titleCtrl.text.trim(),
        ),
      ),
    );
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
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTitleSection(),
                      const SizedBox(height: 32),
                      _buildParticipantsSection(),
                      const SizedBox(height: 40),
                      _buildStartButton(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 24, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimary, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            'Nova Reunião',
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildTitleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Título (opcional)',
          style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
              fontSize: 13),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _titleCtrl,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          decoration: const InputDecoration(
            hintText: 'ex.: Reunião de Planejamento Sprint 12',
            prefixIcon: Icon(Icons.title_rounded, size: 20),
          ),
        ),
      ],
    ).animate(delay: 80.ms).fadeIn().slideY(begin: 0.2);
  }

  Widget _buildParticipantsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Participantes',
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Grave amostras de voz para melhorar a diarização.',
                    style: GoogleFonts.inter(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _addParticipant,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withAlpha(80),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 4),
                    Text(
                      'Adicionar',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.2),
        const SizedBox(height: 16),
        if (_participants.isEmpty)
          GlassCard(
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.group_add_rounded,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Adicione pelo menos um\nparticipante para continuar.',
                    style: GoogleFonts.inter(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ).animate(delay: 200.ms).fadeIn()
        else
          ...List.generate(_participants.length, (i) {
            final p = _participants[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ParticipantCard(
                participant: p,
                onRecord: () => _recordVoiceSample(p),
                onRemove: () => _removeParticipant(p.id),
              ),
            ).animate(delay: (200 + i * 60).ms).fadeIn().slideX(begin: 0.15);
          }),
      ],
    );
  }

  Widget _buildStartButton() {
    return GradientButton(
      label: 'Iniciar Gravação',
      icon: Icons.mic_rounded,
      onPressed: _participants.isEmpty ? null : _startRecording,
      gradient: AppColors.heroGradient,
    ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.3);
  }
}

class _ParticipantCard extends StatelessWidget {
  final Participant participant;
  final VoidCallback onRecord;
  final VoidCallback onRemove;

  const _ParticipantCard({
    required this.participant,
    required this.onRecord,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          ParticipantAvatar(participant: participant, size: 46, showCheckmark: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  participant.name,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  participant.hasVoiceSample
                      ? '✓ Amostra de voz gravada'
                      : 'Sem amostra de voz',
                  style: GoogleFonts.inter(
                    color: participant.hasVoiceSample
                        ? AppColors.success
                        : AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconBtn(
                icon: participant.hasVoiceSample
                    ? Icons.mic_rounded
                    : Icons.mic_none_rounded,
                color: participant.hasVoiceSample
                    ? AppColors.success
                    : AppColors.primary,
                onTap: onRecord,
                tooltip: participant.hasVoiceSample
                    ? 'Regravar amostra'
                    : 'Gravar amostra de voz',
              ),
              const SizedBox(width: 4),
              _IconBtn(
                icon: Icons.close_rounded,
                color: AppColors.error,
                onTap: onRemove,
                tooltip: 'Remover',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}

// ─── Bottom sheet para gravar amostra de voz ───────────────────────────────

class _VoiceSampleSheet extends StatefulWidget {
  final Participant participant;
  final void Function(String path) onSaved;

  const _VoiceSampleSheet({required this.participant, required this.onSaved});

  @override
  State<_VoiceSampleSheet> createState() => _VoiceSampleSheetState();
}

class _VoiceSampleSheetState extends State<_VoiceSampleSheet>
    with SingleTickerProviderStateMixin {
  final _audio = AudioService();
  bool _recording = false;
  bool _done = false;
  String? _savedPath;
  int _elapsed = 0;
  Timer? _timer;
  StreamSubscription<Amplitude>? _ampSub;
  double _amplitude = 0.0;
  late AnimationController _pulseCtrl;

  static const _maxSeconds = 10;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    _pulseCtrl.dispose();
    _audio.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final granted = await _audio.requestPermission();
    if (!granted || !mounted) return;

    setState(() {
      _recording = true;
      _done = false;
      _elapsed = 0;
    });

    await _audio.start(filename: 'sample_${widget.participant.id}');

    _ampSub = _audio.amplitudeStream.listen((amp) {
      if (!mounted) return;
      final normalized = ((amp.current + 60) / 60).clamp(0.0, 1.0);
      setState(() => _amplitude = normalized);
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
      if (_elapsed >= _maxSeconds) _stop();
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    _ampSub?.cancel();
    final path = await _audio.stop();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _done = true;
      _savedPath = path;
    });
  }

  void _confirm() {
    if (_savedPath != null) widget.onSaved(_savedPath!);
    Navigator.pop(context);
  }

  Color get _participantColor => AppColors.participantColors[
      widget.participant.colorIndex % AppColors.participantColors.length];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Amostra de voz',
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Fale por até $_maxSeconds segundos enquanto\ngrava a voz de ${widget.participant.name}.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 36),

          // Visualização do avatar + pulso
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) {
              final scale = _recording
                  ? 1.0 + 0.18 * _pulseCtrl.value * _amplitude
                  : 1.0;
              return Transform.scale(
                scale: scale,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_recording)
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _participantColor.withAlpha(
                            (60 * _amplitude).round(),
                          ),
                        ),
                      ),
                    ParticipantAvatar(
                      participant: widget.participant,
                      size: 76,
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 20),
          if (_recording) ...[
            Text(
              '${_elapsed}s / ${_maxSeconds}s',
              style: GoogleFonts.inter(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _elapsed / _maxSeconds,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(_participantColor),
              borderRadius: BorderRadius.circular(4),
            ),
          ] else if (_done)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Amostra gravada com sucesso!',
                  style: GoogleFonts.inter(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                ),
              ],
            ),

          const SizedBox(height: 36),

          if (!_recording && !_done)
            GradientButton(
              label: 'Iniciar gravação',
              icon: Icons.mic_rounded,
              onPressed: _start,
              gradient: LinearGradient(
                colors: [_participantColor, _participantColor.withAlpha(180)],
              ),
            )
          else if (_recording)
            GradientButton(
              label: 'Parar',
              icon: Icons.stop_rounded,
              onPressed: _stop,
              gradient: const LinearGradient(
                  colors: [AppColors.recording, Color(0xFFFF6B6B)]),
            )
          else ...[
            GradientButton(
              label: 'Usar esta amostra',
              icon: Icons.check_rounded,
              onPressed: _confirm,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() => _done = false),
              child: const Text(
                'Gravar novamente',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
