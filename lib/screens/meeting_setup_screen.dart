import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';
import '../models/participant.dart';
import '../services/auth_service.dart';
import '../services/participant_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../widgets/icon_btn.dart';
import '../widgets/participant_avatar.dart';
import 'participants_screen.dart';
import 'recording_screen.dart';

class MeetingSetupScreen extends StatefulWidget {
  final AuthService authService;
  const MeetingSetupScreen({super.key, required this.authService});

  @override
  State<MeetingSetupScreen> createState() => _MeetingSetupScreenState();
}

class _MeetingSetupScreenState extends State<MeetingSetupScreen> {
  final _titleCtrl = TextEditingController();
  final _participantService = ParticipantService();
  final List<Participant> _participants = [];

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickParticipants() async {
    final registered = await _participantService.loadAll();
    if (!mounted) return;

    if (registered.isEmpty) {
      final goRegister = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Nenhum participante cadastrado',
              style: TextStyle(color: AppColors.textPrimary)),
          content: const Text(
            'Cadastre participantes com amostra de voz antes de adicioná-los a uma reunião.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cadastrar agora'),
            ),
          ],
        ),
      );
      if (goRegister == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ParticipantsScreen()),
        );
      }
      return;
    }

    final selectedIds = _participants.map((p) => p.id).toSet();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 24, right: 24, top: 28,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selecionar participantes',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.4),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: registered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final p = registered[i];
                      final selected = selectedIds.contains(p.id);
                      return GlassCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        borderColor: selected
                            ? AppColors.primary.withAlpha(150)
                            : null,
                        onTap: () {
                          setSheetState(() {
                            if (selected) {
                              selectedIds.remove(p.id);
                            } else {
                              selectedIds.add(p.id);
                            }
                          });
                        },
                        child: Row(
                          children: [
                            ParticipantAvatar(participant: p, size: 38),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                p.name,
                                style: GoogleFonts.inter(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.textMuted,
                              size: 22,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                GradientButton(
                  label: 'Concluir',
                  icon: Icons.check_rounded,
                  onPressed: () {
                    setState(() {
                      _participants
                        ..clear()
                        ..addAll(
                            registered.where((p) => selectedIds.contains(p.id)));
                    });
                    Navigator.pop(ctx);
                  },
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ParticipantsScreen()),
                    );
                    if (mounted) _pickParticipants();
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded,
                      color: AppColors.textSecondary, size: 18),
                  label: const Text('Cadastrar novo participante',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              ],
            ),
          );
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
                    'Selecione quem participou desta reunião.',
                    style: GoogleFonts.inter(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _pickParticipants,
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
  final VoidCallback onRemove;

  const _ParticipantCard({
    required this.participant,
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
          IconBtn(
            icon: Icons.close_rounded,
            color: AppColors.error,
            onTap: onRemove,
            tooltip: 'Remover da reunião',
          ),
        ],
      ),
    );
  }
}
