import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';
import '../models/participant.dart';
import '../services/participant_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../widgets/icon_btn.dart';
import '../widgets/participant_avatar.dart';
import '../widgets/voice_sample_sheet.dart';

/// Cadastro de participantes com biometria de voz, reutilizável entre
/// reuniões diferentes.
class ParticipantsScreen extends StatefulWidget {
  const ParticipantsScreen({super.key});

  @override
  State<ParticipantsScreen> createState() => _ParticipantsScreenState();
}

class _ParticipantsScreenState extends State<ParticipantsScreen> {
  final _service = ParticipantService();
  List<Participant> _participants = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _service.loadAll();
    if (!mounted) return;
    setState(() {
      _participants = list;
      _loading = false;
    });
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
              'Cadastro de Biometria da Voz',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Nome do participante',
                prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
              ),
            ),
            const SizedBox(height: 24),
            GradientButton(
              label: 'Cadastrar',
              icon: Icons.add_rounded,
              onPressed: () async {
                final name = ctrl.text.trim();
                if (name.isEmpty) return;
                final participant = Participant(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  name: name,
                  colorIndex:
                      _participants.length % AppColors.participantColors.length,
                );
                await _service.add(participant);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                await _load();
                if (!mounted) return;
                _recordVoiceSample(participant);
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
      builder: (ctx) => VoiceSampleSheet(
        participant: participant,
        onSaved: (path) async {
          final updated = participant.copyWith(voiceSamplePath: path);
          await _service.update(updated);
          await _load();
          try {
            await _service.syncVoiceSample(updated);
          } catch (_) {
            if (mounted) {
              _showSnack(
                'Amostra salva localmente, mas não foi possível sincronizar com o servidor agora.',
              );
            }
          } finally {
            await _load();
          }
        },
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _removeParticipant(Participant participant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Remover participante?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'A biometria de voz de ${participant.name} será apagada.',
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
      final remoteDeleted = await _service.remove(participant.id);
      await _load();
      if (!remoteDeleted && mounted) {
        _showSnack(
          'Participante removido do aparelho, mas o perfil de voz no servidor não pôde ser excluído agora.',
        );
      }
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
              _buildAppBar(),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary))
                    : _buildBody(),
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
          Expanded(
            child: Text(
              'Participantes',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
          ),
          GestureDetector(
            onTap: _addParticipant,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 4),
                  Text(
                    'Cadastrar',
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
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildBody() {
    if (_participants.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: GlassCard(
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
                  child: const Icon(Icons.group_add_rounded,
                      color: AppColors.primary, size: 30),
                ),
                const SizedBox(height: 16),
                Text(
                  'Nenhum participante cadastrado',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Cadastre pessoas com amostra de voz\npara reconhecê-las nas reuniões.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      itemCount: _participants.length,
      itemBuilder: (_, i) {
        final p = _participants[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                ParticipantAvatar(participant: p, size: 46, showCheckmark: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        !p.hasVoiceSample
                            ? 'Sem amostra de voz'
                            : p.voiceProfileSynced
                                ? '✓ Amostra sincronizada'
                                : 'Amostra gravada — não sincronizada',
                        style: GoogleFonts.inter(
                          color: !p.hasVoiceSample
                              ? AppColors.textSecondary
                              : p.voiceProfileSynced
                                  ? AppColors.success
                                  : const Color(0xFFFBBF24),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconBtn(
                      icon: p.hasVoiceSample
                          ? Icons.mic_rounded
                          : Icons.mic_none_rounded,
                      color: p.hasVoiceSample
                          ? AppColors.success
                          : AppColors.primary,
                      onTap: () => _recordVoiceSample(p),
                      tooltip: p.hasVoiceSample
                          ? 'Regravar amostra'
                          : 'Gravar amostra de voz',
                    ),
                    const SizedBox(width: 4),
                    IconBtn(
                      icon: Icons.delete_outline_rounded,
                      color: AppColors.error,
                      onTap: () => _removeParticipant(p),
                      tooltip: 'Remover',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ).animate(delay: (i * 60).ms).fadeIn().slideX(begin: 0.15);
      },
    );
  }
}
