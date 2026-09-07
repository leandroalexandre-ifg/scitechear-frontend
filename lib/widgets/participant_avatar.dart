import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../models/participant.dart';

class ParticipantAvatar extends StatelessWidget {
  final Participant participant;
  final double size;
  final bool showCheckmark;

  const ParticipantAvatar({
    super.key,
    required this.participant,
    this.size = 40,
    this.showCheckmark = false,
  });

  Color get _color =>
      AppColors.participantColors[
          participant.colorIndex % AppColors.participantColors.length];

  @override
  Widget build(BuildContext context) {
    final initials = participant.name.isNotEmpty
        ? participant.name.trim().split(' ').take(2).map((w) => w[0]).join()
        : '?';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _color.withAlpha(40),
            shape: BoxShape.circle,
            border: Border.all(color: _color, width: 2),
          ),
          child: Center(
            child: Text(
              initials.toUpperCase(),
              style: TextStyle(
                color: _color,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.32,
              ),
            ),
          ),
        ),
        if (showCheckmark && participant.hasVoiceProfile)
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: size * 0.38,
              height: size * 0.38,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.background, width: 1.5),
              ),
              child: Icon(
                Icons.mic,
                color: Colors.white,
                size: size * 0.22,
              ),
            ),
          ),
      ],
    );
  }
}
