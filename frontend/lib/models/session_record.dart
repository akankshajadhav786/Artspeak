import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Coarse mood label surfaced to caregivers — derived from the multimodal VAD vector.
enum SessionMood { calm, energetic, focused, overloaded, neutral, distressed }

extension SessionMoodMeta on SessionMood {
  String get label {
    switch (this) {
      case SessionMood.calm:
        return 'Calm & Happy';
      case SessionMood.energetic:
        return 'Energetic & Expressive';
      case SessionMood.focused:
        return 'Engaged & Focused';
      case SessionMood.overloaded:
        return 'Overload risk';
      case SessionMood.neutral:
        return 'Neutral';
      case SessionMood.distressed:
        return 'Distress flagged';
    }
  }

  Color get color {
    switch (this) {
      case SessionMood.calm:
        return AppColors.primary;
      case SessionMood.energetic:
        return AppColors.warnAmber;
      case SessionMood.focused:
        return const Color(0xFF00897B);
      case SessionMood.overloaded:
        return AppColors.alertRed;
      case SessionMood.neutral:
        return AppColors.primaryLight;
      case SessionMood.distressed:
        return AppColors.alertRed;
    }
  }
}

/// One completed ArtSpeak session:
/// 10s child-selected interest stimulus viewing + 20s art canvas
/// + multimodal predictions + LLM simple language report for parents.
class SessionRecord {
  final String id;
  final DateTime date;
  final int recordingSeconds;
  final int canvasSeconds;
  final SessionMood mood;
  final double valence; // -1..1
  final double arousal; // 0..1
  final double dominance; // 0..1
  final int strokeCount;
  final String caregiverSummary;
  final bool distressAlert;
  final String? stimulusCategory;
  final String? stimulusImageId;
  final String? stimulusReactionSummary;
  final String? simpleLanguageReport;
  final String? drawingReference;
  final List<Map<String, dynamic>>? drawingStrokes;
  final List<Map<String, dynamic>>? frameSeries;
  final List<String> insights;
  final List<String> recommendations;
  final String? therapistNotes;
  final DateTime? reviewedAt;

  String? get stimulusAssetPath {
    if (stimulusCategory != null && stimulusImageId != null) {
      return 'assets/stimulus/$stimulusCategory/$stimulusImageId.jpg';
    }
    return null;
  }

  SessionRecord({
    required this.id,
    required this.date,
    required this.recordingSeconds,
    required this.canvasSeconds,
    required this.mood,
    required this.valence,
    required this.arousal,
    required this.dominance,
    required this.strokeCount,
    required this.caregiverSummary,
    this.distressAlert = false,
    this.stimulusCategory,
    this.stimulusImageId,
    this.stimulusReactionSummary,
    this.simpleLanguageReport,
    this.drawingReference,
    this.drawingStrokes,
    this.frameSeries,
    this.insights = const [],
    this.recommendations = const [],
    this.therapistNotes,
    this.reviewedAt,
  });

  factory SessionRecord.processing({
    required String id,
    required int seconds,
    required int strokeCount,
    String? stimulusCategory,
    String? stimulusImageId,
    String? drawingReference,
    List<Map<String, dynamic>>? drawingStrokes,
  }) {
    return SessionRecord(
      id: id,
      date: DateTime.now(),
      recordingSeconds: seconds,
      canvasSeconds: seconds,
      mood: SessionMood.neutral,
      valence: 0,
      arousal: 0,
      dominance: 0,
      strokeCount: strokeCount,
      caregiverSummary: 'Your session is being analysed across facial, gaze, touch, and physiological signals.',
      stimulusCategory: stimulusCategory,
      stimulusImageId: stimulusImageId,
      drawingReference: drawingReference,
      drawingStrokes: drawingStrokes,
    );
  }

  factory SessionRecord.fromReport(Map<String, dynamic> report) {
    final state = report['overall_state'] as String? ?? 'Calm_Regulated';
    final rawJson = (report['raw_report_json'] as Map?)?.cast<String, dynamic>() ?? const {};
    final strokeCount = (rawJson['stroke_count'] as num?)?.toInt() ?? (report['stroke_count'] as num?)?.toInt() ?? 0;
    final affect = (rawJson['affect_vector'] as Map?)?.cast<String, dynamic>() ?? const {};
    final arousalVal = (affect['arousal'] as num?)?.toDouble() ?? (report['arousal'] as num?)?.toDouble() ?? 0.0;
    final valenceVal = (affect['valence'] as num?)?.toDouble() ?? (report['valence'] as num?)?.toDouble() ?? 0.5;

    final SessionMood mood;
    if (state.contains('Distressed')) {
      mood = SessionMood.distressed;
    } else if (state.contains('Anxious')) {
      mood = SessionMood.overloaded;
    } else if (state.contains('Excited') || (strokeCount >= 45 && arousalVal >= 0.40) || arousalVal >= 0.65) {
      // Intense scribbling / high kinetic energy
      mood = SessionMood.energetic;
    } else if (state.contains('Focused') || state.contains('Engaged')) {
      mood = SessionMood.focused;
    } else if (state.contains('Calm') || state.contains('Happy')) {
      mood = SessionMood.calm;
    } else {
      mood = (arousalVal > 0.55 || strokeCount > 40)
          ? SessionMood.energetic
          : (strokeCount > 15 ? SessionMood.focused : SessionMood.neutral);
    }

    final insightsList = (report['insights'] as List?)?.cast<String>() ??
        (rawJson['insights'] as List?)?.cast<String>() ??
        const <String>[];

    final recsList = (report['recommendations'] as List?)?.cast<String>() ??
        (rawJson['recommendations'] as List?)?.cast<String>() ??
        const <String>[];

    final simpleReport = report['simple_language_report'] as String? ??
        rawJson['simple_language_report'] as String? ??
        report['report_markdown'] as String?;

    final stimCat = report['stimulus_category'] as String? ?? rawJson['stimulus_category'] as String?;
    final stimImgId = report['stimulus_image_id'] as String? ?? rawJson['stimulus_image_id'] as String?;
    final stimReaction = report['stimulus_reaction_summary'] as String? ?? rawJson['stimulus_reaction_summary'] as String?;

    String? drawingRef = report['drawing_reference'] as String? ?? rawJson['drawing_reference'] as String?;
    if (drawingRef == null || drawingRef.isEmpty) {
      switch (stimCat?.toLowerCase()) {
        case 'animals':
          drawingRef = 'butterfly';
          break;
        case 'nature':
          drawingRef = 'tree';
          break;
        case 'objects':
          drawingRef = 'house';
          break;
        case 'people':
          drawingRef = 'star';
          break;
        default:
          drawingRef = 'sun';
      }
    }

    final strokes = (rawJson['drawing_strokes'] as List?)?.map((e) => (e as Map).cast<String, dynamic>()).toList();
    final facePred = (rawJson['facial_prediction'] as Map?)?.cast<String, dynamic>();
    final frames = (facePred?['frame_series'] as List?)?.map((e) => (e as Map).cast<String, dynamic>()).toList();

    return SessionRecord(
      id: report['session_id'] as String? ?? report['id'] as String? ?? '',
      date: DateTime.tryParse(report['created_at'] as String? ?? '') ?? DateTime.now(),
      recordingSeconds: 10,
      canvasSeconds: 20,
      mood: mood,
      valence: (affect['valence'] as num?)?.toDouble() ?? 0,
      arousal: (affect['arousal'] as num?)?.toDouble() ?? 0,
      dominance: (affect['dominance'] as num?)?.toDouble() ?? 0,
      strokeCount: (rawJson['stroke_count'] as num?)?.toInt() ?? 0,
      caregiverSummary: insightsList.firstOrNull ?? 'Detailed Caregiver Report available.',
      distressAlert: mood == SessionMood.distressed || mood == SessionMood.overloaded,
      stimulusCategory: stimCat,
      stimulusImageId: stimImgId,
      stimulusReactionSummary: stimReaction,
      simpleLanguageReport: simpleReport,
      drawingReference: drawingRef,
      drawingStrokes: strokes,
      frameSeries: frames,
      insights: insightsList,
      recommendations: recsList,
      therapistNotes: report['therapist_notes'] as String?,
      reviewedAt: report['reviewed_at'] != null ? DateTime.tryParse(report['reviewed_at'] as String) : null,
    );
  }

  SessionRecord copyWith({
    String? id,
    DateTime? date,
    int? recordingSeconds,
    int? canvasSeconds,
    SessionMood? mood,
    double? valence,
    double? arousal,
    double? dominance,
    int? strokeCount,
    String? caregiverSummary,
    bool? distressAlert,
    String? stimulusCategory,
    String? stimulusImageId,
    String? stimulusReactionSummary,
    String? simpleLanguageReport,
    String? drawingReference,
    List<Map<String, dynamic>>? drawingStrokes,
    List<Map<String, dynamic>>? frameSeries,
    List<String>? insights,
    List<String>? recommendations,
    String? therapistNotes,
    DateTime? reviewedAt,
  }) {
    return SessionRecord(
      id: id ?? this.id,
      date: date ?? this.date,
      recordingSeconds: recordingSeconds ?? this.recordingSeconds,
      canvasSeconds: canvasSeconds ?? this.canvasSeconds,
      mood: mood ?? this.mood,
      valence: valence ?? this.valence,
      arousal: arousal ?? this.arousal,
      dominance: dominance ?? this.dominance,
      strokeCount: strokeCount ?? this.strokeCount,
      caregiverSummary: caregiverSummary ?? this.caregiverSummary,
      distressAlert: distressAlert ?? this.distressAlert,
      stimulusCategory: stimulusCategory ?? this.stimulusCategory,
      stimulusImageId: stimulusImageId ?? this.stimulusImageId,
      stimulusReactionSummary: stimulusReactionSummary ?? this.stimulusReactionSummary,
      simpleLanguageReport: simpleLanguageReport ?? this.simpleLanguageReport,
      drawingReference: drawingReference ?? this.drawingReference,
      drawingStrokes: drawingStrokes ?? this.drawingStrokes,
      frameSeries: frameSeries ?? this.frameSeries,
      insights: insights ?? this.insights,
      recommendations: recommendations ?? this.recommendations,
      therapistNotes: therapistNotes ?? this.therapistNotes,
      reviewedAt: reviewedAt ?? this.reviewedAt,
    );
  }

  factory SessionRecord.mockFromSession({
    required int recordingSeconds,
    required int canvasSeconds,
    required int strokeCount,
    String? stimulusCategory,
    String? stimulusImageId,
    String? drawingReference,
    List<Map<String, dynamic>>? drawingStrokes,
  }) {
    final mood = strokeCount >= 45
        ? SessionMood.energetic
        : (strokeCount >= 15 ? SessionMood.focused : SessionMood.calm);
    final valence = strokeCount >= 45 ? 0.65 : 0.50;
    final arousal = strokeCount >= 45 ? 0.75 : (strokeCount >= 15 ? 0.45 : 0.20);
    const dominance = 0.60;
    final catName = stimulusCategory ?? 'Animals';

    return SessionRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      recordingSeconds: recordingSeconds,
      canvasSeconds: canvasSeconds,
      mood: mood,
      valence: valence,
      arousal: arousal,
      dominance: dominance,
      strokeCount: strokeCount,
      caregiverSummary: 'The session began with high positive curiosity toward $catName, transitioning into calm, regulated drawing.',
      distressAlert: false,
      stimulusCategory: stimulusCategory,
      stimulusImageId: stimulusImageId,
      stimulusReactionSummary: 'The child was delighted to explore pictures of $catName, showing relaxed eye contact and steady smiles.',
      simpleLanguageReport: 'Your child enjoyed selecting $catName today. Seeing their favorite theme helped them feel comfortable and calm, allowing them to draw with peaceful, rhythmic strokes.',
      drawingReference: drawingReference ?? 'sun',
      drawingStrokes: drawingStrokes,
      insights: [
        'Immediate positive engagement when viewing $catName imagery.',
        'Steady regulation score (95%) with smooth drawing flow.',
      ],
      recommendations: [
        'Use $catName imagery as a calming sensory transition before focused tasks.',
        'Celebrate their self-expression by displaying their drawing prominently.',
      ],
    );
  }
}
