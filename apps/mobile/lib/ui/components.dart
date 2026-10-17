import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../l10n/generated/app_localizations.dart';
import 'theme.dart';
export 'map_surface.dart';

class SurfacePanel extends StatelessWidget {
  const SurfacePanel({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(20),
    this.borderColor,
  });
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: borderColor ?? AwaazColors.border),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: AwaazColors.ink.withValues(alpha: .035),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.title,
    required this.body,
    this.meta,
    this.icon,
    this.color = AwaazColors.surface,
  });
  final String title;
  final String body;
  final String? meta;
  final IconData? icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SurfacePanel(
    color: color,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              IconBadge(
                icon: icon!,
                color: color == AwaazColors.warningTint
                    ? AwaazColors.warning
                    : AwaazColors.primary,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (meta != null) ...[
                    const SizedBox(height: 4),
                    Text(meta!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          body,
          style: Theme.of(context).textTheme.bodyMedium!
              .copyWith(color: AwaazColors.muted),
        ),
      ],
    ),
  );
}

class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.color = AwaazColors.primary,
    this.background = AwaazColors.tint,
  });
  final IconData icon;
  final Color color;
  final Color background;
  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(icon, color: color, size: 21),
  );
}

class StatusTag extends StatelessWidget {
  const StatusTag({
    super.key,
    required this.label,
    this.color = AwaazColors.primary,
    this.background = AwaazColors.tint,
    this.icon,
  });
  final String label;
  final Color color;
  final Color background;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Wrap(
      spacing: 5,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (icon != null) Icon(icon, size: 14, color: color),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.bodySmall!
        .copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.1),
  );
}

class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.quiet = false,
    this.urgent = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool quiet;
  final bool urgent;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: onPressed,
      style: (urgent || quiet)
          ? FilledButton.styleFrom(
              backgroundColor: urgent ? AwaazColors.danger : Colors.white,
              foregroundColor: urgent ? Colors.white : AwaazColors.primary,
              side: quiet ? const BorderSide(color: AwaazColors.border) : null,
            )
          : null,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          if (icon != null) Icon(icon, size: 20),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.eyebrow,
  });
  final String title;
  final String subtitle;
  final String? eyebrow;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          SectionLabel(eyebrow!),
          const SizedBox(height: 8),
        ],
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 7),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium!
              .copyWith(color: AwaazColors.muted),
        ),
      ],
    ),
  );
}

/// A route endpoint summary remains readable when text is scaled.
class RouteEndpoints extends StatelessWidget {
  const RouteEndpoints({super.key, required this.destination});
  final String destination;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SurfacePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _point(context, Icons.my_location, l.fromLabel, l.origin),
          const Padding(
            padding: EdgeInsets.only(left: 40, top: 10, bottom: 10),
            child: Divider(height: 1),
          ),
          _point(context, Icons.location_on, l.toLabel, destination),
        ],
      ),
    );
  }

  Widget _point(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) => Row(
    children: [
      Icon(icon, color: AwaazColors.primary, size: 20),
      const SizedBox(width: 18),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    ],
  );
}

String categoryLabel(AppLocalizations l, ReportCategory category) =>
    switch (category) {
      ReportCategory.obstruction => l.obstruction,
      ReportCategory.lighting => l.lighting,
      ReportCategory.theft => l.theft,
      ReportCategory.harassment => l.harassment,
      ReportCategory.accident => l.accident,
      ReportCategory.other => l.other,
    };
IconData categoryIcon(ReportCategory category) => switch (category) {
  ReportCategory.obstruction => Icons.construction_rounded,
  ReportCategory.lighting => Icons.lightbulb_outline_rounded,
  ReportCategory.theft => Icons.wallet_outlined,
  ReportCategory.harassment => Icons.front_hand_outlined,
  ReportCategory.accident => Icons.car_crash_outlined,
  ReportCategory.other => Icons.flag_outlined,
};
