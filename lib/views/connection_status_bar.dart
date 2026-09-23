import 'package:flutter/material.dart';

class ConnectionStatusBar extends StatelessWidget {
  final String? clusterName;
  final String host;
  final bool isSslEnabled;
  final VoidCallback? onTap;

  const ConnectionStatusBar({
    super.key,
    this.clusterName,
    required this.host,
    required this.isSslEnabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCluster = clusterName != null && clusterName!.isNotEmpty;

    final body = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.dns, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: 'Connected to ',
                  children: [
                    if (hasCluster) ...[
                      TextSpan(
                        text: clusterName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: ' on '),
                    ],
                    TextSpan(
                      text: host,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text: isSslEnabled ? ' with ssl' : ' without ssl',
                    ),
                  ],
                ),
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: isSslEnabled ? 'SSL/TLS Encrypted' : 'Unencrypted Connection',
              child: Icon(
                isSslEnabled ? Icons.lock : Icons.lock_open,
                size: 14,
                color: isSslEnabled ? theme.colorScheme.primary : Colors.amber.shade700,
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap != null) {
      return Material(
        color: theme.colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: onTap,
          child: Tooltip(
            message: 'Click to open Connection Settings',
            child: body,
          ),
        ),
      );
    }

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: body,
    );
  }
}
