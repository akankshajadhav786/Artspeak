import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/child_profile.dart';
import '../models/session_record.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'interest_selection_screen.dart';
import 'session_canvas_screen.dart';
import '../services/art_speak_repository.dart';
import '../widgets/drawing_thumbnail.dart';
import '../utils/app_date_time.dart';
import 'child_details_screen.dart';
import 'welcome_screen.dart';
import 'patient_report_screen.dart';

class CaregiverDashboardScreen extends StatefulWidget {
  final ChildProfile initialProfile;
  final List<ChildProfile>? allProfiles;
  const CaregiverDashboardScreen({super.key, required this.initialProfile, this.allProfiles});

  @override
  State<CaregiverDashboardScreen> createState() => _CaregiverDashboardScreenState();
}

class _CaregiverDashboardScreenState extends State<CaregiverDashboardScreen> {
  late List<ChildProfile> _profiles;
  int _activeIndex = 0;
  bool _loadingSessions = false;

  ChildProfile get _active => _profiles.isNotEmpty && _activeIndex < _profiles.length
      ? _profiles[_activeIndex]
      : widget.initialProfile;

  @override
  void initState() {
    super.initState();
    _profiles = widget.allProfiles != null && widget.allProfiles!.isNotEmpty
        ? List.from(widget.allProfiles!)
        : [widget.initialProfile];
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _loadingSessions = true);
    try {
      final children = await artSpeakRepository.loadCaregiverChildren();
      if (mounted && children.isNotEmpty) {
        setState(() {
          _profiles = children;
          final activeId = widget.initialProfile.id;
          final matchIdx = _profiles.indexWhere((c) => c.id == activeId);
          if (matchIdx != -1) {
            _activeIndex = matchIdx;
          } else if (_activeIndex >= _profiles.length) {
            _activeIndex = 0;
          }
          _loadingSessions = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('Notice loading all data: $e');
    }
    await _loadChildSessions();
  }

  Future<void> _loadChildSessions() async {
    final childId = _active.id;
    if (childId == null) {
      if (mounted) setState(() => _loadingSessions = false);
      return;
    }
    setState(() => _loadingSessions = true);
    try {
      final sessions = await artSpeakRepository.loadChildSessions(childId);
      if (mounted) {
        setState(() {
          _active.sessions
            ..clear()
            ..addAll(sessions);
          _loadingSessions = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading child sessions: $e');
      if (mounted) setState(() => _loadingSessions = false);
    }
  }

  Future<void> _startSessionFlow() async {
    final childId = _active.id;
    if (childId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This child is not synced yet.')));
      return;
    }

    // 1. Immediately request camera permission and initialize recording so that
    // both stimulus-viewing reactions (10s) and drawing reactions are captured.
    CameraController? controller;
    bool isRecording = false;

    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        final cam = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );
        final camController = CameraController(cam, ResolutionPreset.medium, enableAudio: false);
        await camController.initialize();
        await camController.startVideoRecording();
        controller = camController;
        isRecording = true;
      }
    } catch (camError) {
      debugPrint('Camera permission/init status: $camError');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera notice: $camError. Proceeding with session.'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }

    try {
      final sessionId = await artSpeakRepository.createSession(childId: childId, durationSeconds: kSessionSeconds);
      if (!mounted) {
        await controller?.dispose();
        return;
      }

      // 2. Navigate to Interest Selection Screen (10s picture presentation before drawing)
      await Navigator.of(context).push<SessionRecord>(
        MaterialPageRoute(
          builder: (_) => InterestSelectionScreen(
            childName: _active.name,
            sessionId: sessionId,
            cameraController: controller,
            isRecording: isRecording,
          ),
        ),
      );

      // Re-fetch all sessions from Supabase to guarantee that the newly synthesized AI report and counts are immediately updated
      await _loadChildSessions();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session completed & report generated!'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (error) {
      await controller?.dispose();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      appBar: const AppHeader(subtitle: 'Caregiver Dashboard'),
      bottomNavigationBar: AppFooter(
        onLogout: () async {
          await artSpeakRepository.signOut();
          if (context.mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const WelcomeScreen()),
              (r) => false,
            );
          }
        },
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...List.generate(_profiles.length, (idx) {
                    final p = _profiles[idx];
                    final isSel = idx == _activeIndex;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 12),
                      child: ChoiceChip(
                        label: Text(p.name, style: GoogleFonts.fredoka(fontWeight: FontWeight.w600)),
                        selected: isSel,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: isSel ? Colors.white : AppColors.primaryDark),
                        onSelected: (_) {
                          setState(() => _activeIndex = idx);
                          _loadChildSessions();
                        },
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 12),
                    child: ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
                      label: Text('Add Child', style: GoogleFonts.fredoka(color: AppColors.primary, fontWeight: FontWeight.w600)),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      onPressed: () async {
                        final newProfile = await Navigator.of(context).push<ChildProfile>(
                          MaterialPageRoute(builder: (_) => const ChildDetailsScreen(isFirstProfile: false)),
                        );
                        if (newProfile != null && mounted) {
                          setState(() {
                            _profiles.add(newProfile);
                            _activeIndex = _profiles.length - 1;
                          });
                          _loadChildSessions();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(gradient: AppGradients.primaryCard, borderRadius: BorderRadius.circular(22)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ACTIVE CHILD PROFILE',
                      style: GoogleFonts.nunito(color: Colors.white70, fontSize: 12, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_active.name,
                          style: GoogleFonts.fredoka(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                        child: const Icon(Icons.palette_rounded, color: Colors.white, size: 26),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Age ${_active.age} · ${_active.gender.label} · ${_active.condition ?? 'Not specified'}',
                    style: GoogleFonts.nunito(color: Colors.white.withOpacity(0.85), fontSize: 14),
                  ),
                  if (_active.hobbies != null || _active.knownTriggers != null || _active.calmingActivities != null) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_active.hobbies != null) _InfoPill(icon: Icons.celebration_rounded, text: _active.hobbies!),
                        if (_active.knownTriggers != null) _InfoPill(icon: Icons.warning_amber_rounded, text: _active.knownTriggers!),
                        if (_active.calmingActivities != null) _InfoPill(icon: Icons.spa_rounded, text: _active.calmingActivities!),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      StatChip(value: '${_active.sessionCount}', label: 'Sessions'),
                      StatChip(value: '${_active.sessionsThisWeek}', label: 'This Week'),
                      StatChip(value: '${_active.streakDays} days', label: 'Streak'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _StartSessionCard(childName: _active.name, onTap: _startSessionFlow),
            const SizedBox(height: 20),

            // Longitudinal 3-Session Overall Insights & Reports Card (for caregiver-guided children)
            if (!_active.therapistNeeded) ...[
              _CaregiverInsightsCard(
                profile: _active,
                onOpenReport: (initialIndex) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PatientReportScreen(
                        profile: _active,
                        isCaregiverView: true,
                        initialSessionIndex: initialIndex,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],

            const SizedBox(height: 14),
            Row(
              children: [
                Text('Past Sessions', style: GoogleFonts.fredoka(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(20)),
                  child: Text('${_active.sessionCount}', style: GoogleFonts.fredoka(color: AppColors.primary, fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                if (!_active.therapistNeeded && _active.sessions.isNotEmpty) ...[
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.accentSoft,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    icon: Icon(
                      _active.sessions.length >= 3 ? Icons.auto_awesome_rounded : Icons.assessment_outlined,
                      size: 15,
                      color: AppColors.primary,
                    ),
                    label: Text(
                      _active.sessions.length >= 3 ? 'Overall Insights' : 'All Reports',
                      style: GoogleFonts.fredoka(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PatientReportScreen(
                            profile: _active,
                            isCaregiverView: true,
                            initialSessionIndex: _active.sessions.length >= 3 ? 0 : 1,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                ],

                IconButton(
                  icon: _loadingSessions
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                      : const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 22),
                  tooltip: 'Refresh sessions',
                  onPressed: _loadingSessions ? null : _loadChildSessions,
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loadingSessions && _active.sessions.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                      const SizedBox(width: 12),
                      Text('Loading past sessions…', style: GoogleFonts.nunito(color: AppColors.textMuted)),
                    ],
                  ),
                ),
              )
            else if (_active.sessions.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: Text('No sessions yet — tap "Start Session" to begin.',
                    style: GoogleFonts.nunito(color: AppColors.textMuted)),
              )
            else
              ..._active.sessions.asMap().entries.map((entry) => _SessionTile(
                    session: entry.value,
                    sessionNumber: entry.key + 1,
                    therapistNeeded: _active.therapistNeeded,
                    profile: _active,
                  )),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(14)),
      constraints: const BoxConstraints(maxWidth: 260),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: GoogleFonts.nunito(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _StartSessionCard extends StatelessWidget {
  final String childName;
  final VoidCallback onTap;
  const _StartSessionCard({required this.childName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.primary, width: 1.6),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.play_arrow_rounded, color: AppColors.primary, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Start Session', style: GoogleFonts.fredoka(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                    const SizedBox(height: 4),
                    Text('A 20-second guided drawing session for $childName',
                        style: GoogleFonts.nunito(fontSize: 12.5, color: AppColors.textMuted, height: 1.3)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final SessionRecord session;
  final bool therapistNeeded;
  final int? sessionNumber;
  final ChildProfile? profile;
  const _SessionTile({
    required this.session,
    required this.therapistNeeded,
    this.sessionNumber,
    this.profile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (sessionNumber != null) ...[
                          Text('Session $sessionNumber · ',
                              style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 14.5)),
                        ],
                        Text(AppDateTime.formatIst(session.date),
                            style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, color: AppColors.primaryDark, fontSize: 14.5)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('${session.recordingSeconds + session.canvasSeconds}s total',
                            style: GoogleFonts.nunito(color: AppColors.textMuted, fontSize: 13)),
                        if (!therapistNeeded) ...[
                          const SizedBox(width: 8),
                          Text('· ${session.mood.label}',
                              style: GoogleFonts.nunito(color: session.mood.color, fontSize: 13, fontWeight: FontWeight.w700)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (session.distressAlert && !therapistNeeded)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.warning_amber_rounded, color: AppColors.alertRed),
                ),
              if (therapistNeeded)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.lock_outline_rounded, color: AppColors.textMuted),
                ),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.accentSoft,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  if (therapistNeeded) {
                    showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                      builder: (_) => Padding(
                        padding: const EdgeInsets.all(24),
                        child: _lockedSummary(),
                      ),
                    );
                  } else if (profile != null) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PatientReportScreen(
                          profile: profile!,
                          isCaregiverView: true,
                          initialSessionId: session.id,
                        ),
                      ),
                    );
                  } else {
                    showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                      builder: (bottomSheetContext) => Padding(
                        padding: const EdgeInsets.all(24),
                        child: _visibleSummary(bottomSheetContext),
                      ),
                    );
                  }
                },
                child: Text(
                  therapistNeeded ? 'View' : 'View Report',
                  style: GoogleFonts.fredoka(color: AppColors.primary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _visibleSummary(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Session Report', style: GoogleFonts.fredoka(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                  const SizedBox(height: 2),
                  Text(
                    AppDateTime.formatIst(session.date),
                    style: GoogleFonts.nunito(color: AppColors.textMuted, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: session.mood.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  session.mood.label,
                  style: GoogleFonts.fredoka(color: session.mood.color, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Two previews: (1) Stimulus Image and (2) Child's Drawing
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stimulus Image
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '10s Theme Image',
                      style: GoogleFonts.fredoka(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: session.stimulusAssetPath != null
                          ? Image.asset(
                              session.stimulusAssetPath!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.image_outlined, color: AppColors.textMuted),
                              ),
                            )
                          : const Center(
                              child: Icon(Icons.image_outlined, color: AppColors.textMuted),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Child's Drawing
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Drawing Shown',
                      style: GoogleFonts.fredoka(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                    ),
                    const SizedBox(height: 6),
                    DrawingThumbnail(
                      drawingReference: session.drawingReference,
                      strokes: session.drawingStrokes,
                      strokeCount: session.strokeCount,
                      showStrokes: false,
                      height: 120,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Stimulus Reaction
          if (session.stimulusReactionSummary != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  const Text('📷', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      session.stimulusReactionSummary!,
                      style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF14532D)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // LLM Generated Simple-Language Caregiver Report
          Text(
            'Caregiver Summary',
            style: GoogleFonts.fredoka(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              session.simpleLanguageReport ?? session.caregiverSummary,
              style: GoogleFonts.nunito(height: 1.4, fontSize: 12.5, color: AppColors.textDark),
            ),
          ),

          if (session.recommendations.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '💡 Tips for Home',
              style: GoogleFonts.fredoka(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 4),
            ...session.recommendations.map((rec) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('• $rec', style: GoogleFonts.nunito(fontSize: 12, color: AppColors.textMuted)),
                )),
          ],

          const SizedBox(height: 12),
          Text(
            'Valence ${session.valence.toStringAsFixed(2)}  ·  Arousal ${session.arousal.toStringAsFixed(2)}  ·  Dominance ${session.dominance.toStringAsFixed(2)}',
            style: GoogleFonts.nunito(color: AppColors.textMuted, fontSize: 11),
          ),
          if (profile != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                icon: const Icon(Icons.auto_graph_rounded, size: 16),
                label: Text(
                  'Open Full Interactive Report & Insights',
                  style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PatientReportScreen(
                        profile: profile!,
                        isCaregiverView: true,
                        initialSessionId: session.id,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lockedSummary() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warnAmber.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_rounded, color: AppColors.warnAmber, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Report Locked for Therapist Review',
                      style: GoogleFonts.fredoka(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                  Text('Active clinical review required',
                      style: GoogleFonts.nunito(fontSize: 11.5, color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text(
            "Because this child's profile is set to require a therapist, the detailed diagnostic findings "
            '(including the 10-second interest stimulus reaction, drawing strokes, and AI clinical report) '
            'have been securely locked on this dashboard and routed directly to the licensed therapist.\n\n'
            'Your therapist will review the session and follow up with you directly.',
            style: GoogleFonts.nunito(height: 1.45, color: AppColors.textDark, fontSize: 12.5),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              'Delivered to Therapist Portal',
              style: GoogleFonts.fredoka(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
            ),
          ],
        ),
      ],
    );
  }
}

class _CaregiverInsightsCard extends StatelessWidget {
  final ChildProfile profile;
  final void Function(int initialIndex) onOpenReport;

  const _CaregiverInsightsCard({
    required this.profile,
    required this.onOpenReport,
  });

  @override
  Widget build(BuildContext context) {
    final count = profile.sessions.length;
    final hasTrajectory = count >= 3;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: hasTrajectory ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasTrajectory ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: hasTrajectory
                ? const Color(0xFF16A34A).withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: hasTrajectory ? const Color(0xFF16A34A) : AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hasTrajectory ? Icons.auto_awesome_rounded : Icons.insights_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            hasTrajectory ? '3+ Sessions Overall Insights' : 'Progress & Session Reports',
                            style: GoogleFonts.fredoka(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: hasTrajectory ? const Color(0xFF166534) : AppColors.primaryDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: hasTrajectory
                                ? const Color(0xFFDCFCE7)
                                : count > 0
                                    ? AppColors.warnAmber.withValues(alpha: 0.14)
                                    : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: hasTrajectory
                                  ? const Color(0xFFBBF7D0)
                                  : count > 0
                                      ? AppColors.warnAmber.withValues(alpha: 0.3)
                                      : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Text(
                            hasTrajectory
                                ? '🌟 Unlocked'
                                : '$count / 3 completed',
                            style: GoogleFonts.fredoka(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: hasTrajectory
                                  ? const Color(0xFF166534)
                                  : count > 0
                                      ? AppColors.warnAmber
                                      : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasTrajectory
                          ? 'Synthesized cross-session longitudinal report available'
                          : count > 0
                              ? '${3 - count} more ${3 - count == 1 ? "session" : "sessions"} needed to unlock 3-session longitudinal report'
                              : 'Complete sessions to unlock multi-session trajectory insights',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: hasTrajectory ? const Color(0xFF15803D) : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            hasTrajectory
                ? 'ArtSpeak has compiled total cross-session insights for ${profile.name}! Review longitudinal mood trajectory graphs, artwork motor progression, and holistic home guidance.'
                : count > 0
                    ? 'Explore multimodal reports with visual gaze and drawing analysis for completed sessions. Once 3 sessions are completed, overall longitudinal insights synthesize automatically.'
                    : 'Start your first guided session to begin building ${profile.name}\'s expressive art profile and longitudinal trajectory report.',
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              height: 1.4,
              color: hasTrajectory ? const Color(0xFF14532D) : AppColors.textDark,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (hasTrajectory) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.auto_graph_rounded, size: 16),
                      label: Text(
                        'View 3+ Sessions Overall Insights',
                        style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      onPressed: () => onOpenReport(0),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.assessment_rounded, size: 16),
                      label: Text(
                        'View Session Reports',
                        style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      onPressed: () => onOpenReport(1),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

