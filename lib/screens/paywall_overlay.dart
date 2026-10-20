import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';

/// Blocking activation surface shown after the free trial ends and whenever
/// an activation link/key needs attention.
class PaywallOverlay extends StatelessWidget {
  const PaywallOverlay({
    super.key,
    required this.controller,
    required this.statusMessage,
    required this.onActivate,
    required this.onOpenPricing,
    this.isLoading = false,
  });

  final TextEditingController controller;
  final String statusMessage;
  final VoidCallback onActivate;
  final VoidCallback onOpenPricing;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trialMinutes = AppConfig.freeTrialDuration.inMinutes;

    return Material(
      color: const Color(0xF70C0D10),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  color: AppTheme.accent,
                  size: 44,
                ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(
                    'Your $trialMinutes-minute free trial has ended.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Unlock unlimited live captions on this device with a '
                  'monthly or lifetime activation.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: isLoading ? null : onOpenPricing,
                  child: const Text(AppConfig.monthlyPlanLabel),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: isLoading ? null : onOpenPricing,
                  child: const Text(AppConfig.lifetimePlanLabel),
                ),
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 22),
                Text(
                  'Already purchased?',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Paste the license key from your purchase email.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  enabled: !isLoading,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.visiblePassword,
                  maxLength: AppConfig.maxLicenseKeyLength,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Activation license key',
                    hintText: 'Paste your key',
                    counterText: '',
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                  onSubmitted: (_) {
                    if (!isLoading) onActivate();
                  },
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: isLoading ? null : onActivate,
                  child: isLoading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Activate player'),
                ),
                if (statusMessage.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      statusMessage,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.accent,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  'Activation is tied to this app installation. Keep your '
                  'license key safe for reinstalls. Need help? '
                  '${AppConfig.supportEmail}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white38,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
