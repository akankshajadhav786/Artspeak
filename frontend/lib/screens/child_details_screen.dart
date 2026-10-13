import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/child_profile.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../services/art_speak_repository.dart';
import 'caregiver_dashboard_screen.dart';
import 'welcome_screen.dart';

const _conditions = [
  'Autism Spectrum Disorder',
  'ADHD',
  'Sensory Processing Disorder',
  'Speech / Language Delay',
  'Other / Not specified',
];

class ChildDetailsScreen extends StatefulWidget {
  /// When true (default) this is the very first child added right after
  /// caregiver login, so submitting takes the caregiver straight into the
  /// dashboard. When false, this screen was opened from the dashboard
  /// sidebar's "Add Child" action, so submitting just pops the new
  /// [ChildProfile] back to the dashboard to be appended to the list.
  final bool isFirstProfile;
  const ChildDetailsScreen({super.key, this.isFirstProfile = true});

  @override
  State<ChildDetailsScreen> createState() => _ChildDetailsScreenState();
}

class _ChildDetailsScreenState extends State<ChildDetailsScreen> {
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _hobbiesCtrl = TextEditingController();
  final _triggersCtrl = TextEditingController();
  final _calmingCtrl = TextEditingController();
  String? _condition;
  ChildGender? _gender;
  bool? _therapistNeeded;
  String? _selectedTherapistId;
  List<Map<String, dynamic>> _registeredTherapists = [];
  bool _loadingTherapists = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _fetchTherapists();
  }

  Future<void> _fetchTherapists() async {
    setState(() => _loadingTherapists = true);
    try {
      final list = await artSpeakRepository.loadRegisteredTherapists();
      if (mounted) {
        setState(() {
          _registeredTherapists = list;
          _loadingTherapists = false;
          if (_registeredTherapists.isNotEmpty && _selectedTherapistId == null) {
            _selectedTherapistId = _registeredTherapists.first['id'] as String;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTherapists = false);
    }
  }

  int? get _parsedAge => int.tryParse(_ageCtrl.text.trim());

  bool get _isAgeValid {
    final age = _parsedAge;
    return age != null && age >= 4 && age <= 13;
  }

  String? get _ageError {
    final text = _ageCtrl.text.trim();
    if (text.isEmpty) return null;
    final age = int.tryParse(text);
    if (age == null) return 'Enter a valid number';
    if (age < 4 || age > 13) return 'Age must be 4 to 13';
    return null;
  }

  bool get _canSubmit =>
      _nameCtrl.text.trim().isNotEmpty &&
      _isAgeValid &&
      _gender != null &&
      _therapistNeeded != null &&
      (_therapistNeeded == false || _selectedTherapistId != null);

  Future<void> _submit() async {
    if (!_isAgeValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid age between 4 and 13.')),
      );
      return;
    }
    final profile = ChildProfile(
      name: _nameCtrl.text.trim(),
      age: _parsedAge!,
      gender: _gender!,
      condition: _condition,
      hobbies: _hobbiesCtrl.text.trim().isEmpty ? null : _hobbiesCtrl.text.trim(),
      knownTriggers: _triggersCtrl.text.trim().isEmpty ? null : _triggersCtrl.text.trim(),
      calmingActivities: _calmingCtrl.text.trim().isEmpty ? null : _calmingCtrl.text.trim(),
      therapistNeeded: _therapistNeeded!,
    );
    setState(() => _busy = true);
    try {
      final childId = await artSpeakRepository.createChild(
        profile,
        therapistId: _therapistNeeded == true ? _selectedTherapistId : null,
      );
      final savedProfile = ChildProfile(
        id: childId,
        name: profile.name,
        age: profile.age,
        gender: profile.gender,
        condition: profile.condition,
        hobbies: profile.hobbies,
        knownTriggers: profile.knownTriggers,
        calmingActivities: profile.calmingActivities,
        therapistNeeded: profile.therapistNeeded,
      );
      if (!mounted) return;
      if (widget.isFirstProfile) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => CaregiverDashboardScreen(initialProfile: savedProfile)));
      } else {
        Navigator.of(context).pop(savedProfile);
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackdrop(
        child: SafeArea(
          child: Stack(
            children: [
              BackPill(onTap: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                    (r) => false,
                  );
                }
              }),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 90),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    constraints: const BoxConstraints(maxWidth: 480),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 24, offset: const Offset(0, 12))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ArtSpeakLogo(size: 38),
                        const SizedBox(height: 26),
                        if (widget.isFirstProfile) ...[
                          const StepHeader(activeStep: 2),
                          const SizedBox(height: 24),
                        ],
                        Text(widget.isFirstProfile ? 'Child Details' : 'Add a Child',
                            style: GoogleFonts.fredoka(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                        const SizedBox(height: 6),
                        Text('Tell us about the child you are supporting.',
                            style: GoogleFonts.nunito(color: AppColors.textMuted, fontSize: 14.5)),
                        const SizedBox(height: 24),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _field(
                                label: "Child's Name *",
                                child: TextField(
                                  controller: _nameCtrl,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(hintText: 'e.g. Lily'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _field(
                                label: 'Age (4–13) *',
                                child: TextField(
                                  controller: _ageCtrl,
                                  onChanged: (_) => setState(() {}),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(2),
                                  ],
                                  decoration: InputDecoration(
                                    hintText: '4–13',
                                    errorText: _ageError,
                                    helperText: _ageError == null ? '4 to 13 years' : null,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        _field(
                          label: 'Gender *',
                          child: DropdownButtonFormField<ChildGender>(
                            value: _gender,
                            decoration: const InputDecoration(hintText: 'Select gender'),
                            items: ChildGender.values
                                .map((g) => DropdownMenuItem(value: g, child: Text(g.label)))
                                .toList(),
                            onChanged: (v) => setState(() => _gender = v),
                          ),
                        ),
                        const SizedBox(height: 18),

                        _field(
                          label: 'Condition / Diagnosis',
                          child: DropdownButtonFormField<String>(
                            value: _condition,
                            decoration: const InputDecoration(hintText: 'Select condition'),
                            items: _conditions
                                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                .toList(),
                            onChanged: (v) => setState(() => _condition = v),
                          ),
                        ),
                        const SizedBox(height: 18),

                        _field(
                          label: 'Hobbies / Favorite Activities',
                          child: TextField(
                            controller: _hobbiesCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(hintText: 'e.g. Puzzles, drawing, music'),
                          ),
                        ),
                        const SizedBox(height: 18),

                        _field(
                          label: 'Known Triggers',
                          child: TextField(
                            controller: _triggersCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(hintText: 'e.g. Loud noises, sudden changes in routine'),
                          ),
                        ),
                        const SizedBox(height: 18),

                        _field(
                          label: 'Calming Activities',
                          child: TextField(
                            controller: _calmingCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(hintText: 'e.g. Deep breathing, weighted blanket, quiet corner'),
                          ),
                        ),
                        const SizedBox(height: 18),

                        _field(
                          label: 'Is a Therapist Needed? *',
                          child: DropdownButtonFormField<bool>(
                            value: _therapistNeeded,
                            decoration: const InputDecoration(hintText: 'Select an option'),
                            items: const [
                              DropdownMenuItem(value: true, child: Text('Yes - Connect with Licensed Therapist / Doctor')),
                              DropdownMenuItem(value: false, child: Text('No - Home / Caregiver Monitoring Only')),
                            ],
                            onChanged: (v) {
                              setState(() {
                                _therapistNeeded = v;
                                if (v == true && _registeredTherapists.isEmpty && !_loadingTherapists) {
                                  _fetchTherapists();
                                }
                              });
                            },
                          ),
                        ),
                        if (_therapistNeeded == true) ...[
                          const SizedBox(height: 18),
                          _field(
                            label: 'Select Therapist or Doctor *',
                            child: _loadingTherapists
                                ? Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                        ),
                                        const SizedBox(width: 12),
                                        Text('Loading verified therapists & doctors…',
                                            style: GoogleFonts.nunito(fontSize: 13, color: AppColors.textMuted)),
                                      ],
                                    ),
                                  )
                                : DropdownButtonFormField<String>(
                                    value: _selectedTherapistId,
                                    isExpanded: true,
                                    isDense: false,
                                    itemHeight: 64.0,
                                    decoration: const InputDecoration(
                                      hintText: 'Select a registered specialist',
                                      prefixIcon: Icon(Icons.medical_services_outlined, color: AppColors.primary),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    ),
                                    selectedItemBuilder: (BuildContext context) {
                                      return _registeredTherapists.map((t) {
                                        final name = t['name'] as String? ?? 'Specialist';
                                        final qual = t['qualification'] as String? ?? '';
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.fredoka(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13.5,
                                                color: AppColors.primaryDark,
                                              ),
                                            ),
                                            if (qual.isNotEmpty)
                                              Text(
                                                qual,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.nunito(
                                                  fontSize: 11,
                                                  color: AppColors.textMuted,
                                                  height: 1.1,
                                                ),
                                              ),
                                          ],
                                        );
                                      }).toList();
                                    },
                                    items: _registeredTherapists.map((t) {
                                      final name = t['name'] as String? ?? 'Specialist';
                                      final qual = t['qualification'] as String? ?? '';
                                      return DropdownMenuItem<String>(
                                        value: t['id'] as String,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(name,
                                                style: GoogleFonts.fredoka(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 13.5,
                                                    color: AppColors.primaryDark)),
                                            if (qual.isNotEmpty)
                                              Text(qual,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: GoogleFonts.nunito(
                                                      fontSize: 11,
                                                      color: AppColors.textMuted,
                                                      height: 1.1)),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (v) => setState(() => _selectedTherapistId = v),
                                  ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.verified_user_rounded, color: Color(0xFF2563EB), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'All clinical reports will be securely assigned and routed exclusively to the selected specialist.',
                                    style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF1E40AF)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'No photo is collected — ArtSpeak keeps session data local to this device.',
                          style: GoogleFonts.nunito(fontSize: 12, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 22),
                        PrimaryButton(
                          label: widget.isFirstProfile ? 'Go to Dashboard' : 'Save Profile',
                          enabled: _canSubmit,
                          onPressed: _busy ? null : _submit,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.fredoka(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
