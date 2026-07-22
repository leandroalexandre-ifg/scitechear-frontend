import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';
import '../models/meeting.dart';
import '../models/participant.dart';
import '../services/auth_service.dart';
import '../services/meeting_service.dart';
import '../services/offline_service.dart';
import '../services/status_service.dart';
import '../widgets/glass_card.dart';
import 'auth_screen.dart';
import 'meeting_setup_screen.dart';
import 'participants_screen.dart';
import 'result_screen.dart';

class HomeScreen extends StatefulWidget {
  final AuthService authService;
  const HomeScreen({super.key, required this.authService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _history = MeetingHistoryService();
  final _status = StatusService();
  final _resultCache = LocalResultCache();
  List<Meeting> _meetings = [];
  bool _loading = true;
  String? _openingMeetingId;

  @override
  void initState() {
    super.initState();
    _loadMeetings();
  }

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  Future<void> _loadMeetings() async {
    final list = await _history.loadAll();
    if (!mounted) return;
    setState(() {
      _meetings = list;
      _loading = false;
    });
  }

  Future<void> _openMeeting(Meeting meeting) async {
    setState(() => _openingMeetingId = meeting.id);
    try {
      // Prioriza o resultado já salvo localmente — evita depender da rede
      // para reabrir reuniões e funciona mesmo com o backend indisponível.
      var result = await _resultCache.load(meeting.jobId);
      if (result == null) {
        try {
          result = await _status.fetchResult(meeting.jobId);
          await _resultCache.save(meeting.jobId, result);
        } catch (_) {
          result = generateDemoResult(
            jobId: meeting.jobId,
            participantNames: meeting.participantNames,
          );
          await _resultCache.save(meeting.jobId, result);
        }
      }
      if (!mounted) return;
      final participants = meeting.participantNames
          .asMap()
          .entries
          .map((e) => Participant(
                id: e.key.toString(),
                name: e.value,
                colorIndex: e.key,
              ))
          .toList();
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(result: result!, participants: participants),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingMeetingId = null);
    }
  }

  Future<void> _removeMeeting(Meeting meeting) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Remover reunião?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '"${meeting.title}" será removida do seu histórico local.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _history.remove(meeting.id);
      await _loadMeetings();
    }
  }

  Future<void> _renameMeeting(Meeting meeting) async {
    final ctrl = TextEditingController(text: meeting.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Renomear reunião',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          decoration: const InputDecoration(
            labelText: 'Título',
            prefixIcon: Icon(Icons.title_rounded, size: 20),
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
              final trimmed = ctrl.text.trim();
              if (trimmed.isEmpty) return;
              FocusScope.of(ctx).unfocus();
              Navigator.pop(ctx, trimmed);
            },
            child: const Text('Salvar',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newTitle != null && newTitle.isNotEmpty && newTitle != meeting.title) {
      await _history.update(meeting.copyWith(title: newTitle));
      await _loadMeetings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.authService.currentUser!;
    final firstName = user.name.split(' ').first;

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
          child: RefreshIndicator(
            onRefresh: _loadMeetings,
            color: AppColors.primary,
            backgroundColor: AppColors.surfaceHigh,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: _buildHeader(context, firstName),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                    child: _buildNewMeetingCard(context),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 36, 24, 16),
                    child: Row(
                      children: [
                        Text(
                          'Reuniões recentes',
                          style: GoogleFonts.inter(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  )
                else if (_meetings.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    sliver: SliverList.builder(
                      itemCount: _meetings.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildMeetingCard(_meetings[i], i),
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

  Widget _buildHeader(BuildContext context, String firstName) {
    final user = widget.authService.currentUser!;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Olá, $firstName',
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  if (user.isAdmin) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFFF59E0B).withAlpha(80)),
                      ),
                      child: Text(
                        'ADMIN',
                        style: GoogleFonts.inter(
                          color: const Color(0xFFF59E0B),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Suas Reuniões',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ParticipantsScreen()),
          ),
          child: Container(
            width: 42,
            height: 42,
            margin: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.groups_rounded,
              color: AppColors.textSecondary,
              size: 19,
            ),
          ),
        ),
        GestureDetector(
          onTap: () => _logout(context),
          child: Container(
            width: 42,
            height: 42,
            margin: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.logout_rounded,
              color: AppColors.textSecondary,
              size: 18,
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.2);
  }

  Widget _buildNewMeetingCard(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MeetingSetupScreen(authService: widget.authService),
          ),
        );
        _loadMeetings();
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFF22D3EE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withAlpha(100),
              blurRadius: 36,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nova Reunião',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Grave, transcreva e extraia\nperguntas automaticamente.',
                    style: GoogleFonts.inter(
                      color: Colors.white.withAlpha(180),
                      fontSize: 13,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(50),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Começar agora',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(35),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withAlpha(60)),
              ),
              child: const Icon(Icons.mic_rounded,
                  color: Colors.white, size: 34),
            ),
          ],
        ),
      ),
    ).animate(delay: 100.ms).fadeIn(duration: 500.ms).slideY(begin: 0.25);
  }

  Widget _buildMeetingCard(Meeting meeting, int index) {
    final opening = _openingMeetingId == meeting.id;
    return GlassCard(
      onTap: opening ? null : () => _openMeeting(meeting),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.description_rounded,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meeting.title,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meeting.participantNames.isEmpty
                      ? _fmtDate(meeting.createdAt)
                      : '${_fmtDate(meeting.createdAt)} · ${meeting.participantNames.join(', ')}',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (opening)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            )
          else
            Row(
              children: [
                GestureDetector(
                  onTap: () => _renameMeeting(meeting),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_outlined,
                        color: AppColors.primary, size: 16),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _removeMeeting(meeting),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.error.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.error, size: 17),
                  ),
                ),
              ],
            ),
        ],
      ),
    ).animate(delay: (index * 60).ms).fadeIn().slideX(begin: 0.1);
  }

  String _fmtDate(DateTime d) {
    final now = DateTime.now();
    final sameDay =
        d.year == now.year && d.month == now.month && d.day == now.day;
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (sameDay) return 'Hoje, $time';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} · $time';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GlassCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.history_rounded,
                        color: AppColors.primary, size: 30),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma reunião ainda',
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Suas reuniões gravadas\naparecerão aqui.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: 250.ms).fadeIn(duration: 500.ms);
  }

  Future<void> _logout(BuildContext context) async {
    await widget.authService.logout();
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AuthScreen(authService: widget.authService),
      ),
    );
  }
}
