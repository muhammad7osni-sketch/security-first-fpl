import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data_providers/models/player.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/dashboard_data.dart';
import 'dashboard_controller.dart';

/// Shown in two cases:
/// 1. User hasn't linked an FPL account → shows the correct link form.
/// 2. User has linked → shows the tactical pitch view.
///
/// ## Platform + configuration routing
///
/// ```
/// kIsWeb == false  → _buildNativeForm()   email+password, direct to FPL
/// kIsWeb == true
///   Env.hasFplLogin == true   → _buildWebEmailForm()  email+password
///   Env.hasFplLogin == false  → _buildWebTeamIdForm() manual Team ID
/// ```
///
/// The web email form attempts the FPL login service first.
/// If login fails, the error is displayed to the user.
class LinkFplAccountScreen extends ConsumerStatefulWidget {
  const LinkFplAccountScreen({super.key});

  @override
  ConsumerState<LinkFplAccountScreen> createState() =>
      _LinkFplAccountScreenState();
}

class _LinkFplAccountScreenState
    extends ConsumerState<LinkFplAccountScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSubmitting = false;
  String? _error;


  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Sign in with FPL email and password, then save the discovered Team ID.
  Future<void> _submitEmailPassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final result = await ref.read(fplAuthServiceProvider).fetchTeamId(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    // Never retain credentials after the request finishes.
    _emailController.clear();
    _passwordController.clear();

    if (!mounted) return;

    result.when(
      ok: (teamId) => _saveTeamId(teamId),
      err: (failure) {
        setState(() {
          _isSubmitting = false;
          _error = failure.message;
        });
      },
    );
  }

  /// Shared final step: validate ID against FPL public API, then persist.
  Future<void> _saveTeamId(int teamId) async {
    final linkResult =
        await ref.read(authRepositoryProvider).linkFplManagerId(teamId);

    if (!mounted) return;

    linkResult.when(
      ok: (_) {
        ref.invalidate(dashboardDataProvider);
      },
      err: (failure) {
        setState(() {
          _isSubmitting = false;
          _error = failure.message;
        });
      },
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ref.watch(dashboardDataProvider).when(
          loading: () => const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Scaffold(
            body: Center(
              child: Text(
                e.toString(),
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
          data: (data) {
            if (data != null) return _buildPitch(data);
            return _buildEmailPasswordForm();
          }
        );
  }

  // ─── Email + password form ────────────────────────────────────────────

  Widget _buildEmailPasswordForm() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: _appBar('Connect FPL Account'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              _buildHeader(
                title: 'Sign in with your FPL account',
                subtitle: 'Enter your FPL email and password. '
                    'Your password is not stored.',
              ),
              const SizedBox(height: 32),
              _emailField(),
              const SizedBox(height: 16),
              _passwordField(),
              const SizedBox(height: 12),
              _buildErrorBanner(),
              const SizedBox(height: 20),
              _buildSubmitButton(
                label: 'Connect FPL Account',
                onPressed: _submitEmailPassword,
              ),
              const SizedBox(height: 24),
              _buildSecurityNote(
                'Your password is used only for this sign-in request '
                'and is cleared afterward. Only your Team ID is saved.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Shared form widgets ────────────────────────────────────────────

  Widget _emailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(
        label: 'FPL Email',
        hint: 'your@email.com',
        icon: Icons.email_outlined,
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Email is required';
        if (!v.contains('@')) return 'Enter a valid email';
        return null;
      },
    );
  }

  Widget _passwordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: true,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(
        label: 'FPL Password',
        hint: '••••••••',
        icon: Icons.lock_outline,
      ),
      validator: (v) =>
          v == null || v.isEmpty ? 'Password is required' : null,
      onFieldSubmitted: (_) =>
          _isSubmitting ? null : _submitEmailPassword(),
    );
  }

  AppBar _appBar(String title) {
    return AppBar(
      title: Text(title),
      backgroundColor: const Color(0xFF1E293B),
      foregroundColor: Colors.white,
      elevation: 0,
    );
  }

  Widget _buildHeader({
    required String title,
    required String subtitle,
  }) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF15803D),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.sports_soccer,
            color: Colors.white,
            size: 40,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required Color iconColor,
    required Widget content,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: iconColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    if (_error == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.red.shade700,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton(
      onPressed: _isSubmitting ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF15803D),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: _isSubmitting
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }

  Widget _buildSecurityNote(String text) {
    return _buildInfoCard(
      icon: Icons.shield_outlined,
      iconColor: Colors.green,
      content: Text(
        text,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 12,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(
        icon,
        color: Colors.grey,
      ),
      labelStyle: const TextStyle(color: Colors.grey),
      hintStyle: const TextStyle(color: Colors.grey),
      filled: true,
      fillColor: const Color(0xFF1E293B),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFF334155),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFF15803D),
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Colors.red,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Colors.red,
          width: 2,
        ),
      ),
    );
  }

  // ─── Pitch view ─────────────────────────────────────────────────────

  Widget _buildPitch(DashboardData data) {
    final starters =
        data.squad.where((p) => p.isStarting).toList();

    final bench =
        data.squad.where((p) => !p.isStarting).toList();

    final gks = starters
        .where(
          (p) => p.player.position == PlayerPosition.goalkeeper,
        )
        .toList();

    final defs = starters
        .where(
          (p) => p.player.position == PlayerPosition.defender,
        )
        .toList();

    final mids = starters
        .where(
          (p) => p.player.position == PlayerPosition.midfielder,
        )
        .toList();

    final fwds = starters
        .where(
          (p) => p.player.position == PlayerPosition.forward,
        )
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(
          data.manager.teamName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.refresh,
              color: Colors.white,
            ),
            onPressed: () {
              ref.invalidate(dashboardDataProvider);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white30,
                  width: 2,
                ),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF166534),
                    Color(0xFF15803D),
                    Color(0xFF166534),
                  ],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildRow(fwds),
                  _buildRow(mids),
                  _buildRow(defs),
                  _buildRow(gks),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 16,
            ),
            color: const Color(0xFF1E293B),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bench',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                _buildRow(
                  bench,
                  isBench: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    List<DashboardSquadPlayer> players, {
    bool isBench = false,
  }) {
    if (players.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: players
          .map(
            (p) => _buildPlayerCard(
              p,
              isBench: isBench,
            ),
          )
          .toList(),
    );
  }

  Widget _buildPlayerCard(
    DashboardSquadPlayer entry, {
    bool isBench = false,
  }) {
    final name = entry.player.webName;
    final radius = isBench ? 22.0 : 26.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.topRight,
          children: [
            CircleAvatar(
              radius: radius,
              backgroundColor: entry.isAvailabilityRisk
                  ? Colors.red.shade900
                  : isBench
                      ? Colors.grey.shade800
                      : const Color(0xFF0F172A),
              child: Icon(
                Icons.person,
                color: entry.isAvailabilityRisk
                    ? Colors.red.shade300
                    : isBench
                        ? Colors.grey
                        : Colors.green.shade400,
                size: radius * 1.3,
              ),
            ),
            if (entry.isCaptain)
              const CircleAvatar(
                radius: 9,
                backgroundColor: Colors.amber,
                child: Text(
                  'C',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              )
            else if (entry.isViceCaptain)
              const CircleAvatar(
                radius: 9,
                backgroundColor: Colors.blue,
                child: Text(
                  'V',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (entry.isAvailabilityRisk)
          const Text(
            '⚠',
            style: TextStyle(
              fontSize: 10,
              color: Colors.orange,
            ),
          ),
      ],
    );
  }
}