import 'dart:async';
import 'package:flutter/material.dart';

class ConnectionStatusBar extends StatefulWidget {
  final String? clusterName;
  final String host;
  final int port;
  final String database;
  final String username;
  final bool isSslEnabled;
  final VoidCallback? onTap;

  const ConnectionStatusBar({
    super.key,
    this.clusterName,
    required this.host,
    this.port = 5432,
    this.database = 'postgres',
    this.username = '',
    required this.isSslEnabled,
    this.onTap,
  });

  /// Formats the connection target as `username@host[:port]/database`,
  /// omitting `:port` when [port] is the default PostgreSQL port (5432).
  static String formatConnectionTarget({
    required String username,
    required String host,
    int port = 5432,
    String database = 'postgres',
  }) {
    final userPrefix = username.isNotEmpty ? '$username@' : '';
    final portPart = port != 5432 ? ':$port' : '';
    final dbPart = database.isNotEmpty ? '/$database' : '';
    return '$userPrefix$host$portPart$dbPart';
  }

  @override
  State<ConnectionStatusBar> createState() => _ConnectionStatusBarState();
}

class _ConnectionStatusBarState extends State<ConnectionStatusBar> {
  static const double _gapWidth = 48.0;
  static const Duration _tickInterval = Duration(milliseconds: 32);
  static const double _pixelsPerSecond = 40.0;

  Timer? _tickerTimer;
  double _offset = 0.0;
  double _unitWidth = 0.0;

  @override
  void didUpdateWidget(covariant ConnectionStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clusterName != widget.clusterName ||
        oldWidget.host != widget.host ||
        oldWidget.port != widget.port ||
        oldWidget.database != widget.database ||
        oldWidget.username != widget.username) {
      _offset = 0.0;
    }
  }

  void _syncTicker({required bool overflows, required double unitWidth}) {
    _unitWidth = unitWidth;
    if (!overflows) {
      _stopTicker();
      if (_offset != 0.0) {
        _offset = 0.0;
      }
      return;
    }
    if (_tickerTimer == null || !_tickerTimer!.isActive) {
      final stepPx = _pixelsPerSecond * (_tickInterval.inMilliseconds / 1000.0);
      _tickerTimer = Timer.periodic(_tickInterval, (_) {
        if (!mounted || _unitWidth <= 0) return;
        setState(() {
          _offset = (_offset + stepPx) % _unitWidth;
        });
      });
    }
  }

  void _stopTicker() {
    _tickerTimer?.cancel();
    _tickerTimer = null;
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCluster = widget.clusterName != null && widget.clusterName!.isNotEmpty;
    final target = ConnectionStatusBar.formatConnectionTarget(
      username: widget.username,
      host: widget.host,
      port: widget.port,
      database: widget.database,
    );

    final textSpan = TextSpan(
      style: theme.textTheme.bodySmall,
      children: [
        if (hasCluster) ...[
          TextSpan(
            text: widget.clusterName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const TextSpan(text: ' on '),
        ],
        TextSpan(
          text: target,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );

    final body = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.dns, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textDirection = Directionality.of(context);
                  final textScaler = MediaQuery.textScalerOf(context);
                  final textPainter = TextPainter(
                    text: textSpan,
                    maxLines: 1,
                    textDirection: textDirection,
                    textScaler: textScaler,
                  )..layout();

                  final overflows =
                      constraints.maxWidth.isFinite &&
                      constraints.maxWidth > 0 &&
                      textPainter.width > constraints.maxWidth;
                  final unitWidth = textPainter.width + _gapWidth;

                  _syncTicker(overflows: overflows, unitWidth: unitWidth);

                  if (!overflows) {
                    return Text.rich(
                      textSpan,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                    );
                  }

                  final bulletPainter = TextPainter(
                    text: TextSpan(
                      text: '•',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    maxLines: 1,
                    textDirection: textDirection,
                    textScaler: textScaler,
                  )..layout();

                  return ClipRect(
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: textPainter.height,
                      child: CustomPaint(
                        foregroundPainter: _TickerLoopPainter(
                          textPainter: textPainter,
                          bulletPainter: bulletPainter,
                          offset: _offset,
                          gapWidth: _gapWidth,
                        ),
                        child: Transform.translate(
                          offset: Offset(-_offset, 0),
                          child: OverflowBox(
                            alignment: Alignment.centerLeft,
                            minWidth: 0,
                            maxWidth: double.infinity,
                            child: Text.rich(
                              textSpan,
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: widget.isSslEnabled ? 'SSL/TLS Encrypted' : 'Unencrypted Connection',
              child: Icon(
                widget.isSslEnabled ? Icons.lock : Icons.lock_open,
                size: 14,
                color: widget.isSslEnabled ? theme.colorScheme.primary : Colors.amber.shade700,
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.onTap != null) {
      return Material(
        color: theme.colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: widget.onTap,
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

class _TickerLoopPainter extends CustomPainter {
  final TextPainter textPainter;
  final TextPainter bulletPainter;
  final double offset;
  final double gapWidth;

  _TickerLoopPainter({
    required this.textPainter,
    required this.bulletPainter,
    required this.offset,
    required this.gapWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final unitWidth = textPainter.width + gapWidth;
    final bulletX = textPainter.width - offset + (gapWidth - bulletPainter.width) / 2;
    final bulletY = (size.height - bulletPainter.height) / 2;
    bulletPainter.paint(canvas, Offset(bulletX, bulletY));

    final secondCopyX = unitWidth - offset;
    textPainter.paint(canvas, Offset(secondCopyX, 0));
  }

  @override
  bool shouldRepaint(covariant _TickerLoopPainter oldDelegate) {
    return oldDelegate.offset != offset ||
        oldDelegate.textPainter.width != textPainter.width;
  }
}
