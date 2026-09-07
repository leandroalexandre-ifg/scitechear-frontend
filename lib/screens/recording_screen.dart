import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:record/record.dart';
import '../core/theme/app_colors.dart';
import '../models/meeting.dart';
import '../models/participant.dart';
import '../services/audio_service.dart';
import '../services/background_service.dart';
import '../services/meeting_service.dart';
import '../services/offline_service.dart';
import '../services/upload_service.dart';
import '../widgets/participant_avatar.dart';
import 'processing_screen.dart';

class RecordingScreen extends StatefulWidget {
  final List<Participant> participants;
  final String? meetingTitle;

  const RecordingScreen({
    super.key,
    required this.participants,
    this.meetingTitle,
  });

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen>
    with TickerProviderStateMixin {
  final _audio = AudioService();
  final _background = BackgroundService();
  final _uploader = UploadService();
  final _history = MeetingHistoryService();
  final _resultCache = LocalResultCache();

  bool _isRecording = false;
  bool _isUploading = false;
  double _uploadProgress = 0;
  String? _uploadError;
  String? _pendingAudioPath;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  StreamSubscription<Amplitude>? _ampSub;
  StreamSubscription<RecordState>? _stateSub;

  // Gravação interrompida pelo próprio aparelho, sem o usuário pedir.
  String? _recordingError;
  // Caminho devolvido por `start()`, guardado como rede de segurança para
  // recuperar o áudio parcial caso `stop()` não devolva nada.
  String? _currentPath;
  // Guard sincrônico: a falha nativa chega como erro *e* como estado
  // `stop`, e os dois disparariam o mesmo tratamento.
  bool _handlingInterruption = false;

  // Waveform: 50 barras de amplitude normalizada
  final List<double> _bars = List<double>.generate(50, (_) => 0.02);

  late AnimationController _pulseCtrl;
  late AnimationController _stopBtnCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _stopBtnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    _stateSub?.cancel();
    _pulseCtrl.dispose();
    _stopBtnCtrl.dispose();
    _audio.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopAndUpload();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final granted = await _audio.requestPermission();
    if (!granted) {
      _showSnack('Permissão de microfone necessária.');
      return;
    }
    final bgReady = await _background.enable();
    if (!bgReady) {
      _showSnack('Não foi possível ativar a gravação em segundo plano.');
      return;
    }

    try {
      _currentPath = await _audio.start(persistent: true);
      setState(() {
        _isRecording = true;
        _handlingInterruption = false;
        _recordingError = null;
        _elapsed = Duration.zero;
        for (var i = 0; i < _bars.length; i++) {
          _bars[i] = 0.02;
        }
      });

      // Cronômetro
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
      });

      // Waveform em tempo real
      _ampSub = _audio.amplitudeStream.listen((amp) {
        if (!mounted) return;
        final normalized = ((amp.current + 60) / 60).clamp(0.02, 1.0);
        setState(() {
          _bars.removeAt(0);
          _bars.add(normalized);
        });
      });

      // Estado do gravador nativo. Uma parada que chegue por aqui nunca é
      // a do usuário — `_stopAndUpload` cancela esta inscrição antes de
      // chamar `stop()` —, então significa que o aparelho encerrou a
      // gravação sozinho e o áudio ficou truncado.
      _stateSub = _audio.stateStream.listen(
        (state) {
          if (state == RecordState.stop) {
            _handleUnexpectedStop(
                'A gravação foi encerrada pelo sistema do aparelho.');
          }
        },
        onError: (Object error, StackTrace stack) {
          debugPrint('Gravador nativo falhou: $error');
          _handleUnexpectedStop(
              'O microfone do aparelho falhou durante a gravação.');
        },
      );
    } catch (e) {
      await _background.disable();
      _showSnack('Erro ao iniciar a gravação: $e');
    }
  }

  /// Reage a uma parada do gravador que o usuário não pediu.
  ///
  /// O caso conhecido é o `AudioRecord.ERROR_DEAD_OBJECT` no Android
  /// (comum em aparelhos Samsung sob otimização agressiva de bateria): a
  /// thread nativa captura a exceção, finaliza o WAV com um header
  /// correto e encerra. O arquivo fica íntegro — só que truncado no ponto
  /// da falha. Sem esta reação, o app seguia mostrando o cronômetro
  /// correndo sobre uma gravação que já tinha morrido, e o usuário só
  /// descobria a perda depois do processamento.
  ///
  /// O lado nativo emite `onFailure(ex)` e, no `finally`, `onStop()` — os
  /// dois chegam aqui, daí o guard sincrônico logo na entrada.
  Future<void> _handleUnexpectedStop(String cause) async {
    if (!_isRecording || _handlingInterruption) return;
    _handlingInterruption = true;

    _timer?.cancel();
    _ampSub?.cancel();
    _stateSub?.cancel();

    final captured = _elapsed;

    // A thread nativa já não existe mais, então `stop()` apenas devolve o
    // caminho configurado, sem lançar. `_currentPath` cobre o caso de ela
    // devolver nulo.
    String? path;
    try {
      path = await _audio.stop();
    } catch (e) {
      debugPrint('Falha ao finalizar a gravação interrompida: $e');
    }
    path ??= _currentPath;

    await _background.disable();

    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _bars.fillRange(0, _bars.length, 0.02);
      _pendingAudioPath = path;
      _recordingError = path == null
          ? '$cause Não foi possível recuperar o áudio desta reunião.'
          : '$cause Só foram gravados os primeiros ${_fmt(captured)} — '
              'o restante da conversa não foi capturado.';
    });
  }

  Future<void> _stopAndUpload() async {
    // Uma interrupção em andamento já está cuidando de parar e recuperar o
    // áudio; deixar o toque do usuário seguir causaria um segundo envio.
    if (_handlingInterruption) return;

    _timer?.cancel();
    _ampSub?.cancel();
    _stateSub?.cancel();
    _stopBtnCtrl.forward();

    final path = await _audio.stop();
    await _background.disable();
    setState(() {
      _isRecording = false;
      _bars.fillRange(0, _bars.length, 0.02);
    });

    if (path == null) {
      _showSnack('Nenhum áudio gravado.');
      return;
    }

    _pendingAudioPath = path;
    await _attemptUpload(path);
  }

  Future<void> _attemptUpload(String path) async {
    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
      _uploadError = null;
    });

    String jobId;
    try {
      jobId = await _uploader.uploadMeeting(
        audioPath: path,
        participants: widget.participants,
        title: widget.meetingTitle,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
    } catch (e) {
      if (kDemoModeEnabled) {
        // Modo demonstração explícito (--dart-define=SCITECH_DEMO_MODE=true):
        // salva a reunião localmente com um resultado fabricado.
        jobId = 'local_${DateTime.now().microsecondsSinceEpoch}';
        final demoResult = generateDemoResult(
          jobId: jobId,
          participantNames: widget.participants.map((p) => p.name).toList(),
        );
        await _resultCache.save(jobId, demoResult);
      } else {
        // Erro real do backend/conexão: nunca virar resultado fictício —
        // mostra o erro e deixa o usuário tentar de novo com o mesmo áudio.
        if (!mounted) return;
        setState(() {
          _isUploading = false;
          _uploadError = e is UploadException
              ? e.message
              : 'Não foi possível enviar a gravação. Tente novamente.';
        });
        return;
      }
    }

    await _history.add(Meeting(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      jobId: jobId,
      title: widget.meetingTitle ?? 'Reunião sem título',
      createdAt: DateTime.now(),
      participantNames: widget.participants.map((p) => p.name).toList(),
    ));

    if (!mounted) return;
    setState(() => _isUploading = false);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(
          jobId: jobId,
          participants: widget.participants,
        ),
      ),
    );
  }

  void _retryUpload() {
    final path = _pendingAudioPath;
    if (path == null) return;
    _attemptUpload(path);
  }

  /// Envia o trecho que sobreviveu a uma interrupção. Truncado é melhor do
  /// que perdido: o backend processa normalmente o que receber.
  void _sendPartialRecording() {
    final path = _pendingAudioPath;
    if (path == null) return;
    setState(() => _recordingError = null);
    _attemptUpload(path);
  }

  void _discardRecording() {
    setState(() {
      _recordingError = null;
      _pendingAudioPath = null;
      _currentPath = null;
      _elapsed = Duration.zero;
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  String _statusLabel() {
    if (_isUploading) return 'Enviando áudio…';
    if (_recordingError != null) return 'Gravação interrompida';
    if (_isRecording) return 'Gravando • pode bloquear a tela';
    return 'Toque para começar';
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF080B14), Color(0xFF0A0E1A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              if (widget.participants.isNotEmpty) _buildParticipantChips(),
              Expanded(child: _buildCenter()),
              _buildBottomSection(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 24, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimary, size: 20),
            onPressed: _isRecording || _isUploading
                ? null
                : () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              widget.meetingTitle ?? 'Gravar Reunião',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.recording.withAlpha(30),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.recording.withAlpha(100)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.recording,
                      shape: BoxShape.circle,
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .fadeOut(duration: 600.ms),
                  const SizedBox(width: 6),
                  Text(
                    'AO VIVO',
                    style: GoogleFonts.inter(
                        color: AppColors.recording,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        letterSpacing: 0.8),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildParticipantChips() {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        itemCount: widget.participants.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = widget.participants[i];
          final color = AppColors.participantColors[
              p.colorIndex % AppColors.participantColors.length];
          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withAlpha(80)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ParticipantAvatar(participant: p, size: 22),
                const SizedBox(width: 6),
                Text(
                  p.name.split(' ').first,
                  style: GoogleFonts.inter(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).animate(delay: 100.ms).fadeIn();
  }

  Widget _buildCenter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Timer
          Text(
            _fmt(_elapsed),
            style: GoogleFonts.inter(
              fontSize: 72,
              fontWeight: FontWeight.w200,
              color: AppColors.textPrimary,
              letterSpacing: -2,
            ),
          ).animate().fadeIn(duration: 400.ms),

          const SizedBox(height: 6),
          Text(
            _statusLabel(),
            style: GoogleFonts.inter(
              color: _recordingError != null
                  ? AppColors.error
                  : _isRecording
                      ? AppColors.recording
                      : AppColors.textSecondary,
              fontSize: 14,
              fontWeight: _isRecording || _recordingError != null
                  ? FontWeight.w500
                  : FontWeight.normal,
            ),
          ).animate().fadeIn(duration: 400.ms),

          const SizedBox(height: 48),

          // Waveform
          SizedBox(
            height: 80,
            child: CustomPaint(
              painter: _WaveformPainter(
                bars: _bars,
                active: _isRecording,
                primaryColor: AppColors.primary,
                secondaryColor: AppColors.secondary,
              ),
              size: Size(MediaQuery.of(context).size.width - 56, 80),
            ),
          ).animate().fadeIn(duration: 600.ms),
        ],
      ),
    );
  }

  /// Banner de erro com as ações que o usuário tem a partir dele.
  Widget _buildErrorSection({
    required IconData icon,
    required String message,
    required List<Widget> actions,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.error.withAlpha(25),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.error.withAlpha(80)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.error, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(children: actions),
        ],
      ),
    );
  }

  Widget _buildBottomSection() {
    // A gravação morreu no meio: o usuário decide o que fazer com o
    // trecho recuperado antes de qualquer outra coisa.
    if (_recordingError != null) {
      return _buildErrorSection(
        icon: Icons.mic_off_rounded,
        message: _recordingError!,
        actions: [
          Expanded(
            child: OutlinedButton(
              onPressed: _discardRecording,
              child: const Text('Descartar'),
            ),
          ),
          if (_pendingAudioPath != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _sendPartialRecording,
                icon: const Icon(Icons.upload_rounded, size: 18),
                label: const Text('Enviar o que foi gravado'),
              ),
            ),
          ],
        ],
      );
    }

    if (_uploadError != null) {
      return _buildErrorSection(
        icon: Icons.error_outline_rounded,
        message: _uploadError!,
        actions: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _uploadError = null),
              child: const Text('Descartar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _retryUpload,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar enviar novamente'),
            ),
          ),
        ],
      );
    }

    if (_isUploading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: _uploadProgress,
              backgroundColor: AppColors.border,
              valueColor:
                  const AlwaysStoppedAnimation(AppColors.primary),
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_uploadProgress * 100).toStringAsFixed(0)}% enviado',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) {
        final glowSize =
            _isRecording ? 12.0 + 8.0 * _pulseCtrl.value : 0.0;
        final btnColor =
            _isRecording ? AppColors.recording : AppColors.primary;

        return GestureDetector(
          onTap: _toggleRecording,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Anel pulsante
              if (_isRecording)
                Container(
                  width: 96 + glowSize * 2,
                  height: 96 + glowSize * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.recording.withAlpha(
                        (30 * _pulseCtrl.value).round()),
                    border: Border.all(
                      color: AppColors.recording.withAlpha(
                          (60 * _pulseCtrl.value).round()),
                      width: 1.5,
                    ),
                  ),
                ),
              // Botão principal
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _isRecording
                        ? [AppColors.recording, const Color(0xFFFF6B6B)]
                        : [AppColors.primary, AppColors.primaryLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: btnColor.withAlpha(
                          _isRecording ? 120 : 80),
                      blurRadius: _isRecording ? 28 : 20,
                      spreadRadius: _isRecording ? 2 : 0,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  _isRecording
                      ? Icons.stop_rounded
                      : Icons.mic_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Waveform Painter ───────────────────────────────────────────────────────

class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final bool active;
  final Color primaryColor;
  final Color secondaryColor;

  _WaveformPainter({
    required this.bars,
    required this.active,
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barSpacing = 3.0;
    final barWidth = (size.width - (bars.length - 1) * barSpacing) / bars.length;

    for (var i = 0; i < bars.length; i++) {
      final amp = active ? bars[i] : 0.04;
      final barH = math.max(amp * size.height, 4.0);
      final x = i * (barWidth + barSpacing);
      final y = (size.height - barH) / 2;

      final t = i / bars.length;
      final color = Color.lerp(primaryColor, secondaryColor, t)!;
      final alpha = active ? (0.3 + 0.7 * amp).clamp(0.0, 1.0) : 0.25;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barH),
          const Radius.circular(2),
        ),
        Paint()..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.bars != bars || old.active != active;
}
