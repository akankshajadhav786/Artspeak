import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/art_speak_repository.dart';
import '../models/session_record.dart';
import 'session_canvas_screen.dart';

class InterestCategoryOption {
  final String id;
  final String title;
  final String emoji;
  final Color baseColor;
  final Color softBg;
  final List<String> sampleImages;

  const InterestCategoryOption({
    required this.id,
    required this.title,
    required this.emoji,
    required this.baseColor,
    required this.softBg,
    required this.sampleImages,
  });
}

final List<InterestCategoryOption> kInterestCategories = [
  const InterestCategoryOption(
    id: 'animals',
    title: 'Animals',
    emoji: '🐶',
    baseColor: Color(0xFF3D5AFE),
    softBg: Color(0xFFEEF2FF),
    sampleImages: [
      'assets/stimulus/animals/P073.jpg',
      'assets/stimulus/animals/P074.jpg',
      'assets/stimulus/animals/P076.jpg',
      'assets/stimulus/animals/P078.jpg',
      'assets/stimulus/animals/P079.jpg',
      'assets/stimulus/animals/P083.jpg',
      'assets/stimulus/animals/P101.jpg',
      'assets/stimulus/animals/P122.jpg',
    ],
  ),
  const InterestCategoryOption(
    id: 'nature',
    title: 'Nature',
    emoji: '🌲',
    baseColor: Color(0xFF10B981),
    softBg: Color(0xFFECFDF5),
    sampleImages: [
      'assets/stimulus/nature/P044.jpg',
      'assets/stimulus/nature/P045.jpg',
      'assets/stimulus/nature/P055.jpg',
      'assets/stimulus/nature/P064.jpg',
      'assets/stimulus/nature/P067.jpg',
      'assets/stimulus/nature/P072.jpg',
      'assets/stimulus/nature/P117.jpg',
      'assets/stimulus/nature/P128.jpg',
    ],
  ),
  const InterestCategoryOption(
    id: 'objects',
    title: 'Objects',
    emoji: '🧸',
    baseColor: Color(0xFFF59E0B),
    softBg: Color(0xFFFFFBEB),
    sampleImages: [
      'assets/stimulus/objects/N002.jpg',
      'assets/stimulus/objects/N017.jpg',
      'assets/stimulus/objects/N028.jpg',
      'assets/stimulus/objects/N034.jpg',
      'assets/stimulus/objects/N077.jpg',
      'assets/stimulus/objects/N097.jpg',
      'assets/stimulus/objects/P104.jpg',
      'assets/stimulus/objects/P111.jpg',
    ],
  ),
  const InterestCategoryOption(
    id: 'people',
    title: 'People',
    emoji: '👶',
    baseColor: Color(0xFFEC4899),
    softBg: Color(0xFFFDF2F8),
    sampleImages: [
      'assets/stimulus/people/P004.jpg',
      'assets/stimulus/people/P010.jpg',
      'assets/stimulus/people/P012.jpg',
      'assets/stimulus/people/P014.jpg',
      'assets/stimulus/people/P017.jpg',
      'assets/stimulus/people/P025.jpg',
      'assets/stimulus/people/P062.jpg',
      'assets/stimulus/people/P090.jpg',
    ],
  ),
];

class InterestSelectionScreen extends StatefulWidget {
  final String childName;
  final String sessionId;
  final CameraController? cameraController;
  final bool isRecording;

  const InterestSelectionScreen({
    super.key,
    required this.childName,
    required this.sessionId,
    this.cameraController,
    this.isRecording = false,
  });

  @override
  State<InterestSelectionScreen> createState() => _InterestSelectionScreenState();
}

class _InterestSelectionScreenState extends State<InterestSelectionScreen> {
  InterestCategoryOption? _selectedCategory;
  String? _selectedImageAsset;
  String? _selectedImageId;
  int _secondsLeft = 10;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _onCategorySelected(InterestCategoryOption category) {
    final rand = Random();
    final pickedAsset = category.sampleImages[rand.nextInt(category.sampleImages.length)];
    final pickedId = pickedAsset.split('/').last.split('.').first;

    // Update database session with stimulus category
    artSpeakRepository.updateSessionStimulus(
      sessionId: widget.sessionId,
      stimulusCategory: category.id,
      stimulusImageId: pickedId,
    );

    setState(() {
      _selectedCategory = category;
      _selectedImageAsset = pickedAsset;
      _selectedImageId = pickedId;
      _secondsLeft = 10;
    });

    // Start the 10-second timer as soon as the user selects the box
    _startStimulusCountdown();
  }

  void _startStimulusCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        timer.cancel();
        _navigateToDrawing();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _navigateToDrawing() async {
    _countdownTimer?.cancel();
    final result = await Navigator.of(context).push<SessionRecord>(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) => SessionCanvasScreen(
          childName: widget.childName,
          sessionId: widget.sessionId,
          existingCameraController: widget.cameraController,
          stimulusCategory: _selectedCategory?.id,
          stimulusImageId: _selectedImageId,
          stimulusImageAsset: _selectedImageAsset,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primaryDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          children: [
            Text(
              "Choose Today's Theme",
              style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, color: AppColors.primaryDark, fontSize: 18),
            ),
            Text(
              "What makes ${widget.childName} smile?",
              style: GoogleFonts.nunito(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          if (widget.isRecording)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.alertRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.alertRed.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.alertRed, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('Camera Active', style: GoogleFonts.nunito(color: AppColors.alertRed, fontWeight: FontWeight.w700, fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Small Selection Boxes at the top (like Sun, House chips)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: kInterestCategories.map((cat) {
                    final isSelected = _selectedCategory?.id == cat.id;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: InkWell(
                        onTap: () => _onCategorySelected(cat),
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? cat.baseColor : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? cat.baseColor : AppColors.accentSoft,
                              width: isSelected ? 2.0 : 1.4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isSelected
                                    ? cat.baseColor.withValues(alpha: 0.3)
                                    : Colors.black.withValues(alpha: 0.03),
                                blurRadius: isSelected ? 8 : 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(cat.emoji, style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 8),
                              Text(
                                cat.title,
                                style: GoogleFonts.fredoka(
                                  color: isSelected ? Colors.white : AppColors.primaryDark,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 14),

              // The Big Box below that immediately displays the selected image + 10s timer
              Expanded(
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 820),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _selectedCategory != null
                          ? _selectedCategory!.baseColor.withValues(alpha: 0.4)
                          : AppColors.accentSoft,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _selectedCategory != null
                            ? _selectedCategory!.baseColor.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: _selectedCategory == null || _selectedImageAsset == null
                      ? _buildEmptyPromptBox()
                      : _buildStimulusDisplayBox(),
                ),
              ),

              const SizedBox(height: 12),

              // Bottom status bar & optional skip button
              if (_selectedCategory != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _navigateToDrawing,
                      icon: const Icon(Icons.brush_rounded, size: 18, color: AppColors.primary),
                      label: Text(
                        "Skip to drawing now",
                        style: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Initial placeholder in the big box before any small box is tapped.
  Widget _buildEmptyPromptBox() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: AppColors.accentSoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.touch_app_rounded, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 18),
          Text(
            "Tap a box above to view!",
            style: GoogleFonts.fredoka(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Select Animals, Nature, Objects, or People to show an image for 10 seconds",
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 13.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// The active big box showing the category image and the 10-second countdown timer.
  Widget _buildStimulusDisplayBox() {
    final cat = _selectedCategory!;
    final double progress = (10 - _secondsLeft) / 10.0;

    return Stack(
      children: [
        // Centered Stimulus Image
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              _selectedImageAsset!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(cat.emoji, style: const TextStyle(fontSize: 64)),
                    const SizedBox(height: 12),
                    Text(cat.title, style: GoogleFonts.fredoka(fontSize: 22, color: cat.baseColor)),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Top Header inside the big box with Timer and Theme
        Positioned(
          top: 10,
          left: 10,
          right: 10,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Category indicator tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(cat.emoji, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      cat.title,
                      style: GoogleFonts.fredoka(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),

              // 10s Countdown Circular Badge
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  shape: BoxShape.circle,
                  border: Border.all(color: cat.baseColor, width: 2.5),
                  boxShadow: [
                    BoxShadow(color: cat.baseColor.withValues(alpha: 0.35), blurRadius: 8),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  '$_secondsLeft',
                  style: GoogleFonts.fredoka(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
            ],
          ),
        ),

        // Bottom Progress Line & Observation Hint inside the big box
        Positioned(
          bottom: 10,
          left: 14,
          right: 14,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: Colors.black26,
                  valueColor: AlwaysStoppedAnimation<Color>(cat.baseColor),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "Look at this picture! Moving to drawing in ${_secondsLeft}s...",
                  style: GoogleFonts.nunito(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
