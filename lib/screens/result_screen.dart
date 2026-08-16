import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_colors.dart';
import '../models/meeting_result.dart';
import '../models/participant.dart';
import '../widgets/glass_card.dart';

class ResultScreen extends StatefulWidget {
  final MeetingResult result;

  /// Não usado para resolver falantes (isso vem pronto do backend em
  /// `result`). Reservado para uma futura feature de participantes
  /// cadastrados-mas-não-detectados na reunião.
  final List<Participant> participants;

  const ResultScreen({
    super.key,
    required this.result,
    this.participants = const [],
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // O backend já resolve falante -> participante (biometria de voz). O
  // cliente NUNCA deve inferir identidade pela posição do participante na
  // lista de seleção da reunião — só usa o que veio no resultado.
  String _segmentLabel(TranscriptSegment s) => s.speaker ?? s.cluster;

  String _questionLabel(Question q) =>
      q.speaker ?? (q.type == QuestionType.implicit ? 'Pergunta implícita' : 'Não identificado');

  static const _neutralColor = AppColors.textMuted;

  // Cor estável por identidade (participantId, com fallback para o cluster
  // bruto), nunca por posição na lista — a mesma pessoa mantém a mesma cor
  // entre as abas de Transcrição e Perguntas.
  Color _colorForKey(String key) =>
      AppColors.participantColors[key.hashCode.abs() % AppColors.participantColors.length];

  Color _segmentColor(TranscriptSegment s) =>
      _colorForKey(s.participantId ?? s.cluster);

  Color _questionColor(Question q) {
    // Perguntas implícitas nunca têm participant_id/speaker por contrato —
    // usar cor neutra em vez de "hashar" o texto, que daria uma cor sem
    // nenhum significado (e teria o mesmo problema que a regra de
    // biometria já proíbe para nomes: inventar identidade).
    if (q.type == QuestionType.implicit) return _neutralColor;
    final key = q.participantId ?? q.speaker;
    if (key == null) return _neutralColor;
    return _colorForKey(key);
  }

  String _fmt(double seconds) {
    final d = Duration(seconds: seconds.round());
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> _sendQuestionsByEmail() async {
    final formKey = GlobalKey<FormState>();
    final emailCtrl = TextEditingController();
    final recipient = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Enviar perguntas por e-mail',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: emailCtrl,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
            decoration: const InputDecoration(
              labelText: 'E-mail do destinatário',
              prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
            ),
            validator: (v) => (v == null || !_emailRegex.hasMatch(v.trim()))
                ? 'Informe um e-mail válido'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              FocusScope.of(ctx).unfocus();
              Navigator.pop(ctx);
            },
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              FocusScope.of(ctx).unfocus();
              Navigator.pop(ctx, emailCtrl.text.trim());
            },
            child: const Text('Enviar',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    emailCtrl.dispose();
    if (recipient == null || recipient.isEmpty) return;

    final buffer = StringBuffer();
    for (var i = 0; i < widget.result.questions.length; i++) {
      final q = widget.result.questions[i];
      final timeLabel = q.time != null ? _fmt(q.time!) : '—';
      buffer.writeln('${i + 1}. [${_questionLabel(q)} · $timeLabel]');
      buffer.writeln(q.text);
      buffer.writeln();
    }

    // Uri(queryParameters: ...) usa a codificação de formulário
    // (application/x-www-form-urlencoded), que representa espaço como "+".
    // Clientes de e-mail interpretam mailto: com percent-encoding (RFC 6068),
    // então "+" aparece como caractere literal em vez de espaço. Por isso o
    // corpo é montado manualmente com Uri.encodeComponent (usa %20).
    final subject = Uri.encodeComponent('Perguntas da reunião');
    final body = Uri.encodeComponent(buffer.toString().trim());
    final uri = Uri.parse('mailto:$recipient?subject=$subject&body=$body');

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('launch failed');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o app de e-mail.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
              _buildHeader(context),
              if (widget.result.isDemo) _buildDemoBanner(),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildTranscript(),
                    _buildQuestions(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 24, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.home_rounded,
                color: AppColors.textPrimary, size: 22),
            onPressed: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resultado',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
                Text(
                  '${widget.result.segments.length} segmentos · '
                  '${widget.result.questions.length} perguntas',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                // Exibido para o usuário poder citar o job_id ao reportar
                // um problema de suporte.
                Text(
                  'Job ID: ${widget.result.jobId}',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.robotoMono(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          // Badge de conclusão
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.success.withAlpha(30),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.success.withAlpha(80)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_rounded,
                    color: AppColors.success, size: 14),
                const SizedBox(width: 4),
                Text(
                  'Concluído',
                  style: GoogleFonts.inter(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.forward_to_inbox_rounded,
                color: AppColors.textPrimary, size: 20),
            tooltip: 'Enviar perguntas por e-mail',
            onPressed: widget.result.questions.isEmpty
                ? null
                : _sendQuestionsByEmail,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildDemoBanner() {
    const color = Color(0xFFF59E0B);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: color, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Conteúdo de demonstração — servidor indisponível',
                style: GoogleFonts.inter(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: TabBar(
          controller: _tabCtrl,
          indicator: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: GoogleFonts.inter(
              fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            Tab(text: 'Transcrição (${widget.result.segments.length})'),
            Tab(text: 'Perguntas (${widget.result.questions.length})'),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscript() {
    if (widget.result.segments.isEmpty) {
      return _emptyState(
        icon: Icons.text_fields_rounded,
        message: 'Nenhuma transcrição disponível.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: widget.result.segments.length,
      itemBuilder: (_, i) {
        final seg = widget.result.segments[i];
        final label = _segmentLabel(seg);
        final color = _segmentColor(seg);
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            borderColor: color.withAlpha(60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color.withAlpha(30),
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withAlpha(100)),
                      ),
                      child: Center(
                        child: Text(
                          label[0].toUpperCase(),
                          style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w700,
                              fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_fmt(seg.start)} → ${_fmt(seg.end)}',
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  seg.text,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ).animate(delay: (i * 40).ms).fadeIn().slideY(begin: 0.15);
      },
    );
  }

  Widget _buildQuestions() {
    if (widget.result.questions.isEmpty) {
      return _emptyState(
        icon: Icons.help_outline_rounded,
        message: 'Nenhuma pergunta extraída.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: widget.result.questions.length,
      itemBuilder: (_, i) {
        final q = widget.result.questions[i];
        final label = _questionLabel(q);
        final color = _questionColor(q);
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            borderColor: const Color(0xFFF472B6).withAlpha(60),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF472B6).withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Color(0xFFF472B6),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        q.text,
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            q.time != null ? '$label · ${_fmt(q.time!)}' : label,
                            style: GoogleFonts.inter(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ).animate(delay: (i * 50).ms).fadeIn().slideY(begin: 0.15);
      },
    );
  }

  Widget _emptyState({required IconData icon, required String message}) {
    return Center(
      child: GlassCard(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 40),
            const SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.inter(
                  color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
