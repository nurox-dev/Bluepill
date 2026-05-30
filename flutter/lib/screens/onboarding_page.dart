import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/profile_options.dart';
import '../models/model_helpers.dart';
import '../services/supabase_service.dart';
import '../ui/bp_card.dart';
import '../ui/expressive_card.dart';
import '../ui/expressive_loading_indicator.dart';
import '../ui/profile_fields.dart';

List<Color> _bgFor(ThemeData theme, int page) {
  if (page == 0) {
    return [
      theme.colorScheme.primary.withValues(alpha: 0.85),
      theme.colorScheme.surface,
    ];
  }
  return [
    theme.colorScheme.surfaceContainerLow,
    theme.colorScheme.surfaceContainerHigh,
  ];
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.onCompleted,
    this.initialProfile,
  });

  final VoidCallback onCompleted;
  final Map<String, dynamic>? initialProfile;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with TickerProviderStateMixin {
  late PageController _pageController;
  int _page = 0;

  final _name = TextEditingController();
  final _locationCity = TextEditingController();
  DateTime? _dob;
  String? _identityStage;

  List<String> _skills = [];
  List<String> _interests = [];
  List<String> _skillsToLearn = [];
  final _futureVision = TextEditingController();
  final _successDefinition = TextEditingController();

  bool _saving = false;

  late AnimationController _blobController;
  late AnimationController _progressController;
  late AnimationController _pulseController;

  static const _totalPages = 6;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 1);
    _blobController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _hydrate(widget.initialProfile);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _name.dispose();
    _locationCity.dispose();
    _futureVision.dispose();
    _successDefinition.dispose();
    _blobController.dispose();
    _progressController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
  }

  void _next() {
    if (_page < _totalPages - 1) {
      _progressController.forward(from: 0);
      _goTo(_page + 1);
    } else {
      _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([_blobController, _pulseController]),
        builder: (context, _) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _bgFor(theme, _page),
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  if (_page > 0) _buildTopBar(theme),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (p) => setState(() => _page = p),
                      itemCount: _totalPages,
                      itemBuilder: (context, index) {
                        return _buildScreen(index);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (_page > 1)
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => _goTo(_page - 1),
                )
              else
                const SizedBox(width: 48),
              const Spacer(),
              Text(
                        '$_page of ${_totalPages - 1}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 4),
          AnimatedBuilder(
            animation: _progressController,
            builder: (context, _) {
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: (_page) / (_totalPages - 1)),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
                builder: (context, value, _) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 4,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScreen(int index) {
    return switch (index) {
      0 => _welcomeScreen(),
      1 => _basicsScreen(),
      2 => _identityScreen(),
      3 => _skillsInterestsScreen(),
      4 => _futureVisionScreen(),
      _ => _finalProfileScreen(),
    };
  }

  // ───── Screen 0: Welcome ─────

  Widget _welcomeScreen() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Spacer(flex: 2),
            AnimatedBuilder(
              animation: _blobController,
              builder: (context, _) {
                return Transform.translate(
                  offset: Offset(
                    math.sin(_blobController.value * 2 * math.pi) * 6,
                    math.cos(_blobController.value * 2 * math.pi) * 6,
                  ),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.secondary,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: 0.4),
                          blurRadius: 30,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text('👋', style: TextStyle(fontSize: 36)),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              "Let's create your\npersonal growth roadmap.",
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Takes about 1 minute. Built just for you.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(flex: 2),
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return Transform.scale(
                  scale: 1.0 + _pulseController.value * 0.03,
                  child: FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(200, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      textStyle: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: const Text('✨ Start'),
                  ),
                );
              },
            ),
            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }

  // ───── Screen 1: Your Basics ─────

  Widget _basicsScreen() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text('Your Basics', style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
          )),
          const SizedBox(height: 6),
          Text(
            'Start with the details we should know about you.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          BpCard(
            child: Form(
              key: UniqueKey(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),
                  CityAutocompleteField(controller: _locationCity, required: true),
                  const SizedBox(height: 14),
                  DatePickerField(
                    label: 'Date of birth',
                    value: _dob,
                    required: true,
                    onChanged: (v) => setState(() => _dob = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: FilledButton(
              onPressed: () {
                if (_name.text.trim().isEmpty ||
                    _locationCity.text.trim().isEmpty ||
                    _dob == null) {
                  return;
                }
                _next();
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(27),
                ),
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Text('Nice to meet you${_name.text.trim().isEmpty ? '' : ', ${_name.text.trim()}'} 👋'),
            ),
          ),
        ],
      ),
    );
  }

  // ───── Screen 2: Identity Stage ─────

  Widget _identityScreen() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text('Which best describes you today?',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
              )),
          const SizedBox(height: 24),
          ...identityStageOptions.map((option) {
            final emoji = option.$1;
            final label = option.$2;
            final value = option.$3;
            final selected = _identityStage == value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ExpressiveCard(
                selected: selected,
                onTap: () => setState(() => _identityStage = value),
                child: Row(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 16),
                    Text(label, style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          if (_identityStage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _identityFeedback(_identityStage!),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          Center(
            child: FilledButton(
              onPressed: _identityStage == null ? null : _next,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(27),
                ),
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }

  String _identityFeedback(String stage) {
    return switch (stage) {
      'student' => 'Great—this is where many high-growth journeys begin.',
      'early_career' => 'The early years compound the most. Smart move.',
      'entrepreneur' => 'Bold path. We will help you build systems that scale.',
      'professional' => 'Solid foundation to accelerate from.',
      'planning_retirement' => 'Freedom by design. Let us map the route.',
      _ => 'Every journey starts with a single step.',
    };
  }

  // ───── Screen 3: Skills & Interests ─────

  Widget _skillsInterestsScreen() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text('Skills & Interests',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
              )),
          const SizedBox(height: 6),
          Text(
            'What you want to learn and what excites you.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text('Skills to Learn',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: skillsToLearnOptions.map((option) {
              final selected = _skillsToLearn.contains(option);
              return FilterChip(
                selected: selected,
                label: Text(option),
                onSelected: (sel) {
                  setState(() {
                    if (sel) {
                      _skillsToLearn.add(option);
                    } else {
                      _skillsToLearn.remove(option);
                    }
                  });
                },
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          Text('Interests',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: interestOptions.map((option) {
              final selected = _interests.contains(option);
              return FilterChip(
                selected: selected,
                label: Text(option),
                onSelected: (sel) {
                  setState(() {
                    if (sel) {
                      _interests.add(option);
                    } else {
                      _interests.remove(option);
                    }
                  });
                },
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Center(
            child: FilledButton(
              onPressed: (_skillsToLearn.isEmpty && _interests.isEmpty)
                  ? null
                  : _next,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(27),
                ),
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }

  // ───── Screen 8: Future Vision ─────

  Widget _futureVisionScreen() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text("Imagine it's 5 years from now.",
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
              )),
          const SizedBox(height: 6),
          Text(
            'What would make you proud?',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          BpCard(
            child: TextFormField(
              controller: _futureVision,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Your 5-year vision',
                alignLabelWithHint: true,
                hintText:
                    'I see myself running a company that impacts millions...',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Define success in one sentence.',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 12),
          BpCard(
            child: TextFormField(
              controller: _successDefinition,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Success definition',
                alignLabelWithHint: true,
                hintText: 'Living life on my own terms...',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: FilledButton(
              onPressed: _futureVision.text.trim().isEmpty ? null : _next,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(27),
                ),
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('See My Future Profile ✨'),
            ),
          ),
        ],
      ),
    );
  }

  // ───── Screen 9: AI Identity Profile (Final) ─────

  Widget _finalProfileScreen() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: _saving
          ? SizedBox(
              height: 300,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ExpressiveLoadingIndicator(),
                    const SizedBox(height: 16),
                    Text('Building your roadmap...',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                  ],
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Text('✨ Your Future Profile',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    )),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      width: 2,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.surfaceContainerLow,
                        theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.2),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _profileSection(theme, 'Focus Areas',
                          _interests, Icons.explore_outlined),
                      const Divider(height: 24),
                      Text('Recommended Path',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          )),
                      const SizedBox(height: 8),
                      ..._recommendedPaths().map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(Icons.arrow_forward_rounded, size: 16,
                                color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(p, style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      )),
                      const Divider(height: 24),
                      Text('AI Narrative',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          )),
                      const SizedBox(height: 8),
                      Text(
                        _aiNarrative(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    textStyle: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Text('🚀 Build My Roadmap'),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _saving ? null : () => _goTo(0),
                    child: const Text('Edit Profile'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _profileSection(
      ThemeData theme, String title, List<String> items, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(title, style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            )),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Text('None selected', style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: items.map((item) => Chip(
              label: Text(item, style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelPadding: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            )).toList(),
          ),
      ],
    );
  }

  List<String> _recommendedPaths() {
    final paths = <String>[];
    final vision = _futureVision.text.trim();
    if (vision.contains('business') || vision.contains('startup') ||
        vision.contains('company')) {
      paths.add('Business building');
    }
    if (vision.contains('free') || vision.contains('income') ||
        vision.contains('financial')) {
      paths.add('Financial systems');
    }
    if (_identityStage == 'student' || _identityStage == 'early_career') {
      paths.add('Skill development');
    }
    if (paths.isEmpty) {
      paths.add('Personal growth foundations');
    }
    return paths.take(4).toList();
  }

  String _aiNarrative() {
    final name = _name.text.trim().isNotEmpty ? _name.text.trim() : 'you';
    final stage = identityStageOptions
        .firstWhere((o) => o.$3 == _identityStage,
            orElse: () => ('', 'growing', ''))
        .$2
        .toLowerCase();

    return '$name is a $stage individual with a clear vision for the future. '
        'With interests in ${_interests.take(3).join(', ')} '
        'and skills to learn including ${_skillsToLearn.take(3).join(', ')}, '
        'the foundation is strong for accelerated growth. '
        'The path ahead emphasizes '
        '${_recommendedPaths().join(', ').toLowerCase()}. '
        'This personalized roadmap is built to turn vision into reality.';
  }

  // ───── Save ─────

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await SupabaseService.client.from('users_profile').upsert(
        {
          'user_id': SupabaseService.currentUserId,
          'name': _name.text.trim(),
          'location_city': _locationCity.text.trim(),
          'dob': _dob == null ? null : dateKey(_dob!),
          'dream_goal': _futureVision.text.trim().isNotEmpty
              ? _futureVision.text.trim()
              : 'Personal growth journey',
          'identity_stage': _identityStage,
          'skills': _skills,
          'interests': _interests,
          'skills_to_learn': _skillsToLearn,
          'future_vision': _futureVision.text.trim(),
          'success_definition': _successDefinition.text.trim(),
        },
        onConflict: 'user_id',
      );

      if (!mounted) return;
      widget.onCompleted();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _hydrate(Map<String, dynamic>? profile) {
    if (profile == null) return;
    _name.text = profile['name']?.toString() ?? '';
    _locationCity.text = profile['location_city']?.toString() ?? '';
    _dob = DateTime.tryParse(profile['dob']?.toString() ?? '');
    _identityStage = profile['identity_stage']?.toString();
    _skills = _stringList(profile['skills']);
    _interests = _stringList(profile['interests']);
    _skillsToLearn = _stringList(profile['skills_to_learn']);
    _futureVision.text = profile['future_vision']?.toString() ?? '';
    _successDefinition.text = profile['success_definition']?.toString() ?? '';
  }

  List<String> _stringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }
}
