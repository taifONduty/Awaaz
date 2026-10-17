import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:awaaz/data/draft_store.dart';
import 'package:awaaz/data/safety_repository.dart';
import 'package:awaaz/domain/models.dart';
import 'package:awaaz/ui/journey_view_model.dart';

class FailingStore implements DraftStore {
  @override
  Future<List<ReportDraft>> read() async => throw StateError('unavailable');
  @override
  Future<void> write(List<ReportDraft> drafts) async =>
      throw StateError('unavailable');
}

class DeferredRepository extends DemoSafetyRepository {
  final calls = <Completer<List<RouteOption>>>[];
  @override
  Future<List<RouteOption>> routes(
    Destination destination,
    TravelMode mode,
    DemoScenario scenario,
  ) {
    final call = Completer<List<RouteOption>>();
    calls.add(call);
    return call.future;
  }
}

void main() {
  test('accepting a detour updates baseline; keeping it does not', () async {
    final vm = JourneyViewModel(
      repository: DemoSafetyRepository(),
      draftStore: MemoryDraftStore(),
    );
    await vm.initialize();
    await vm.plan(vm.repository.destinations.first);
    vm.start();
    final original = vm.baselineId;
    vm.simulateDeviation();
    expect(vm.phase, JourneyPhase.checkIn);
    expect(vm.baselineId, original);
    vm.acknowledgeDetour(accept: false);
    expect(vm.baselineId, original);
    vm.simulateDeviation();
    vm.acknowledgeDetour(accept: true);
    expect(vm.baselineRevision, 2);
    expect(vm.baselineId, isNot(original));
    final selected = vm.selectedRoute;
    await vm.plan(vm.repository.destinations.last);
    expect(vm.selectedRoute, selected);
    vm.end();
    expect(vm.baselineId, isNull);
    vm.dispose();
  });
  test('stale route response cannot replace the newest destination', () async {
    final repo = DeferredRepository();
    final actual = JourneyViewModel(
      repository: repo,
      draftStore: MemoryDraftStore(),
    );
    final first = actual.plan(repo.destinations.first),
        second = actual.plan(repo.destinations.last);
    const route = RouteOption(
      id: 'latest',
      preference: RoutePreference.fastest,
      minutes: 1,
      kilometres: 1,
      coverage: 0,
    );
    repo.calls[1].complete([route]);
    await second;
    repo.calls[0].complete([]);
    await first;
    expect(actual.selectedRoute, route);
    expect(actual.destination, repo.destinations.last);
    actual.dispose();
  });
  test(
    'drafts survive a new view model and remain private local data',
    () async {
      final store = MemoryDraftStore();
      final vm = JourneyViewModel(
        repository: DemoSafetyRepository(),
        draftStore: store,
      );
      await vm.initialize();
      expect(
        await vm.saveDraft(
          ReportCategory.lighting,
          'Demo road',
          'Lights are out in this fixture.',
        ),
        isTrue,
      );
      final next = JourneyViewModel(
        repository: DemoSafetyRepository(),
        draftStore: store,
      );
      await next.initialize();
      expect(next.drafts.single.description, 'Lights are out in this fixture.');
      await next.deleteDrafts();
      expect(await store.read(), isEmpty);
      vm.dispose();
      next.dispose();
    },
  );
  test('storage failures do not claim a report was saved', () async {
    final vm = JourneyViewModel(
      repository: DemoSafetyRepository(),
      draftStore: FailingStore(),
    );
    await vm.initialize();
    expect(vm.storageFailed, isTrue);
    expect(
      await vm.saveDraft(
        ReportCategory.other,
        'Road',
        'A long demo description',
      ),
      isFalse,
    );
    expect(vm.drafts, isEmpty);
    expect(vm.storageFailed, isTrue);
    vm.dispose();
  });
}
