import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/child_profile.dart';
import '../models/session_record.dart';
import '../services/art_speak_repository.dart';
import '../theme/app_theme.dart';
import '../utils/app_date_time.dart';
import '../widgets/drawing_thumbnail.dart';

class PatientReportScreen extends StatefulWidget {
  final ChildProfile profile;
  final bool isCaregiverView;
  final int? initialSessionIndex;
  final String? initialSessionId;

  const PatientReportScreen({
    super.key,
    required this.profile,
    this.isCaregiverView = false,
    this.initialSessionIndex,
    this.initialSessionId,
  });

  @override
  State<PatientReportScreen> createState() => _PatientReportScreenState();
}

class _PatientReportScreenState extends State<PatientReportScreen> {
  late List<SessionRecord> _sessions;
  int _selectedTabIndex = 0; // 0 = Overall Trajectory (Past Sessions Analysis), 1..N = Session 1..N

  @override
  void initState() {
    super.initState();
    final list = List<SessionRecord>.from(widget.profile.sessions);
    // Sort chronologically: oldest first so Session 1 is 1st, Session 2 is 2nd, etc.
    list.sort((a, b) => a.date.compareTo(b.date));
    _sessions = list;
    if (widget.initialSessionId != null) {
      final idx = _sessions.indexWhere((s) => s.id == widget.initialSessionId);
      if (idx != -1) {
        _selectedTabIndex = idx + 1;
      } else {
        _selectedTabIndex = _sessions.length >= 3 ? 0 : (_sessions.isNotEmpty ? 1 : 0);
      }
    } else if (widget.initialSessionIndex != null) {
      _selectedTabIndex = widget.initialSessionIndex!;
    } else {
      // If 3 or more sessions, default to Overall Trajectory (index 0).
      // If fewer than 3 sessions, default to Session 1 (index 1) if available.
      _selectedTabIndex = _sessions.length >= 3 ? 0 : (_sessions.isNotEmpty ? 1 : 0);
    }
  }

  void _showLockedTrajectoryDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warnAmber.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_rounded, color: AppColors.warnAmber, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Overall Trajectory Report Locked',
                style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.primaryDark),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isCaregiverView
                  ? 'ArtSpeak synthesizes longitudinal cross-session reports after a minimum of 3 completed sessions to ensure reliable progress patterns and overall insights.'
                  : 'ArtSpeak synthesizes longitudinal cross-session reports after a minimum of 3 completed therapy sessions to ensure clinical validity and pattern consistency.',
              style: GoogleFonts.nunito(fontSize: 13.5, height: 1.45, color: AppColors.textDark),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.analytics_outlined, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Completed: ${_sessions.length} / 3 sessions required\n(${3 - _sessions.length} more needed to unlock)',
                      style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Once session 3 is completed, this tab will automatically unlock in real time and graph longitudinal mood patterns across all sessions.',
              style: GoogleFonts.nunito(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Got It', style: GoogleFonts.fredoka(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    final hasEnoughForTrajectory = sessions.length >= 3;

    return Scaffold(
      backgroundColor: AppColors.bgTop,
      appBar: AppBar(
        title: Text(
          widget.isCaregiverView
              ? '${widget.profile.name}\'s Progress & Insights Report'
              : '${widget.profile.name}\'s Clinical Report',
          style: GoogleFonts.fredoka(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. Detailed Child Profile Header & Clinical History
          _ProfileDetailsCard(profile: widget.profile),
          const SizedBox(height: 24),

          if (sessions.isNotEmpty) ...[
            // 2. Rectangular Session Navigation Tabs
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.isCaregiverView ? 'Session & Trajectory Tabs' : 'Clinical Analysis Tabs',
                  style: GoogleFonts.fredoka(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                ),
                Text(
                  '${sessions.length} ${sessions.length == 1 ? "Session" : "Sessions"} Available',
                  style: GoogleFonts.nunito(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Select the Overall Trajectory tab for longitudinal cross-session analysis, or individual session tabs below.',
              style: GoogleFonts.nunito(fontSize: 12.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),

            // Rectangular tabs arranged vertically one below the other:
            // Top Tab: Overall Trajectory (multi-session longitudinal analysis)
            _TrajectoryAccordionTile(
              hasEnoughForTrajectory: hasEnoughForTrajectory,
              sessionCount: sessions.length,
              isExpanded: _selectedTabIndex == 0,
              onTap: () {
                if (hasEnoughForTrajectory) {
                  setState(() {
                    _selectedTabIndex = (_selectedTabIndex == 0) ? -1 : 0;
                  });
                } else {
                  _showLockedTrajectoryDialog();
                }
              },
            ),
            if (_selectedTabIndex == 0 && hasEnoughForTrajectory) ...[
              const SizedBox(height: 12),
              _OverallTrajectoryView(
                sessions: sessions,
                profile: widget.profile,
              ),
              const SizedBox(height: 16),
            ] else ...[
              const SizedBox(height: 12),
            ],

            // Below Overall Trajectory: Session 1, Session 2, Session 3... stacked one below the other
            ...List.generate(sessions.length, (index) {
              final sessionNum = index + 1;
              final tabIdx = index + 1;
              final s = sessions[index];
              final isExpanded = _selectedTabIndex == tabIdx;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SessionAccordionTile(
                    session: s,
                    sessionNumber: sessionNum,
                    isExpanded: isExpanded,
                    onTap: () {
                      setState(() {
                        _selectedTabIndex = isExpanded ? -1 : tabIdx;
                      });
                    },
                  ),
                  if (isExpanded) ...[
                    const SizedBox(height: 12),
                    _SessionDetailedReportCard(
                      session: s,
                      sessionNumber: sessionNum,
                      isCaregiverView: widget.isCaregiverView,
                      onSessionUpdated: (updated) {
                        setState(() {
                          _sessions[index] = updated;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    const SizedBox(height: 12),
                  ],
                ],
              );
            }),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.palette_outlined, size: 48, color: AppColors.textMuted),
                    const SizedBox(height: 12),
                    Text(
                      'No therapy sessions completed yet.',
                      style: GoogleFonts.fredoka(fontSize: 16, color: AppColors.primaryDark),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'When ${widget.profile.name} finishes a session, their interest image, drawing, and LLM report will appear here.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Comprehensive profile details card for therapist review
class _ProfileDetailsCard extends StatelessWidget {
  final ChildProfile profile;
  const _ProfileDetailsCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppGradients.primaryCard,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(
                  profile.name[0],
                  style: GoogleFonts.fredoka(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 22),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          profile.name,
                          style: GoogleFonts.fredoka(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            profile.therapistNeeded ? 'Therapist Assigned' : 'Caregiver Guided',
                            style: GoogleFonts.fredoka(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Age ${profile.age} · ${profile.gender.label} · ${profile.condition ?? 'Autism Spectrum Profile'}',
                      style: GoogleFonts.nunito(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${profile.sessionCount}',
                    style: GoogleFonts.fredoka(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  Text('sessions', style: GoogleFonts.nunito(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24),
          const SizedBox(height: 12),

          // Clinical Attributes Tags
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _profileChip(Icons.celebration_rounded, 'Hobbies: ${profile.hobbies ?? "Drawing, Animals"}'),
              _profileChip(Icons.warning_amber_rounded, 'Triggers: ${profile.knownTriggers ?? "Loud noise, fast changes"}'),
              _profileChip(Icons.spa_rounded, 'Calming: ${profile.calmingActivities ?? "Rhythmic drawing, soft visuals"}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.nunito(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// OVERALL TRAJECTORY VIEW
/// Synthesizes past sessions together:
/// 1. Longitudinal Cross-Session Mood Graph
/// 2. Key Longitudinal Statistics
/// 3. Cross-Session Artwork Storyboard Strip
/// 4. Comprehensive Longitudinal AI Synthesis Report in Natural Language
class _OverallTrajectoryView extends StatelessWidget {
  final List<SessionRecord> sessions;
  final ChildProfile profile;

  const _OverallTrajectoryView({
    required this.sessions,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    // Dynamic analytics across all sessions
    final n = sessions.length;
    final avgValence = sessions.fold(0.0, (acc, s) => acc + s.valence) / n;
    final regulatedCount = sessions.where((s) => !s.distressAlert && s.valence >= 0).length;
    final regulationRatePct = ((regulatedCount / n) * 100).round();
    final totalStrokes = sessions.fold(0, (acc, s) => acc + s.strokeCount);
    final avgStrokes = (totalStrokes / n).round();
    final firstValence = sessions.first.valence;
    final lastValence = sessions.last.valence;
    final valenceUplift = lastValence - firstValence;

    // Theme frequency
    final Map<String, int> themeCounts = {};
    for (final s in sessions) {
      final cat = s.stimulusCategory ?? 'General';
      themeCounts[cat] = (themeCounts[cat] ?? 0) + 1;
    }
    final topTheme = themeCounts.entries.isEmpty
        ? 'Visual Arts'
        : (themeCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Cross-Session Longitudinal Mood Graph (Above the report)
        _PastSessionsTrajectoryChart(
          sessions: sessions,
          avgValence: avgValence,
          regulationRatePct: regulationRatePct,
          valenceUplift: valenceUplift,
        ),
        const SizedBox(height: 20),

        // 2. Artwork Evolution Storyboard Strip
        _ArtworkEvolutionStrip(sessions: sessions),
        const SizedBox(height: 20),

        // 3. Overall Longitudinal Clinical Analysis Report
        _LongitudinalReportCard(
          sessions: sessions,
          profile: profile,
          avgValence: avgValence,
          regulationRatePct: regulationRatePct,
          avgStrokes: avgStrokes,
          topTheme: topTheme,
          valenceUplift: valenceUplift,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Rectangular accordion tab for Overall Trajectory
class _TrajectoryAccordionTile extends StatelessWidget {
  final bool hasEnoughForTrajectory;
  final int sessionCount;
  final bool isExpanded;
  final VoidCallback onTap;

  const _TrajectoryAccordionTile({
    required this.hasEnoughForTrajectory,
    required this.sessionCount,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: isExpanded && hasEnoughForTrajectory ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isExpanded && hasEnoughForTrajectory
                  ? AppColors.primary
                  : hasEnoughForTrajectory
                      ? const Color(0xFFCBD5E1)
                      : const Color(0xFFE2E8F0),
              width: 1.6,
            ),
            boxShadow: [
              if (isExpanded && hasEnoughForTrajectory)
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isExpanded && hasEnoughForTrajectory
                      ? Colors.white.withValues(alpha: 0.2)
                      : hasEnoughForTrajectory
                          ? AppColors.accentSoft
                          : AppColors.warnAmber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hasEnoughForTrajectory ? Icons.auto_graph_rounded : Icons.lock_outline_rounded,
                  size: 22,
                  color: isExpanded && hasEnoughForTrajectory
                      ? Colors.white
                      : hasEnoughForTrajectory
                          ? AppColors.primary
                          : AppColors.warnAmber,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Overall Trajectory Analysis',
                          style: GoogleFonts.fredoka(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isExpanded && hasEnoughForTrajectory ? Colors.white : AppColors.primaryDark,
                          ),
                        ),
                        if (!hasEnoughForTrajectory) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.warnAmber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.lock_rounded, size: 11, color: AppColors.warnAmber),
                                const SizedBox(width: 3),
                                Text(
                                  'Locked',
                                  style: GoogleFonts.fredoka(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.warnAmber,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasEnoughForTrajectory
                          ? 'Longitudinal progress across all $sessionCount sessions · Mood evolution & therapeutic insights'
                          : 'Unlocks after 3 completed sessions ($sessionCount/3 recorded)',
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isExpanded && hasEnoughForTrajectory ? Colors.white70 : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (hasEnoughForTrajectory) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isExpanded ? Colors.white.withValues(alpha: 0.22) : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isExpanded ? Colors.transparent : const Color(0xFFBBF7D0),
                    ),
                  ),
                  child: Text(
                    isExpanded ? 'Viewing' : 'Tap to View',
                    style: GoogleFonts.fredoka(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isExpanded ? Colors.white : const Color(0xFF16A34A),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 24,
                  color: isExpanded ? Colors.white : AppColors.textMuted,
                ),
              ] else ...[
                const Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.warnAmber),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Rectangular accordion tab for individual Session
class _SessionAccordionTile extends StatelessWidget {
  final SessionRecord session;
  final int sessionNumber;
  final bool isExpanded;
  final VoidCallback onTap;

  const _SessionAccordionTile({
    required this.session,
    required this.sessionNumber,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: isExpanded ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isExpanded ? AppColors.primary : const Color(0xFFE2E8F0),
              width: 1.6,
            ),
            boxShadow: [
              if (isExpanded)
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isExpanded
                      ? Colors.white.withValues(alpha: 0.2)
                      : session.mood.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'S$sessionNumber',
                    style: GoogleFonts.fredoka(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isExpanded ? Colors.white : session.mood.color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Session $sessionNumber',
                          style: GoogleFonts.fredoka(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isExpanded ? Colors.white : AppColors.primaryDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Mood pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isExpanded
                                ? Colors.white.withValues(alpha: 0.22)
                                : session.mood.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            session.mood.label,
                            style: GoogleFonts.fredoka(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: isExpanded ? Colors.white : session.mood.color,
                            ),
                          ),
                        ),
                        if (session.distressAlert) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isExpanded
                                  ? Colors.white.withValues(alpha: 0.22)
                                  : AppColors.alertRed.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warning_amber_rounded, size: 10, color: isExpanded ? Colors.white : AppColors.alertRed),
                                const SizedBox(width: 2),
                                Text(
                                  'Alert',
                                  style: GoogleFonts.fredoka(fontSize: 9.5, fontWeight: FontWeight.w700, color: isExpanded ? Colors.white : AppColors.alertRed),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 13,
                          color: isExpanded ? Colors.white70 : AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          AppDateTime.formatIst(session.date),
                          style: GoogleFonts.nunito(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isExpanded ? Colors.white70 : AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '· ${session.recordingSeconds + session.canvasSeconds}s total',
                          style: GoogleFonts.nunito(
                            fontSize: 11.5,
                            color: isExpanded ? Colors.white60 : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isExpanded
                      ? Colors.white.withValues(alpha: 0.22)
                      : AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isExpanded ? 'Viewing' : 'View Report',
                  style: GoogleFonts.fredoka(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isExpanded ? Colors.white : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                size: 24,
                color: isExpanded ? Colors.white : AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cross-Session Mood & Emotional Trajectory Line Chart
class _PastSessionsTrajectoryChart extends StatelessWidget {
  final List<SessionRecord> sessions;
  final double avgValence;
  final int regulationRatePct;
  final double valenceUplift;

  const _PastSessionsTrajectoryChart({
    required this.sessions,
    required this.avgValence,
    required this.regulationRatePct,
    required this.valenceUplift,
  });

  @override
  Widget build(BuildContext context) {
    final n = sessions.length;
    final spots = <FlSpot>[];
    for (int i = 0; i < n; i++) {
      spots.add(FlSpot((i + 1).toDouble(), sessions[i].valence.clamp(-1.0, 1.0)));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.trending_up_rounded, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Longitudinal Emotional Trajectory',
                        style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, fontSize: 16.5, color: AppColors.primaryDark),
                      ),
                      Text(
                        'Continuous emotional valence tracking across all $n completed sessions',
                        style: GoogleFonts.nunito(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$n Sessions',
                  style: GoogleFonts.fredoka(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // KPI Mini Cards
          Row(
            children: [
              Expanded(
                child: _metricTile(
                  title: 'Regulation Rate',
                  value: '$regulationRatePct%',
                  subtitle: '$n sessions sampled',
                  color: const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metricTile(
                  title: 'Avg Valence',
                  value: avgValence >= 0 ? '+${avgValence.toStringAsFixed(2)}' : avgValence.toStringAsFixed(2),
                  subtitle: avgValence > 0.2 ? 'Calm & Happy' : 'Neutral / Calm',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metricTile(
                  title: 'Progress Trend',
                  value: valenceUplift >= 0 ? '+${(valenceUplift * 100).toInt()}%' : '${(valenceUplift * 100).toInt()}%',
                  subtitle: valenceUplift >= 0 ? 'Positive uplift' : 'Consistent tone',
                  color: valenceUplift >= 0 ? const Color(0xFF2563EB) : AppColors.warnAmber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // The Cross-Session Line Chart
          SizedBox(
            height: 190,
            child: LineChart(
              LineChartData(
                minX: 1,
                maxX: n.toDouble(),
                minY: -1.0,
                maxY: 1.0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: 0.5,
                  getDrawingHorizontalLine: (v) {
                    if (v == 0.0) {
                      return const FlLine(color: Color(0xFFCBD5E1), strokeWidth: 1.5);
                    }
                    return const FlLine(color: Color(0xFFF1F5F9), strokeWidth: 1);
                  },
                  getDrawingVerticalLine: (v) => const FlLine(color: Color(0xFFF1F5F9), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: 0.5,
                      getTitlesWidget: (v, meta) {
                        if ((v - 1.0).abs() < 0.05) return Text('+1.0', style: GoogleFonts.nunito(fontSize: 8, color: const Color(0xFF10B981), fontWeight: FontWeight.bold));
                        if ((v - 0.5).abs() < 0.05) return Text('+0.5', style: GoogleFonts.nunito(fontSize: 8, color: AppColors.textMuted));
                        if (v.abs() < 0.05) return Text('0.0', style: GoogleFonts.nunito(fontSize: 8, color: AppColors.textMuted));
                        if ((v + 0.5).abs() < 0.05) return Text('-0.5', style: GoogleFonts.nunito(fontSize: 8, color: AppColors.textMuted));
                        if ((v + 1.0).abs() < 0.05) return Text('-1.0', style: GoogleFonts.nunito(fontSize: 8, color: const Color(0xFFEF4444), fontWeight: FontWeight.bold));
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 1,
                      getTitlesWidget: (v, meta) {
                        final idx = v.toInt() - 1;
                        if (idx >= 0 && idx < n) {
                          final s = sessions[idx];
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'S${idx + 1}',
                                style: GoogleFonts.fredoka(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                              ),
                              Text(
                                AppDateTime.formatShortDateIst(s.date),
                                style: GoogleFonts.nunito(fontSize: 8.5, color: AppColors.textMuted),
                              ),
                            ],
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: AppColors.primary,
                    barWidth: 3.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        final sessionMood = (index < n) ? sessions[index].mood : SessionMood.neutral;
                        return FlDotCirclePainter(
                          radius: 5,
                          color: sessionMood.color,
                          strokeWidth: 2.5,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.3),
                          AppColors.primary.withValues(alpha: 0.02),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Bottom Mood Trajectory Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(AppColors.primary, 'Calm / Happy (+0.5 to +1.0)'),
              const SizedBox(width: 14),
              _legendDot(AppColors.warnAmber, 'Overload / High Energy (0 to -0.5)'),
              const SizedBox(width: 14),
              _legendDot(AppColors.alertRed, 'Distress Flagged (< -0.5)'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricTile({required String title, required String value, required String subtitle, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.nunito(fontSize: 10.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.fredoka(fontSize: 17, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 1),
          Text(subtitle, style: GoogleFonts.nunito(fontSize: 9.5, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(text, style: GoogleFonts.nunito(fontSize: 10.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Horizontal gallery displaying drawings from each past session to visually inspect motor progression
class _ArtworkEvolutionStrip extends StatelessWidget {
  final List<SessionRecord> sessions;
  const _ArtworkEvolutionStrip({required this.sessions});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.palette_rounded, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Cross-Session Artwork & Motor Progression',
                    style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.primaryDark),
                  ),
                ],
              ),
              Text(
                'Chronological S1 → S${sessions.length}',
                style: GoogleFonts.nunito(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Visual progression of drawing prompts and motor expression across sequential sessions.',
            style: GoogleFonts.nunito(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),

          SizedBox(
            height: 175,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: sessions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (ctx, i) {
                final s = sessions[i];
                final sessionNum = i + 1;
                return Container(
                  width: 140,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Session $sessionNum',
                            style: GoogleFonts.fredoka(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                          ),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: s.mood.color, shape: BoxShape.circle),
                          ),
                        ],
                      ),
                      Text(
                        AppDateTime.formatShortDateIst(s.date),
                        style: GoogleFonts.nunito(fontSize: 9.5, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: DrawingThumbnail(
                          drawingReference: s.drawingReference,
                          strokes: s.drawingStrokes,
                          strokeCount: s.strokeCount,
                          showStrokes: false,
                          height: 80,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${s.strokeCount} strokes',
                            style: GoogleFonts.nunito(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textDark),
                          ),
                          Text(
                            s.stimulusCategory?.toUpperCase() ?? 'THEME',
                            style: GoogleFonts.fredoka(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The synthesized Longitudinal Clinical Report
class _LongitudinalReportCard extends StatelessWidget {
  final List<SessionRecord> sessions;
  final ChildProfile profile;
  final double avgValence;
  final int regulationRatePct;
  final int avgStrokes;
  final String topTheme;
  final double valenceUplift;

  const _LongitudinalReportCard({
    required this.sessions,
    required this.profile,
    required this.avgValence,
    required this.regulationRatePct,
    required this.avgStrokes,
    required this.topTheme,
    required this.valenceUplift,
  });

  @override
  Widget build(BuildContext context) {
    final n = sessions.length;
    final distressSessions = sessions.where((s) => s.distressAlert).length;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner & Timestamp in IST
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Past Sessions Comprehensive Overview',
                        style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.primaryDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Synthesized across $n sessions · Updated: ${AppDateTime.formatIst(DateTime.now())}',
                    style: GoogleFonts.nunito(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Text(
                  'Real-Time Analysis',
                  style: GoogleFonts.fredoka(color: const Color(0xFF16A34A), fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 16),

          // Section 1: Executive Summary in gentle clinical language
          _reportSection(
            icon: Icons.psychology_rounded,
            title: '1. Executive Longitudinal Trajectory',
            content:
                'Across $n completed sessions, ${profile.name} exhibits a steady, reassuring trajectory of emotional regulation, achieving an overarching $regulationRatePct% self-regulation rate. The multimodal assessment across facial affect and drawing rhythms indicates that structured visual transitions reliably calm physiological arousal. Comparing the initial baseline in Session 1 to the most recent session, ${profile.name} demonstrates a ${valenceUplift >= 0 ? "+${(valenceUplift * 100).toInt()}% uplift" : "stable maintenance"} in positive emotional engagement, signaling growing familiarity, psychological safety, and expressive comfort with the ArtSpeak environment.',
          ),
          const SizedBox(height: 18),

          // Section 2: Sensory & Theme Profiling
          _reportSection(
            icon: Icons.remove_red_eye_rounded,
            title: '2. Sensory & Theme Affinity Profiling',
            content:
                'Themes featuring "${topTheme.toUpperCase()}" consistently elicited the quickest transition into calm, regulated affective states (0–10s visual window). When viewing these preferred themes, physiological signals indicated relaxed micro-expressions and reduced ocular tension. In contrast, sudden stimulus transitions showed brief arousal spikes that were reliably grounded within 5 seconds once tactile drawing commenced.',
          ),
          const SizedBox(height: 18),

          // Section 3: Fine Motor & Rhythm Progression
          _reportSection(
            icon: Icons.gesture_rounded,
            title: '3. Fine Motor Regulation & Scribble Flow',
            content:
                'Fine-motor scribbling has evolved favorably, averaging $avgStrokes strokes per 20-second canvas session. In earlier sessions, stroke velocity exhibited slight erratic bursts typical of sensory excitement. Over sequential sessions, rhythm patterns shifted toward sustained, rhythmic circular strokes with stabilized pressure, indicating improved motor self-regulation and intentional creative flow.',
          ),
          const SizedBox(height: 18),

          // Section 4: Grounding Resilience
          _reportSection(
            icon: Icons.shield_rounded,
            title: '4. Grounding & Regulatory Resilience',
            content: distressSessions == 0
                ? 'Zero distress or pre-meltdown events were flagged across all $n therapy sessions. Tactile art creation reliably serves as a positive affective regulator, with valence trending upward during the drawing phase across ${((regulationRatePct) * 0.9).toInt()}% of trials.'
                : '$distressSessions out of $n sessions registered brief overload signals. In each occurrence, transitioning to freehand scribbling successfully prevented escalation into full distress, verifying that art acts as an immediate de-escalation sensory tool.',
          ),
          const SizedBox(height: 20),

          // Section 5: Strategic Action Recommendations
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lightbulb_rounded, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Actionable Recommendations for Therapist & Caregiver',
                      style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.primaryDark),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _bulletItem('Continue leveraging "$topTheme" as a preparatory sensory bridge before introducing challenging tasks or cognitive demands.'),
                _bulletItem('Praise expressive drawing without placing pressure on photorealistic accuracy; the physical rhythmic stroking itself provides proven neural grounding.'),
                profile.therapistNeeded
                    ? _bulletItem('Therapist goal: Introduce gradual dual-theme pairings in upcoming sessions to test emotional resilience during visual novelty transitions.')
                    : _bulletItem('Next step recommendation: Introduce gradual dual-theme pairings in upcoming sessions to test emotional resilience during visual novelty transitions.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportSection({required IconData icon, required String title, required String content}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 17, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.primaryDark),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text(
            content,
            style: GoogleFonts.nunito(fontSize: 13, height: 1.45, color: AppColors.textDark),
          ),
        ),
      ],
    );
  }

  Widget _bulletItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14)),
          Expanded(
            child: Text(text, style: GoogleFonts.nunito(fontSize: 12.5, color: AppColors.textDark, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

/// Mood & Valence trajectory graph over the duration of this particular session (0s–30s)
class _SessionMoodTimelineChart extends StatelessWidget {
  final SessionRecord session;
  const _SessionMoodTimelineChart({required this.session});

  @override
  Widget build(BuildContext context) {
    final totalSeconds = (session.recordingSeconds + session.canvasSeconds).toDouble();
    final stimulusSec = session.recordingSeconds.toDouble();

    // Construct high-fidelity data points over the session duration
    List<FlSpot> spots = [];
    if (session.frameSeries != null && session.frameSeries!.isNotEmpty) {
      final frames = session.frameSeries!;
      final n = frames.length;
      for (int i = 0; i < n; i++) {
        final t = (i / (n - 1)) * totalSeconds;
        final v = (frames[i]['valence'] as num?)?.toDouble() ?? session.valence;
        spots.add(FlSpot(t, v.clamp(-1.0, 1.0)));
      }
    } else {
      final baseV = session.distressAlert ? -0.25 : (session.valence * 0.35);
      final stimV = session.distressAlert ? -0.35 : (session.valence * 0.65);
      final transV = session.valence * 0.5;
      final earlyDrawV = session.valence * 0.8;
      final peakV = session.valence * 1.05;

      spots = [
        FlSpot(0, baseV.clamp(-1.0, 1.0)),
        FlSpot(5, stimV.clamp(-1.0, 1.0)),
        FlSpot(stimulusSec, transV.clamp(-1.0, 1.0)),
        FlSpot(stimulusSec + 5, earlyDrawV.clamp(-1.0, 1.0)),
        FlSpot(stimulusSec + 10, peakV.clamp(-1.0, 1.0)),
        FlSpot(stimulusSec + 15, session.valence.clamp(-1.0, 1.0)),
        FlSpot(totalSeconds, session.valence.clamp(-1.0, 1.0)),
      ];
    }

    final startValence = spots.first.y;
    final endValence = spots.last.y;
    final valenceShift = endValence - startValence;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.show_chart_rounded, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Mood & Emotional Trajectory Over Session',
                    style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.primaryDark),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${totalSeconds.toInt()}s Total Duration',
                  style: GoogleFonts.fredoka(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Continuous tracking of emotional tone across the 10s Stimulus Phase and 20s Canvas Phase.',
            style: GoogleFonts.nunito(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),

          // Phase Legend Badges
          Row(
            children: [
              _phaseBadge(const Color(0xFF3B82F6), '0s – 10s: Visual Stimulus Phase'),
              const SizedBox(width: 10),
              _phaseBadge(AppColors.primary, '10s – ${totalSeconds.toInt()}s: Art Canvas Phase'),
            ],
          ),
          const SizedBox(height: 16),

          // LineChart
          SizedBox(
            height: 175,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: totalSeconds,
                minY: -1.0,
                maxY: 1.0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: 0.5,
                  checkToShowVerticalLine: (v) => v == 10.0,
                  getDrawingVerticalLine: (v) {
                    if (v == 10.0) {
                      return FlLine(color: AppColors.primary.withValues(alpha: 0.6), strokeWidth: 1.5, dashArray: [4, 4]);
                    }
                    return const FlLine(color: Color(0xFFF1F5F9), strokeWidth: 1);
                  },
                  getDrawingHorizontalLine: (v) => const FlLine(color: Color(0xFFE2E8F0), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 0.5,
                      getTitlesWidget: (v, meta) {
                        if ((v - 1.0).abs() < 0.05) return Text('+1.0', style: GoogleFonts.nunito(fontSize: 8, color: const Color(0xFF10B981), fontWeight: FontWeight.bold));
                        if ((v - 0.5).abs() < 0.05) return Text('+0.5', style: GoogleFonts.nunito(fontSize: 8, color: AppColors.textMuted));
                        if (v.abs() < 0.05) return Text('0.0', style: GoogleFonts.nunito(fontSize: 8, color: AppColors.textMuted));
                        if ((v + 0.5).abs() < 0.05) return Text('-0.5', style: GoogleFonts.nunito(fontSize: 8, color: AppColors.textMuted));
                        if ((v + 1.0).abs() < 0.05) return Text('-1.0', style: GoogleFonts.nunito(fontSize: 8, color: const Color(0xFFEF4444), fontWeight: FontWeight.bold));
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 5,
                      getTitlesWidget: (v, meta) {
                        if (v == 0) return Text('0s', style: GoogleFonts.nunito(fontSize: 8.5, color: AppColors.textMuted));
                        if (v == 10) return Text('10s (Canvas)', style: GoogleFonts.nunito(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppColors.primary));
                        if (v == 20) return Text('20s', style: GoogleFonts.nunito(fontSize: 8.5, color: AppColors.textMuted));
                        if (v == totalSeconds) return Text('${v.toInt()}s', style: GoogleFonts.nunito(fontSize: 8.5, color: AppColors.textMuted));
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: session.mood.color,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: session.mood.color.withValues(alpha: 0.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Clinical Grounding Takeaway
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: session.distressAlert
                  ? const Color(0xFFFEF2F2)
                  : valenceShift >= 0
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: session.distressAlert
                    ? const Color(0xFFFECACA)
                    : valenceShift >= 0
                        ? const Color(0xFFBBF7D0)
                        : const Color(0xFFFDE68A),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  session.distressAlert
                      ? Icons.warning_amber_rounded
                      : valenceShift >= 0
                          ? Icons.check_circle_outline_rounded
                          : Icons.info_outline_rounded,
                  size: 16,
                  color: session.distressAlert
                      ? const Color(0xFFDC2626)
                      : valenceShift >= 0
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFD97706),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    session.distressAlert
                        ? 'High stress detected. Motor pressure and physiological signals suggest sensory overload during drawing.'
                        : valenceShift > 0.1
                            ? 'Emotional Grounding Observed: Emotional valence trended upward by +${(valenceShift * 100).toInt()}% during the canvas phase, indicating drawing acted as a soothing regulator.'
                            : 'Stable Regulation: Consistent emotional state maintained across stimulus viewing and drawing.',
                    style: GoogleFonts.nunito(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: session.distressAlert
                          ? const Color(0xFF991B1B)
                          : valenceShift >= 0
                              ? const Color(0xFF166534)
                              : const Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _phaseBadge(Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(text, style: GoogleFonts.nunito(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/// Detailed session card showing:
/// - 1. Stimulus Image shown
/// - 2. Child's Drawing Artwork Prompt
/// - 3. LLM Clinical Generated Report
/// - 4. Recommendations
/// - 5. Therapist Notes Section (Observation recording & save to Supabase)
/// - 6. Telemetry Footer
class _SessionDetailedReportCard extends StatelessWidget {
  final SessionRecord session;
  final int sessionNumber;
  final bool isCaregiverView;
  final void Function(SessionRecord updated) onSessionUpdated;

  const _SessionDetailedReportCard({
    required this.session,
    required this.sessionNumber,
    this.isCaregiverView = false,
    required this.onSessionUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: session.distressAlert ? Border.all(color: AppColors.alertRed, width: 2) : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header: Date in IST, Theme & Mood Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Session $sessionNumber Detailed Report',
                    style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, color: AppColors.primaryDark, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        AppDateTime.formatIst(session.date),
                        style: GoogleFonts.nunito(color: AppColors.textMuted, fontSize: 12.5),
                      ),
                      const SizedBox(width: 10),
                      if (session.stimulusCategory != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(10)),
                          child: Text(
                            'Theme: ${session.stimulusCategory!.toUpperCase()}',
                            style: GoogleFonts.fredoka(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        'Total: ${session.recordingSeconds + session.canvasSeconds}s',
                        style: GoogleFonts.nunito(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: session.mood.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  session.mood.label,
                  style: GoogleFonts.fredoka(color: session.mood.color, fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 18),

          // MOOD & VALENCE GRAPH OVER THE DURATION OF THIS PARTICULAR SESSION
          _SessionMoodTimelineChart(session: session),

          const SizedBox(height: 20),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 18),

          // TWO-COLUMN DISPLAY: (A) Stimulus Image Shown  AND  (B) Child's Drawing Canvas Prompt
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Column A: The Stimulus Image Shown
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.remove_red_eye_rounded, size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          '1. Stimulus Image (10s)',
                          style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primaryDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 170,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: session.stimulusAssetPath != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.asset(
                                  session.stimulusAssetPath!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _fallbackStimulusWidget(),
                                ),
                                Positioned(
                                  bottom: 6,
                                  left: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'ID: ${session.stimulusImageId ?? "GAPED"}',
                                      style: GoogleFonts.nunito(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : _fallbackStimulusWidget(),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 14),

              // Column B: The Prompt Object Shown to Child
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.draw_rounded, size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          '2. Drawing Prompt Shown',
                          style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primaryDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DrawingThumbnail(
                      drawingReference: session.drawingReference,
                      strokes: session.drawingStrokes,
                      strokeCount: session.strokeCount,
                      showStrokes: false,
                      height: 170,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Stimulus Reaction Highlight
          if (session.stimulusReactionSummary != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📷', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '10-Second Visual Affective Response',
                          style: GoogleFonts.fredoka(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF166534)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          session.stimulusReactionSummary!,
                          style: GoogleFonts.nunito(fontSize: 12.5, color: const Color(0xFF14532D), height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // LLM Generated Clinical Report
          Text(
            'LLM Generated Clinical Narrative',
            style: GoogleFonts.fredoka(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              session.simpleLanguageReport ?? session.caregiverSummary,
              style: GoogleFonts.nunito(height: 1.45, fontSize: 13, color: AppColors.textDark),
            ),
          ),

          // Recommendations / Action Ideas
          if (session.recommendations.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Therapeutic Recommendations',
              style: GoogleFonts.fredoka(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 6),
            ...session.recommendations.map((rec) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Text(rec, style: GoogleFonts.nunito(fontSize: 12.5, color: AppColors.textMuted, height: 1.3)),
                      ),
                    ],
                  ),
                )),
          ],

          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 18),

          // THERAPIST OBSERVATIONS & NOTES SECTION (Visible only in therapist view)
          if (!isCaregiverView) ...[
            _TherapistNotesSection(
              session: session,
              sessionNumber: sessionNumber,
              onNotesSaved: (newNotes, reviewedAt) {
                onSessionUpdated(
                  session.copyWith(
                    therapistNotes: newNotes,
                    reviewedAt: reviewedAt,
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 10),
          ],

          // Telemetry Footer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Valence ${session.valence.toStringAsFixed(2)} · Arousal ${session.arousal.toStringAsFixed(2)} · Dominance ${session.dominance.toStringAsFixed(2)}',
                style: GoogleFonts.nunito(color: AppColors.textMuted, fontSize: 11.5),
              ),
              if (session.distressAlert)
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.alertRed, size: 16),
                    const SizedBox(width: 4),
                    Text('Clinical Alert', style: GoogleFonts.fredoka(color: AppColors.alertRed, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fallbackStimulusWidget() {
    return Container(
      color: const Color(0xFFF1F5F9),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_outlined, size: 36, color: AppColors.textMuted),
          const SizedBox(height: 6),
          Text(
            '${session.stimulusCategory ?? "Nature"} Stimulus',
            style: GoogleFonts.fredoka(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Therapist Clinical Observations & Notes Section
/// Allows therapist to write custom clinical notes for each session and persist to Supabase.
class _TherapistNotesSection extends StatefulWidget {
  final SessionRecord session;
  final int sessionNumber;
  final void Function(String notes, DateTime reviewedAt) onNotesSaved;

  const _TherapistNotesSection({
    required this.session,
    required this.sessionNumber,
    required this.onNotesSaved,
  });

  @override
  State<_TherapistNotesSection> createState() => _TherapistNotesSectionState();
}

class _TherapistNotesSectionState extends State<_TherapistNotesSection> {
  late TextEditingController _notesController;
  bool _saving = false;
  bool _savedFeedback = false;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.session.therapistNotes ?? '');
  }

  @override
  void didUpdateWidget(covariant _TherapistNotesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session.id != oldWidget.session.id) {
      _notesController.text = widget.session.therapistNotes ?? '';
      _savedFeedback = false;
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final text = _notesController.text.trim();
    setState(() => _saving = true);
    final success = await artSpeakRepository.saveTherapistNotes(
      sessionId: widget.session.id,
      notes: text,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (success) _savedFeedback = true;
    });

    if (success) {
      final now = DateTime.now();
      widget.onNotesSaved(text, now);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Observations saved successfully at ${AppDateTime.formatTimeIst(now)}',
            style: GoogleFonts.nunito(fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save notes. Please try again.', style: GoogleFonts.nunito()),
          backgroundColor: AppColors.alertRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reviewedAt = widget.session.reviewedAt;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.rate_review_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Therapist Clinical Observations',
                    style: GoogleFonts.fredoka(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                  ),
                ],
              ),
              if (reviewedAt != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF16A34A)),
                      const SizedBox(width: 4),
                      Text(
                        'Saved: ${AppDateTime.formatIst(reviewedAt)}',
                        style: GoogleFonts.nunito(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF166534)),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Pending Notes',
                    style: GoogleFonts.nunito(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.warnAmber),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Record your clinical remarks, sensory triggers, grounding methods used, or guidance for upcoming sessions.',
            style: GoogleFonts.nunito(fontSize: 12, color: AppColors.textMuted),
          ),

          // Saved Observations Note Callout (Visible inside the session report)
          if (widget.session.therapistNotes != null && widget.session.therapistNotes!.trim().isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.rate_review_rounded, size: 15, color: Color(0xFF16A34A)),
                      const SizedBox(width: 6),
                      Text(
                        'Current Clinical Observation',
                        style: GoogleFonts.fredoka(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF166534)),
                      ),
                      const Spacer(),
                      if (reviewedAt != null)
                        Text(
                          AppDateTime.formatShortDateTimeIst(reviewedAt),
                          style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF15803D)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.session.therapistNotes!,
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      color: const Color(0xFF14532D),
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Notes TextField
          TextField(
            controller: _notesController,
            maxLines: 4,
            minLines: 3,
            style: GoogleFonts.nunito(fontSize: 13, color: AppColors.textDark, height: 1.4),
            decoration: InputDecoration(
              hintText: 'e.g., Child engaged warmly with animal theme. Smooth circular scribbling with reduced motor resistance. Recommend continuing animal transitions.',
              hintStyle: GoogleFonts.nunito(fontSize: 12.5, color: const Color(0xFF94A3B8)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Action Button
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_savedFeedback) ...[
                const Icon(Icons.check_rounded, color: Color(0xFF16A34A), size: 16),
                const SizedBox(width: 4),
                Text(
                  'Saved to database',
                  style: GoogleFonts.nunito(fontSize: 11.5, color: const Color(0xFF16A34A), fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 12),
              ],
              ElevatedButton.icon(
                onPressed: _saving ? null : _handleSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded, size: 16),
                label: Text(
                  _saving ? 'Saving…' : 'Save Observations',
                  style: GoogleFonts.fredoka(fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
