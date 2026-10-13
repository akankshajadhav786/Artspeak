import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/child_profile.dart';
import '../models/session_record.dart';

class ArtSpeakRepository {
  SupabaseClient get _client => Supabase.instance.client;

  User get currentUser {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Please sign in first.');
    return user;
  }

  bool get hasActiveSession => _client.auth.currentSession != null;
  User? get currentSessionUser => _client.auth.currentUser;

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      debugPrint('Notice signing out: $e');
    }
  }

  Future<String?> getCurrentUserRole() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final metaRole = user.userMetadata?['role'] as String?;
    if (metaRole != null && metaRole.isNotEmpty) return metaRole.toLowerCase();

    try {
      final t = await _client.from('therapists').select('id').eq('id', user.id).maybeSingle();
      if (t != null) return 'therapist';
    } catch (_) {}

    try {
      final c = await _client.from('caregivers').select('id').eq('id', user.id).maybeSingle();
      if (c != null) return 'caregiver';
    } catch (_) {}

    return 'caregiver';
  }

  String authErrorMessage(Object error) {
    if (error is http.ClientException) {
      return 'Unable to reach Supabase. Check the Supabase URL, internet connection, and browser network access.';
    }
    if (error is AuthException) {
      final message = error.message.toLowerCase();
      if (message.contains('invalid login credentials')) return 'Email or password is incorrect.';
      if (message.contains('email not confirmed')) return 'Confirm your email address before signing in.';
      if (message.contains('password')) return error.message;
      return error.message;
    }
    if (error is PostgrestException) {
      return error.message;
    }
    return error.toString();
  }

  Future<void> signUpCaregiver({
    required String email,
    required String password,
    required String name,
    required int age,
    required String gender,
    required String relationWithChild,
  }) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'role': 'caregiver',
        'name': name,
        'age': age.toString(),
        'gender': gender,
        'relation_with_child': relationWithChild,
      },
    );
  }

  Future<String> signUpTherapist({
    required String name,
    required int age,
    required String gender,
    required String qualification,
    required String licenseNumber,
    required String contactEmail,
    required String password,
  }) async {
    final username = await _client.rpc('generate_unique_therapist_username', params: {'p_full_name': name}) as String;
    final loginEmail = '$username@artspeak.internal';
    await _client.auth.signUp(
      email: loginEmail,
      password: password,
      data: {
        'role': 'therapist',
        'name': name,
        'age': age.toString(),
        'gender': gender,
        'qualification': qualification,
        'license_number': licenseNumber,
        'contact_email': contactEmail,
        'username': username,
      },
    );
    return username;
  }

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signInTherapist({required String username, required String password}) async {
    final loginEmail = await _client.rpc('get_therapist_login_email', params: {'p_username': username});
    if (loginEmail == null) throw StateError('This therapist account is not verified yet.');
    await _client.auth.signInWithPassword(email: loginEmail as String, password: password);
  }

  Future<String> createChild(ChildProfile profile, {String? therapistId}) async {
    final payload = <String, dynamic>{
      'caregiver_id': currentUser.id,
      'name': profile.name,
      'age': profile.age,
      'gender': profile.gender.databaseValue,
      'conditions': _asTags(profile.condition),
      'hobbies': _asTags(profile.hobbies),
      'known_triggers': _asTags(profile.knownTriggers),
      'calming_activities': _asTags(profile.calmingActivities),
      'needs_therapist': profile.therapistNeeded,
    };
    final row = await _client.from('children').insert(payload).select('id').single();
    final childId = row['id'] as String;

    if (profile.therapistNeeded && therapistId != null) {
      await assignTherapist(childId: childId, therapistId: therapistId);
    }
    return childId;
  }

  Future<void> assignTherapist({required String childId, required String therapistId}) async {
    const baseUrl = String.fromEnvironment('INFERENCE_API_URL');
    final url = baseUrl.isNotEmpty ? baseUrl : 'http://127.0.0.1:8000';
    try {
      final response = await http.post(
        Uri.parse('$url/assign-therapist'),
        headers: {
          'Authorization': 'Bearer ${_client.auth.currentSession?.accessToken ?? ''}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'child_id': childId,
          'therapist_id': therapistId,
        }),
      );
      if (response.statusCode >= 300) {
        debugPrint('assignTherapist returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('assignTherapist exception: $e');
    }

    // Direct Supabase fallback
    try {
      await _client.from('child_therapist_assignments').update({'active': false}).eq('child_id', childId);
      await _client.from('child_therapist_assignments').insert({
        'child_id': childId,
        'therapist_id': therapistId,
        'assigned_by': currentUser.id,
        'active': true,
      });
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> loadRegisteredTherapists() async {
    const baseUrl = String.fromEnvironment('INFERENCE_API_URL');
    final url = baseUrl.isNotEmpty ? baseUrl : 'http://127.0.0.1:8000';
    try {
      final response = await http.get(
        Uri.parse('$url/therapists'),
        headers: {
          'Authorization': 'Bearer ${_client.auth.currentSession?.accessToken ?? ''}',
        },
      );
      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body);
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error loading therapists from API: $e');
    }
    try {
      final rows = await _client.from('therapists').select('id, name, qualification, license_number');
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error loading therapists from Supabase: $e');
      return [];
    }
  }

  List<String> _asTags(String? value) => value == null || value.trim().isEmpty
      ? <String>[]
      : value.split(',').map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toList();

  Future<String> createSession({
    required String childId,
    required int durationSeconds,
    String? stimulusCategory,
    String? stimulusImageId,
  }) async {
    final payload = <String, dynamic>{
      'caregiver_id': currentUser.id,
      'child_id': childId,
      'video_duration_seconds': durationSeconds,
      'art_duration_seconds': durationSeconds,
    };
    if (stimulusCategory != null) payload['stimulus_category'] = stimulusCategory;
    if (stimulusImageId != null) payload['stimulus_image_id'] = stimulusImageId;
    payload['stimulus_duration_seconds'] = 10;

    final row = await _client.from('sessions').insert(payload).select('id').single();
    return row['id'] as String;
  }

  Future<void> updateSessionStimulus({
    required String sessionId,
    required String stimulusCategory,
    required String stimulusImageId,
  }) async {
    await _client.from('sessions').update({
      'stimulus_category': stimulusCategory,
      'stimulus_image_id': stimulusImageId,
    }).eq('id', sessionId);
  }

  Future<void> saveTouchEvents(String sessionId, List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;
    await _client.from('session_touch_events').insert(
      events.map((event) => {...event, 'session_id': sessionId}).toList(),
    );
  }

  Future<void> saveVideo(String sessionId, Uint8List videoBytes, int durationSeconds) async {
    final path = '${currentUser.id}/$sessionId.mp4';
    await _client.storage.from('session-videos').uploadBinary(
          path,
          videoBytes,
          fileOptions: const FileOptions(upsert: false, contentType: 'video/mp4'),
        );
    await _client.from('session_video_recordings').insert({
      'session_id': sessionId,
      'storage_path': path,
      'duration_seconds': durationSeconds,
    });
  }

  Future<void> markProcessing(String sessionId) async {
    await _client.from('sessions').update({'status': 'processing', 'ended_at': DateTime.now().toIso8601String()}).eq('id', sessionId);
  }

  Future<void> requestInference(
    String sessionId, {
    String? drawingReference,
    List<Map<String, dynamic>>? drawingStrokes,
    String? stimulusCategory,
    String? stimulusImageId,
  }) async {
    const baseUrl = String.fromEnvironment('INFERENCE_API_URL');
    final url = baseUrl.isNotEmpty ? baseUrl : 'http://127.0.0.1:8000';
    try {
      final response = await http.post(
        Uri.parse('$url/process/$sessionId'),
        headers: {
          'Authorization': 'Bearer ${_client.auth.currentSession?.accessToken ?? ''}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'session_id': sessionId,
          'drawing_reference': drawingReference,
          'drawing_strokes': drawingStrokes,
          'stimulus_category': stimulusCategory,
          'stimulus_image_id': stimulusImageId,
        }),
      );
      if (response.statusCode >= 300) {
        // Log inference error without crashing the user's workflow
        debugPrint('Inference request returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('Inference request exception: $e');
    }
  }

  Future<SessionRecord?> fetchSessionReport(String sessionId) async {
    try {
      final report = await _client.from('session_reports').select().eq('session_id', sessionId).maybeSingle();
      if (report != null) {
        return SessionRecord.fromReport(report);
      }
    } catch (e) {
      debugPrint('Error fetching session report: $e');
    }
    return null;
  }

  Future<void> saveDrawingMetadata({
    required String sessionId,
    required String drawingReference,
    required List<Map<String, dynamic>> strokes,
  }) async {
    try {
      // Store in session touch events or report json
      await _client.from('sessions').update({
        'status': 'completed',
      }).eq('id', sessionId);
    } catch (_) {}
  }

  Future<List<SessionRecord>> loadChildSessions(String childId) async {
    try {
      final reports = await _client
          .from('session_reports')
          .select()
          .eq('child_id', childId)
          .order('created_at', ascending: true);
      final list = (reports as List)
          .map<SessionRecord>((report) => SessionRecord.fromReport(report as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => a.date.compareTo(b.date));
      return list;
    } catch (e) {
      debugPrint('Error loading child sessions: $e');
      return [];
    }
  }

  Future<List<ChildProfile>> loadCaregiverChildren() async {
    try {
      final rows = await _client
          .from('children')
          .select()
          .eq('caregiver_id', currentUser.id)
          .order('created_at', ascending: false);
      final List<ChildProfile> profiles = [];
      for (final child in (rows as List)) {
        final childId = child['id'] as String;
        final sessions = await loadChildSessions(childId);
        profiles.add(ChildProfile(
          id: childId,
          name: child['name'] as String? ?? 'Child',
          age: child['age'] as int? ?? 5,
          gender: childGenderFromDatabase(child['gender'] as String?),
          condition: (child['conditions'] as List?)?.cast<String>().join(', '),
          hobbies: (child['hobbies'] as List?)?.cast<String>().join(', '),
          knownTriggers: (child['known_triggers'] as List?)?.cast<String>().join(', '),
          calmingActivities: (child['calming_activities'] as List?)?.cast<String>().join(', '),
          therapistNeeded: child['needs_therapist'] as bool? ?? false,
          sessions: sessions,
        ));
      }
      return profiles;
    } catch (e) {
      debugPrint('Error loading caregiver children: $e');
      return [];
    }
  }

  Future<List<ChildProfile>> loadTherapistRoster() async {
    final assignments = await _client.from('child_therapist_assignments').select('child_id').eq('therapist_id', currentUser.id).eq('active', true);
    final roster = <ChildProfile>[];
    for (final assignment in assignments) {
      final child = await _client.from('children').select().eq('id', assignment['child_id']).single();
      final reports = await _client.from('session_reports').select().eq('child_id', child['id']).order('created_at', ascending: true);
      final sessions = reports.map<SessionRecord>((report) => SessionRecord.fromReport(report)).toList();
      sessions.sort((a, b) => a.date.compareTo(b.date));
      roster.add(ChildProfile(
        id: child['id'],
        name: child['name'],
        age: child['age'],
        gender: childGenderFromDatabase(child['gender']),
        condition: (child['conditions'] as List?)?.cast<String>().join(', '),
        hobbies: (child['hobbies'] as List?)?.cast<String>().join(', '),
        knownTriggers: (child['known_triggers'] as List?)?.cast<String>().join(', '),
        calmingActivities: (child['calming_activities'] as List?)?.cast<String>().join(', '),
        therapistNeeded: child['needs_therapist'] as bool? ?? false,
        sessions: sessions,
      ));
    }
    // Sort roster so latest patient with most recent session activity appears on top
    roster.sort((a, b) {
      final aDate = a.sessions.isNotEmpty
          ? a.sessions.map((s) => s.date).reduce((x, y) => x.isAfter(y) ? x : y)
          : DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.sessions.isNotEmpty
          ? b.sessions.map((s) => s.date).reduce((x, y) => x.isAfter(y) ? x : y)
          : DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return roster;
  }

  Future<bool> saveTherapistNotes({
    required String sessionId,
    required String notes,
  }) async {
    try {
      final nowUtc = DateTime.now().toUtc().toIso8601String();
      final user = _client.auth.currentUser;
      final updateData = <String, dynamic>{
        'therapist_notes': notes,
        'reviewed_at': nowUtc,
      };
      if (user != null) {
        updateData['reviewed_by_therapist_id'] = user.id;
      }
      await _client.from('session_reports').update(updateData).eq('session_id', sessionId);
      return true;
    } catch (e) {
      debugPrint('Error saving therapist notes: $e');
      return false;
    }
  }
}

final artSpeakRepository = ArtSpeakRepository();