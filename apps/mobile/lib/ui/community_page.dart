import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../l10n/generated/app_localizations.dart';
import 'account_page.dart';
import 'account_view_model.dart';
import 'components.dart';
import 'journey_view_model.dart';
import 'theme.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({
    super.key,
    required this.vm,
    required this.accounts,
    required this.onReport,
    required this.onHistory,
  });
  final JourneyViewModel vm;
  final AccountViewModel accounts;
  final VoidCallback onReport, onHistory;
  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  ReportCategory? _filter;

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) await widget.vm.deleteDrafts();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.vm, widget.accounts]),
    builder: (context, _) {
      final l = AppLocalizations.of(context), accounts = widget.accounts;
      final preview = !accounts.configured;
      final ready = accounts.signedIn && accounts.account?.profile != null;
      final events = accounts.events;
      final fixtures = widget.vm.reports;
      final categories = preview
          ? fixtures.map((report) => report.category).toSet()
          : events.map((event) => event.category).toSet();
      final filteredEvents = events
          .where((event) => _filter == null || event.category == _filter)
          .toList();
      final filteredFixtures = fixtures
          .where((report) => _filter == null || report.category == _filter)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.community,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (!preview && accounts.signedIn)
                IconButton(
                  key: const Key('community-refresh'),
                  tooltip: l.retry,
                  onPressed: accounts.loading || accounts.busy
                      ? null
                      : () => unawaited(accounts.refresh()),
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l.communityFeedIntro,
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(color: AwaazColors.muted),
          ),
          const SizedBox(height: 20),
          ActionButton(
            key: const Key('community-report'),
            label: l.reportIncident,
            icon: Icons.add,
            onPressed: widget.onReport,
          ),
          if (!preview)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('community-history'),
                onPressed: widget.onHistory,
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(l.accountReports),
              ),
            ),
          const SizedBox(height: 16),
          if (!preview && !ready && !accounts.loading)
            AccountAccessPanel(
              accounts: accounts,
              onOpen: widget.onHistory,
              body: l.communitySignIn,
            ),
          if (!preview && accounts.error != null) ...[
            Text(
              accountError(l, accounts.error),
              key: const Key('community-error'),
              style: const TextStyle(color: AwaazColors.warning),
            ),
            const SizedBox(height: 12),
          ],
          if (!preview && accounts.loading && !ready)
            const LoadingRows()
          else if (preview || ready) ...[
            if (accounts.loading) const LinearProgressIndicator(minHeight: 2),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    key: const Key('filter-all'),
                    label: Text(l.allReports),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  for (final category in categories) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      key: Key('filter-${category.name}'),
                      label: Text(categoryLabel(l, category)),
                      avatar: Icon(categoryIcon(category), size: 18),
                      selected: _filter == category,
                      onSelected: (_) => setState(() => _filter = category),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (preview ? filteredFixtures.isEmpty : filteredEvents.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.forum_outlined,
                      color: AwaazColors.muted,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      preview ? l.noReports : l.accountEmptyEvents,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(l.unknown),
                  ],
                ),
              ),
            if (preview)
              for (final report in filteredFixtures)
                RoadReportRow(
                  category: report.category,
                  place: report.place,
                  description: report.description == 'construction'
                      ? l.construction
                      : l.lights,
                  badge: report.reviewed ? l.reviewed : l.unreviewed,
                  icon: report.reviewed
                      ? Icons.check_circle_outline
                      : Icons.schedule,
                )
            else
              for (final event in filteredEvents)
                RoadReportRow(
                  key: Key('published-event-${event.id}'),
                  category: event.category,
                  description: event.summary,
                  badge: l.communityPublished,
                  // The feed contract exposes no place or exact coordinates.
                  // Show its actual observation time, never an invented location.
                  meta:
                      '${l.communityObserved} ${MaterialLocalizations.of(context).formatMediumDate(event.observedAt.toLocal())} · '
                      '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(event.observedAt.toLocal()))}',
                  icon: Icons.public,
                ),
            const SizedBox(height: 12),
            Text(
              preview ? l.verificationNote : l.communityPublishedNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (preview) ...[
            const SizedBox(height: 16),
            ExpansionTile(
              key: const Key('community-map-preview'),
              title: Text(l.mapDemoLabel),
              tilePadding: EdgeInsets.zero,
              children: [
                SchematicMap(
                  destination: '',
                  showReports: fixtures.isNotEmpty,
                  height: 220,
                ),
              ],
            ),
          ],
          if (widget.vm.drafts.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(l.drafts, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final draft in widget.vm.drafts)
              RoadReportRow(
                category: draft.category,
                place: draft.place,
                description: draft.description,
                badge: l.localOnly,
                icon: Icons.lock_outline,
              ),
            TextButton(onPressed: _delete, child: Text(l.deleteDrafts)),
          ],
        ],
      );
    },
  );
}

class RoadReportRow extends StatelessWidget {
  const RoadReportRow({
    super.key,
    required this.category,
    required this.description,
    required this.badge,
    required this.icon,
    this.place,
    this.meta,
  });
  final ReportCategory category;
  final String description, badge;
  final IconData icon;
  final String? place, meta;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBadge(
                  icon: categoryIcon(category),
                  background: AwaazColors.canvas,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        categoryLabel(AppLocalizations.of(context), category),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (place != null)
                        Text(
                          place!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(description),
            if (meta != null) ...[
              const SizedBox(height: 8),
              Text(meta!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: AwaazColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    badge,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class AccountAccessPanel extends StatelessWidget {
  const AccountAccessPanel({
    super.key,
    required this.accounts,
    required this.onOpen,
    required this.body,
  });
  final AccountViewModel accounts;
  final VoidCallback onOpen;
  final String body;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          ActionButton(
            quiet: true,
            label: accounts.signedIn ? l.communityFinishSetup : l.accountSignIn,
            onPressed: accounts.busy || accounts.loading ? null : onOpen,
          ),
        ],
      ),
    );
  }
}

class LoadingRows extends StatelessWidget {
  const LoadingRows({super.key, this.label});
  final String? label;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label ?? AppLocalizations.of(context).communityLoading,
    child: Column(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              height: 84,
              decoration: BoxDecoration(
                color: AwaazColors.border.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
      ],
    ),
  );
}
