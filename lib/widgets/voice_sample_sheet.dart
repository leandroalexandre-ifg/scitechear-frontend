import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:record/record.dart';
import '../core/theme/app_colors.dart';
import '../models/participant.dart';
import '../services/audio_service.dart';
import 'gradient_button.dart';
import 'participant_avatar.dart';

/// Bottom sheet para gravar a amostra de voz (biometria) de um participante.
/// A gravação é salva em armazenamento persistente, pois é reutilizada em
/// futuras reuniões a partir do cadastro de participantes.
class VoiceSampleSheet extends StatefulWidget {
  final Participant participant;
  final void Function(String path) onSaved;

  const VoiceSampleSheet({
    super.key,
    required this.participant,
    required this.onSaved,
  });

  @override
  State<VoiceSampleSheet> createState() => _VoiceSampleSheetState();
}

class _VoiceSampleSheetState extends State<VoiceSampleSheet>
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

    await _audio.start(
      filename: 'voice_${widget.participant.id}',
      persistent: true,
    );

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
