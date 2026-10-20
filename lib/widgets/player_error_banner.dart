import 'package:flutter/material.dart';

/// Non-blocking error card with optional speech-recognition recovery actions.
class PlayerErrorBanner extends StatelessWidget {
  const PlayerErrorBanner({
    super.key,
    required this.message,
    this.isBusy = false,
    this.onRetry,
    this.onOpenSettings,
    this.onDismiss,
  });

  final String message;
  final bool isBusy;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = colors.onErrorContainer;

    return Material(
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Semantics(
            container: true,
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: 20,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: foreground,
                          height: 1.4,
                        ),
                      ),
                      if (isBusy ||
                          onRetry != null ||
                          onOpenSettings != null) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            if (isBusy)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                child: SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: foreground,
                                  ),
                                ),
                              ),
                            if (onRetry != null)
                              TextButton(
                                onPressed: isBusy ? null : onRetry,
                                style: TextButton.styleFrom(
                                  foregroundColor: foreground,
                                ),
                                child: Text(
                                  isBusy
                                      ? 'Starting captions…'
                                      : 'Retry captions',
                                ),
                              ),
                            if (onOpenSettings != null)
                              TextButton(
                                onPressed: isBusy ? null : onOpenSettings,
                                style: TextButton.styleFrom(
                                  foregroundColor: foreground,
                                ),
                                child: const Text('Open settings'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    tooltip: 'Dismiss error',
                    onPressed: onDismiss,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: foreground,
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
