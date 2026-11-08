import 'package:flutter/material.dart';

/// The live-caption surface that sits over the media.
///
/// The look follows the system caption bar on current Android phones (Pixel
/// Live Caption and the Infinix/XOS caption overlay): a near-black rounded box
/// with white, centred text that stays readable on any video frame. Two lines
/// are shown until the box is tapped; tapping expands it to show the last few
/// phrases, exactly like double-tapping the system caption box.
class CaptionOverlay extends StatefulWidget {
  const CaptionOverlay({
    super.key,
    required this.text,
    this.status = '',
    this.collapsedLines = 2,
    this.expandedLines = 12,
  });

  /// Caption text. When empty the box shows [status] instead.
  final String text;

  /// Setup/reading status shown before the first phrase arrives.
  final String status;

  /// Lines shown while the box is collapsed. The system caption box shows two.
  final int collapsedLines;

  /// Lines shown after the box is expanded. The system box allows up to twelve.
  final int expandedLines;

  @override
  State<CaptionOverlay> createState() => _CaptionOverlayState();
}

class _CaptionOverlayState extends State<CaptionOverlay> {
  static const _background = Color(0xE6000000);
  static const _radius = BorderRadius.all(Radius.circular(12));

  bool _expanded = false;

  @override
  void didUpdateWidget(CaptionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new caption line starts collapsed again, like the system caption box.
    if (widget.text.trim().isEmpty && _expanded) {
      _expanded = false;
    }
  }

  void _toggleExpanded() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();
    final status = widget.status.trim();
    if (text.isEmpty && status.isEmpty) {
      return const SizedBox.shrink();
    }

    return Semantics(
      container: true,
      liveRegion: true,
      label: text.isEmpty ? status : 'Live captions',
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // The system caption box expands on a double tap; a single tap works
            // too so the control stays discoverable.
            onTap: text.isEmpty ? null : _toggleExpanded,
            onDoubleTap: text.isEmpty ? null : _toggleExpanded,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              alignment: Alignment.bottomCenter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _background,
                  borderRadius: _radius,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: text.isEmpty
                      ? _buildStatus(status)
                      : _buildCaption(text),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCaption(String text) {
    final style = TextStyle(
      color: Colors.white,
      fontSize: 17,
      height: 1.3,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      shadows: const [Shadow(blurRadius: 6, color: Color(0x99000000))],
    );
    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Measuring the text decides whether the expand affordance is useful.
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: widget.collapsedLines,
          textDirection: Directionality.of(context),
          textScaler: textScaler,
        )..layout(maxWidth: constraints.maxWidth);
        final canExpand = painter.didExceedMaxLines;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: Text(
                  text,
                  key: ValueKey(text),
                  maxLines: _expanded
                      ? widget.expandedLines
                      : widget.collapsedLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: style,
                ),
              ),
            ),
            if (canExpand)
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 1),
                child: Icon(
                  _expanded
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildStatus(String status) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.graphic_eq_rounded,
          size: 18,
          color: Colors.white.withValues(alpha: 0.75),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 14,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}
