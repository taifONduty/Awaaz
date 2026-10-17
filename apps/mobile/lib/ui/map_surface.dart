import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'theme.dart';

/// A fictional, interactive city diagram. No GPS or live map data is implied.
class SchematicMap extends StatefulWidget {
  const SchematicMap({
    super.key,
    required this.destination,
    this.fastest = false,
    this.detour = false,
    this.height = 300,
    this.showReports = false,
    this.edgeToEdge = false,
  });
  final String destination;
  final bool fastest;
  final bool detour;
  final double height;
  final bool showReports;
  final bool edgeToEdge;

  @override
  State<SchematicMap> createState() => _SchematicMapState();
}

class _SchematicMapState extends State<SchematicMap> {
  final _transform = TransformationController();
  double _scale = 1;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom() {
    final next = _transform.value.getMaxScaleOnAxis() >= 2.5 ? 1.0 : 2.5;
    final size = context.size ?? Size.zero;
    _transform.value = Matrix4.diagonal3Values(next, next, 1)
      ..setTranslationRaw(
        (1 - next) * size.width / 2,
        (1 - next) * size.height / 2,
        0,
      );
    setState(() => _scale = next);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Semantics(
      label: widget.destination.isEmpty
          ? l.mapDemoLabel
          : '${l.fixtureMap}. ${l.origin}. ${widget.destination}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.edgeToEdge ? 0 : 16),
        child: SizedBox(
          height: widget.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                transformationController: _transform,
                minScale: 1,
                maxScale: 3,
                onInteractionEnd: (_) => setState(
                  () => _scale = _transform.value.getMaxScaleOnAxis(),
                ),
                child: CustomPaint(
                  painter: _CityPainter(
                    fastest: widget.fastest,
                    detour: widget.detour,
                    reports: widget.showReports,
                    showRoute: widget.destination.isNotEmpty,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                top: 14,
                left: 14,
                right: 70,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .96),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      l.mapDemoLabel,
                      style: Theme.of(context).textTheme.bodySmall!
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 14,
                right: 12,
                child: Column(
                  children: [
                    _MapControl(
                      key: const Key('map-zoom'),
                      label: _scale > 1.2 ? l.zoomOut : l.zoomMap,
                      icon: _scale > 1.2 ? Icons.remove : Icons.add,
                      onPressed: _zoom,
                    ),
                    const SizedBox(height: 8),
                    _MapControl(
                      key: const Key('map-reset'),
                      label: l.resetMap,
                      icon: Icons.center_focus_strong_outlined,
                      onPressed: () {
                        _transform.value = Matrix4.identity();
                        setState(() => _scale = 1);
                      },
                    ),
                  ],
                ),
              ),
              if (widget.showReports)
                Positioned(
                  left: 14,
                  bottom: 14,
                  right: 72,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        l.mapSignals,
                        style: Theme.of(context).textTheme.bodySmall,
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
}

class _MapControl extends StatelessWidget {
  const _MapControl({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 2,
    shadowColor: AwaazColors.ink.withValues(alpha: .12),
    borderRadius: BorderRadius.circular(14),
    child: IconButton(
      tooltip: label,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: Icon(icon, size: 21, color: AwaazColors.ink),
      onPressed: onPressed,
    ),
  );
}

class _CityPainter extends CustomPainter {
  const _CityPainter({
    required this.fastest,
    required this.detour,
    required this.reports,
    required this.showRoute,
  });
  final bool fastest;
  final bool detour;
  final bool reports;
  final bool showRoute;

  @override
  void paint(Canvas canvas, Size size) {
    // Use a fixed illustration coordinate system so the street pattern stays
    // coherent at phone and tablet sizes. It is not a geographic base map.
    canvas.save();
    canvas.scale(size.width / 420, size.height / 340);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 420, 340),
      Paint()..color = AwaazColors.map,
    );
    final building = Paint()..color = const Color(0xFFE5E8EA);
    final edge = Paint()
      ..color = const Color(0xFFDDE2E4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7;
    for (var row = 0; row < 7; row++) {
      for (var col = 0; col < 8; col++) {
        final x = col * 61.0 - 18 + (row.isOdd ? 7 : 0);
        final y = row * 53.0 - 14;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, 38 + (col % 3) * 3, 29),
          const Radius.circular(4),
        );
        canvas.drawRRect(rect, building);
        canvas.drawRRect(rect, edge);
      }
    }
    void road(Path path, double width) {
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFDBE0E2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 2
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round,
      );
    }

    for (var i = 0; i < 7; i++) {
      road(
        Path()
          ..moveTo(-20, 36 + i * 53)
          ..lineTo(440, 36 + i * 53),
        9,
      );
    }
    for (var i = 0; i < 8; i++) {
      road(
        Path()
          ..moveTo(34 + i * 61, -10)
          ..lineTo(34 + i * 61, 350),
        8,
      );
    }
    final park = Path()
      ..moveTo(224, 184)
      ..lineTo(292, 162)
      ..lineTo(355, 218)
      ..lineTo(347, 302)
      ..lineTo(232, 312)
      ..close();
    canvas.drawPath(park, Paint()..color = AwaazColors.park);
    final lake = Path()
      ..moveTo(286, 184)
      ..cubicTo(334, 170, 304, 221, 320, 239)
      ..cubicTo(348, 273, 311, 306, 293, 279)
      ..cubicTo(280, 257, 291, 244, 271, 226)
      ..cubicTo(253, 209, 263, 187, 286, 184)
      ..close();
    canvas.drawPath(lake, Paint()..color = AwaazColors.water);
    for (final p in [
      const Offset(240, 202),
      const Offset(334, 197),
      const Offset(247, 288),
      const Offset(338, 284),
      const Offset(257, 265),
    ]) {
      canvas.drawCircle(p, 6, Paint()..color = const Color(0xFFBCD49F));
      canvas.drawCircle(
        p.translate(-2, -1),
        4,
        Paint()..color = const Color(0xFFC5DCAA),
      );
    }
    final main = Path()
      ..moveTo(-10, 282)
      ..lineTo(95, 239)
      ..lineTo(95, 142)
      ..lineTo(277, 142)
      ..lineTo(365, 89)
      ..lineTo(445, 53);
    road(main, 21);
    road(
      Path()
        ..moveTo(166, -10)
        ..lineTo(166, 95)
        ..lineTo(215, 142)
        ..lineTo(215, 287)
        ..lineTo(245, 350),
      15,
    );
    road(
      Path()
        ..moveTo(-10, 88)
        ..lineTo(151, 88)
        ..lineTo(215, 36)
        ..lineTo(435, 36),
      16,
    );
    final alternative = Path()
      ..moveTo(95, 239)
      ..lineTo(156, 239)
      ..lineTo(215, 195)
      ..lineTo(215, 142)
      ..lineTo(277, 142)
      ..lineTo(365, 89);
    if (showRoute) {
      canvas.drawPath(
        alternative,
        Paint()
          ..color = const Color(0xFFB8CAC2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    final route = Path()..moveTo(95, 239);
    if (detour) {
      route
        ..lineTo(95, 301)
        ..lineTo(215, 301)
        ..lineTo(215, 142);
    } else if (fastest) {
      route
        ..lineTo(156, 239)
        ..lineTo(215, 195)
        ..lineTo(215, 142);
    } else {
      route.lineTo(95, 142);
    }
    route
      ..lineTo(277, 142)
      ..lineTo(365, 89);
    for (final stroke
        in showRoute
            ? [(Colors.white, 11.0), (AwaazColors.primary, 6.0)]
            : <(Color, double)>[]) {
      canvas.drawPath(
        route,
        Paint()
          ..color = stroke.$1
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.$2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    void label(
      String text,
      Offset at, {
      double fontSize = 10,
      Color color = AwaazColors.muted,
      bool bold = false,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            fontFamily: 'Manrope',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, at);
    }

    label(
      'D H A N M O N D I',
      const Offset(112, 176),
      fontSize: 11,
      bold: true,
    );
    label('KALABAGAN', const Offset(193, 58), fontSize: 9, bold: true);
    label('Lake', const Offset(285, 241), color: const Color(0xFF587E81));
    label('Road 27', const Offset(120, 123), fontSize: 8);
    label('Road 8', const Offset(226, 275), fontSize: 8);
    if (showRoute) {
      canvas.drawCircle(
        const Offset(95, 239),
        24,
        Paint()..color = AwaazColors.primary.withValues(alpha: .12),
      );
      canvas.drawCircle(
        const Offset(95, 239),
        12,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        const Offset(95, 239),
        8,
        Paint()..color = AwaazColors.primary,
      );
      final pin = Path()
        ..moveTo(365, 97)
        ..quadraticBezierTo(341, 70, 365, 57)
        ..quadraticBezierTo(389, 70, 365, 97)
        ..close();
      canvas.drawPath(
        pin.shift(const Offset(0, 2)),
        Paint()..color = AwaazColors.ink.withValues(alpha: .1),
      );
      canvas.drawPath(pin, Paint()..color = AwaazColors.ink);
      canvas.drawCircle(
        const Offset(365, 73),
        6,
        Paint()..color = AwaazColors.accent,
      );
    }
    if (reports) {
      for (final p in [const Offset(166, 88), const Offset(215, 239)]) {
        canvas.drawCircle(p, 15, Paint()..color = Colors.white);
        canvas.drawCircle(p, 12, Paint()..color = AwaazColors.warningTint);
        label(
          '!',
          p.translate(-2, -8),
          fontSize: 14,
          color: AwaazColors.warning,
          bold: true,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CityPainter old) =>
      fastest != old.fastest ||
      detour != old.detour ||
      reports != old.reports ||
      showRoute != old.showRoute;
}
