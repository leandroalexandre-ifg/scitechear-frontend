import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';
import '../models/meeting_result.dart';
import '../models/participant.dart';
import '../widgets/glass_card.dart';

class ResultScreen extends StatefulWidget {
  final MeetingResult result;
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

  // Mapeia "SPEAKER_00" → nome do participante, se disponível.
  String _speakerLabel(String rawSpeaker) {
    final index = int.tryParse(
      RegExp(r'\d+').firstMatch(rawSpeaker)?.group(0) ?? '',
    );
    if (index != null && index < widget.participants.length) {
      return widget.participants[index].name;
    }
    return rawSpeaker;
  }

  Color _speakerColor(String rawSpeaker) {
    final index = int.tryParse(
      RegExp(r'\d+').firstMatch(rawSpeaker)?.group(0) ?? '',
    );
    final i = index ?? rawSpeaker.hashCode.abs();
    return AppColors.participantColors[i % AppColors.participantColors.length];
  }

  String _fmt(double seconds) {
    final d = Duration(seconds: seconds.round());
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
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
        ],
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
        final label = _speakerLabel(seg.speaker);
        final color = _speakerColor(seg.speaker);
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
        final label = _speakerLabel(q.speaker);
        final color = _speakerColor(q.speaker);
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
                            '$label · ${_fmt(q.time)}',
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
