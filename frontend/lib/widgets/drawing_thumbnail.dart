import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Renders the child's drawing prompt and strokes for caregiver and therapist review.
class DrawingThumbnail extends StatelessWidget {
  final String? drawingReference;
  final List<Map<String, dynamic>>? strokes;
  final int strokeCount;
  final double height;
  final bool showStrokes;

  const DrawingThumbnail({
    super.key,
    this.drawingReference,
    this.strokes,
    this.strokeCount = 0,
    this.height = 180,
    this.showStrokes = false,
  });

  @override
  Widget build(BuildContext context) {
    final ref = (drawingReference ?? 'sun').toLowerCase();
    final emoji = _emojiForRef(ref);
    final label = _labelForRef(ref);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFFDFBF7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
      ),
      child: Stack(
        children: [
          // Reference outline watermark / prompt (crisper if strokes are hidden)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CustomPaint(
                painter: _SimpleRefOutlinePainter(ref, highContrast: !showStrokes),
              ),
            ),
          ),

          // User drawn strokes if present and enabled
          if (showStrokes && strokes != null && strokes!.isNotEmpty)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: CustomPaint(
                  painter: _StrokeDataPainter(strokes!),
                ),
              ),
            ),

          // Badge with reference name
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(
                    'Drawing: $label',
                    style: GoogleFonts.fredoka(color: AppColors.primaryDark, fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),

          // Bottom right badge: target prompt indicator
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: showStrokes ? AppColors.accentSoft : const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                showStrokes ? '$strokeCount strokes' : 'Target Object',
                style: GoogleFonts.nunito(
                  color: showStrokes ? AppColors.primary : const Color(0xFF0369A1),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _emojiForRef(String ref) {
    switch (ref) {
      case 'house':
        return '🏠';
      case 'star':
        return '⭐';
      case 'flower':
        return '🌸';
      case 'tree':
        return '🌳';
      case 'boat':
        return '⛵';
      case 'butterfly':
        return '🦋';
      case 'sun':
      default:
        return '☀️';
    }
  }

  String _labelForRef(String ref) {
    if (ref.isEmpty) return 'Sun';
    return ref[0].toUpperCase() + ref.substring(1);
  }
}

class _StrokeDataPainter extends CustomPainter {
  final List<Map<String, dynamic>> strokes;
  _StrokeDataPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final rawPoints = s['points'] as List?;
      if (rawPoints == null || rawPoints.length < 2) continue;
      final colorVal = s['color'] as int? ?? 0xFF3D5AFE;
      final width = (s['width'] as num?)?.toDouble() ?? 4.0;
      final paint = Paint()
        ..color = Color(colorVal)
        ..strokeWidth = width.clamp(2.0, 8.0)
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (var i = 0; i < rawPoints.length - 1; i++) {
        final p1 = rawPoints[i] as List;
        final p2 = rawPoints[i + 1] as List;
        // Normalize points to target size if canvas bounds differ
        final offset1 = Offset((p1[0] as num).toDouble() % size.width, (p1[1] as num).toDouble() % size.height);
        final offset2 = Offset((p2[0] as num).toDouble() % size.width, (p2[1] as num).toDouble() % size.height);
        canvas.drawLine(offset1, offset2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _SimpleRefOutlinePainter extends CustomPainter {
  final String ref;
  final bool highContrast;

  _SimpleRefOutlinePainter(this.ref, {this.highContrast = false});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeColor = highContrast ? const Color(0xFF1E293B) : const Color(0xFF64748B).withValues(alpha: 0.35);
    final paint = Paint()
      ..color = strokeColor
      ..strokeWidth = highContrast ? 4.5 : 3.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    switch (ref) {
      case 'house':
        final path = Path()
          ..moveTo(w * 0.2, h * 0.9)
          ..lineTo(w * 0.2, h * 0.5)
          ..lineTo(w * 0.5, h * 0.2)
          ..lineTo(w * 0.8, h * 0.5)
          ..lineTo(w * 0.8, h * 0.9)
          ..close();
        canvas.drawPath(path, paint);
        canvas.drawRect(Rect.fromLTWH(w * 0.42, h * 0.6, w * 0.16, h * 0.3), paint);
        canvas.drawRect(Rect.fromLTWH(w * 0.25, h * 0.6, w * 0.12, h * 0.12), paint);
        break;
      case 'star':
        final path = Path();
        const points = 5;
        final outerR = min(w, h) * 0.38;
        final innerR = outerR * 0.45;
        final cx = w / 2, cy = h / 2;
        for (int i = 0; i < points * 2; i++) {
          final r = i.isEven ? outerR : innerR;
          final angle = (pi / points) * i - pi / 2;
          final x = cx + r * cos(angle);
          final y = cy + r * sin(angle);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
        break;
      case 'flower':
        final cx = w / 2, cy = h / 2;
        final petalR = min(w, h) * 0.14;
        for (int i = 0; i < 6; i++) {
          final angle = (pi / 3) * i;
          final petalCenter = Offset(cx + petalR * 1.1 * cos(angle), cy + petalR * 1.1 * sin(angle));
          canvas.drawCircle(petalCenter, petalR, paint);
        }
        canvas.drawCircle(Offset(cx, cy), petalR * 0.7, paint);
        canvas.drawLine(Offset(cx, cy + petalR * 1.6), Offset(cx, h * 0.9), paint);
        break;
      case 'tree':
        canvas.drawRect(Rect.fromLTWH(w * 0.44, h * 0.55, w * 0.12, h * 0.35), paint);
        final foliagePath = Path()
          ..moveTo(w * 0.25, h * 0.55)
          ..quadraticBezierTo(w * 0.12, h * 0.45, w * 0.22, h * 0.32)
          ..quadraticBezierTo(w * 0.18, h * 0.16, w * 0.38, h * 0.16)
          ..quadraticBezierTo(w * 0.5, h * 0.06, w * 0.62, h * 0.16)
          ..quadraticBezierTo(w * 0.82, h * 0.16, w * 0.78, h * 0.32)
          ..quadraticBezierTo(w * 0.88, h * 0.45, w * 0.75, h * 0.55)
          ..close();
        canvas.drawPath(foliagePath, paint);
        break;
      case 'boat':
        final hullPath = Path()
          ..moveTo(w * 0.2, h * 0.72)
          ..lineTo(w * 0.8, h * 0.72)
          ..lineTo(w * 0.7, h * 0.9)
          ..lineTo(w * 0.3, h * 0.9)
          ..close();
        canvas.drawPath(hullPath, paint);
        canvas.drawLine(Offset(w * 0.48, h * 0.2), Offset(w * 0.48, h * 0.72), paint);
        final sailPath = Path()
          ..moveTo(w * 0.5, h * 0.22)
          ..lineTo(w * 0.76, h * 0.65)
          ..lineTo(w * 0.5, h * 0.65)
          ..close();
        canvas.drawPath(sailPath, paint);
        break;
      case 'butterfly':
        final cx = w / 2, cy = h / 2;
        canvas.drawLine(Offset(cx, h * 0.2), Offset(cx, h * 0.85), paint);
        final leftWingTop = Path()
          ..moveTo(cx, cy * 0.75)
          ..quadraticBezierTo(w * 0.1, h * 0.15, w * 0.15, h * 0.45)
          ..quadraticBezierTo(w * 0.2, h * 0.65, cx, cy * 0.95)
          ..close();
        final rightWingTop = Path()
          ..moveTo(cx, cy * 0.75)
          ..quadraticBezierTo(w * 0.9, h * 0.15, w * 0.85, h * 0.45)
          ..quadraticBezierTo(w * 0.8, h * 0.65, cx, cy * 0.95)
          ..close();
        canvas.drawPath(leftWingTop, paint);
        canvas.drawPath(rightWingTop, paint);
        break;
      case 'sun':
      default:
        final cx = w / 2, cy = h / 2;
        final r = min(w, h) * 0.2;
        canvas.drawCircle(Offset(cx, cy), r, paint);
        for (int i = 0; i < 8; i++) {
          final angle = (pi / 4) * i;
          final start = Offset(cx + r * 1.25 * cos(angle), cy + r * 1.25 * sin(angle));
          final end = Offset(cx + r * 1.65 * cos(angle), cy + r * 1.65 * sin(angle));
          canvas.drawLine(start, end, paint);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
