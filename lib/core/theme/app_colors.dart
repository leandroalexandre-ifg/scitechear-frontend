import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const background = Color(0xFF080B14);
  static const surface = Color(0xFF0F1729);
  static const surfaceHigh = Color(0xFF1A2340);
  static const border = Color(0xFF1E2D4A);

  static const primary = Color(0xFF6366F1);
  static const primaryLight = Color(0xFF818CF8);
  static const secondary = Color(0xFF22D3EE);

  static const success = Color(0xFF34D399);
  static const error = Color(0xFFFC8181);
  static const recording = Color(0xFFFF4757);

  static const textPrimary = Color(0xFFF1F5F9);
  static const textSecondary = Color(0xFF64748B);
  static const textMuted = Color(0xFF334155);

  // Paleta de cores para participantes
  static const participantColors = [
    Color(0xFF6366F1),
    Color(0xFF22D3EE),
    Color(0xFFF472B6),
    Color(0xFF34D399),
    Color(0xFFFBBF24),
    Color(0xFFF97316),
    Color(0xFFA78BFA),
    Color(0xFF2DD4BF),
  ];

  static const primaryGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const heroGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFF22D3EE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
