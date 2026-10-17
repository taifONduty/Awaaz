import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/place_search.dart';
import '../l10n/generated/app_localizations.dart';
import 'theme.dart';

class PlaceSearchPage extends StatefulWidget {
  const PlaceSearchPage({super.key, required this.service});
  final PlaceSearchService service;
  @override
  State<PlaceSearchPage> createState() => _PlaceSearchPageState();
}

class _PlaceSearchPageState extends State<PlaceSearchPage>
    with WidgetsBindingObserver {
  final _query = TextEditingController();
  Timer? _debounce;
  int _epoch = 0;
  bool _loading = false, _failed = false, _searched = false, _visible = true;
  List<NamedPlace> _results = const [];
  bool _pausedSearch = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _cancel() {
    _epoch++;
    _debounce?.cancel();
    widget.service.cancelSearch();
  }

  @override
  void dispose() {
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    _query.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _visible = false;
      _cancel();
      if (mounted) {
        setState(() {
          _loading = false;
          _results = const [];
          _searched = false;
          _failed = false;
          _pausedSearch = _query.text.trim().runes.length >= 2;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _visible = true;
    }
  }

  void _changed(String value) {
    _cancel();
    setState(() {
      _results = const [];
      _failed = false;
      _searched = false;
      _loading = false;
      _pausedSearch = false;
    });
    if (_visible && value.trim().runes.length >= 2) {
      _debounce = Timer(
        const Duration(milliseconds: 350),
        () => unawaited(_search()),
      );
    }
  }

  Future<void> _search() async {
    _debounce?.cancel();
    if (!_visible || _query.text.trim().runes.length < 2) return;
    final epoch = ++_epoch;
    final term = _query.text.trim();
    setState(() {
      _loading = true;
      _failed = false;
      _pausedSearch = false;
    });
    try {
      final results = await widget.service.searchPlaces(term);
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _results = results;
        _searched = true;
      });
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _failed = true;
          _searched = true;
        });
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context),
        bangla = Localizations.localeOf(context).languageCode == 'bn';
    return Scaffold(
      appBar: AppBar(title: Text(l.placeSearchTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('place-query'),
                    controller: _query,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    maxLength: 80,
                    textInputAction: TextInputAction.search,
                    onChanged: _changed,
                    onSubmitted: (_) => unawaited(_search()),
                    decoration: InputDecoration(
                      hintText: l.placeSearchHint,
                      counterText: '',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: l.placeClear,
                              onPressed: () {
                                _query.clear();
                                _changed('');
                              },
                              icon: const Icon(Icons.close),
                            ),
                      filled: true,
                      fillColor: AwaazColors.canvas,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_loading)
              const LinearProgressIndicator(key: Key('place-search-loading')),
            Expanded(
              child: ListView(
                key: const Key('place-results'),
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Text(
                      l.placeSearchPrivacy,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => unawaited(_attribution()),
                      child: Text(
                        '© OpenStreetMap contributors · ODbL',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  if (_pausedSearch)
                    _message(l.placePaused, retry: true)
                  else if (_failed)
                    _message(l.placeUnavailable, retry: true)
                  else if (_results.isEmpty)
                    _message(_searched ? l.placeNoResults : l.placeStart)
                  else
                    for (final place in _results) ...[
                      ListTile(
                        key: ValueKey('place-${place.id}'),
                        minVerticalPadding: 14,
                        leading: Icon(switch (place.kind) {
                          'education' => Icons.school_outlined,
                          'health' => Icons.local_hospital_outlined,
                          'transit' => Icons.directions_transit,
                          'shop' => Icons.storefront_outlined,
                          'road' => Icons.alt_route,
                          _ => Icons.place_outlined,
                        }, color: AwaazColors.muted),
                        title: Text(
                          bangla ? place.nameBn : place.nameEn,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(placeKind(context, place.kind)),
                        trailing: const Icon(Icons.north_west, size: 18),
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          Navigator.pop(context, place);
                        },
                      ),
                      const Divider(height: 1, indent: 64),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(String text, {bool retry = false}) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Text(text),
        if (retry)
          TextButton(
            onPressed: _loading ? null : () => unawaited(_search()),
            child: Text(AppLocalizations.of(context).retry),
          ),
      ],
    ),
  );

  Future<void> _attribution() async {
    final uri = Uri.parse('https://www.openstreetmap.org/copyright');
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('OpenStreetMap · ODbL'),
          content: SelectableText(uri.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).close),
            ),
          ],
        ),
      );
    }
  }
}

String placeKind(BuildContext context, String kind) {
  final l = AppLocalizations.of(context);
  return switch (kind) {
    'road' => l.placeRoad,
    'education' => l.placeEducation,
    'health' => l.placeHealth,
    'transit' => l.placeTransit,
    'shop' => l.placeShop,
    'area' => l.placeArea,
    _ => l.placePublic,
  };
}
