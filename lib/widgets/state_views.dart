import 'package:flutter/material.dart';

/// Shared loading / error / empty states for lists, forms and dashboard cards.

class LoadingView extends StatelessWidget {
  final String label;
  const LoadingView({super.key, this.label = 'Yükleniyor'});

  @override
  Widget build(BuildContext context) => Center(child: CircularProgressIndicator(semanticsLabel: label));
}

/// Centered, scrollable (large text / small height never overflows) and announced by screen readers.
class _StateMessage extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String message;
  final Color messageColor;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StateMessage({
    required this.icon,
    required this.iconColor,
    required this.message,
    required this.messageColor,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 48),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: messageColor),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final errorText = Theme.of(context).colorScheme.onErrorContainer;
    return _StateMessage(
      icon: Icons.error_outline_rounded,
      iconColor: errorText,
      message: message,
      messageColor: errorText,
      actionLabel: 'Tekrar Dene',
      onAction: onRetry,
    );
  }
}

class EmptyView extends StatelessWidget {
  final String message;
  final IconData icon;

  /// Optional button under the message (e.g. "Yenile").
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyView({super.key, required this.message, this.icon = Icons.inbox_rounded, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return _StateMessage(
      icon: icon,
      iconColor: onSurface.withValues(alpha: 0.4),
      message: message,
      messageColor: onSurface.withValues(alpha: 0.75),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}
