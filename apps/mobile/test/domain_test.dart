import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:awaaz/domain/models.dart';
import 'package:awaaz/domain/risk_router.dart';
import 'package:awaaz/domain/deviation_monitor.dart';

RoadEdge edge(
  String id,
  String from,
  String to,
  double seconds, {
  double risk = 0,
  double uncertainty = 0,
  bool closed = false,
  Set<TravelMode> modes = const {TravelMode.car, TravelMode.walk},
}) => RoadEdge(
  id: id,
  from: from,
  to: to,
  seconds: seconds,
  risk: risk,
  uncertainty: uncertainty,
  closed: closed,
  modes: modes,
);
CorridorSample sample(
  int second, {
  double distance = 150,
  double accuracy = 10,
  int age = 0,
  double speed = 8,
}) => CorridorSample(
  elapsed: Duration(seconds: second),
  distanceMetres: distance,
  accuracyMetres: accuracy,
  fixAge: Duration(seconds: age),
  speedMps: speed,
);

void main() {
  const vertices = [
    RoadVertex('a', 0, 0),
    RoadVertex('b', 1, 0),
    RoadVertex('c', 2, 0),
  ];
  test(
    'risk and uncertainty change route; unknown evidence carries a cost',
    () {
      final router = RiskRouter(
        vertices: vertices,
        maximumSpeedMps: 1,
        edges: [
          edge('direct', 'a', 'c', 2, risk: .8),
          edge('ab', 'a', 'b', 2, risk: .1),
          edge('bc', 'b', 'c', 2, risk: .1),
        ],
      );
      expect(
        router
            .findRoute('a', 'c', mode: TravelMode.car, riskWeight: 0)!
            .edges
            .map((e) => e.id),
        ['direct'],
      );
      expect(
        router
            .findRoute('a', 'c', mode: TravelMode.car)!
            .edges
            .map((e) => e.id),
        ['ab', 'bc'],
      );
      final uncertain = RiskRouter(
        vertices: vertices,
        maximumSpeedMps: 1,
        edges: [
          edge('unknown', 'a', 'c', 2, uncertainty: 1),
          edge('ab', 'a', 'b', 1.2),
          edge('bc', 'b', 'c', 1.2),
        ],
      );
      expect(
        uncertain
            .findRoute('a', 'c', mode: TravelMode.car)!
            .edges
            .map((e) => e.id),
        ['ab', 'bc'],
      );
    },
  );
  test('closures, mode access and missing paths are respected', () {
    final router = RiskRouter(
      vertices: vertices,
      maximumSpeedMps: 1,
      edges: [
        edge('closed', 'a', 'c', 2, closed: true),
        edge('walk', 'a', 'c', 2, modes: {TravelMode.walk}),
      ],
    );
    expect(router.findRoute('a', 'c', mode: TravelMode.car), isNull);
    expect(
      router.findRoute('a', 'c', mode: TravelMode.walk)!.edges.single.id,
      'walk',
    );
    expect(router.findRoute('a', 'a', mode: TravelMode.car)!.edges, isEmpty);
  });
  test(
    'incoming-edge state preserves a more costly arrival with a cheaper turn',
    () {
      final router = RiskRouter(
        vertices: vertices,
        maximumSpeedMps: 1,
        edges: [
          edge('quick', 'a', 'b', 1),
          edge('slow', 'a', 'b', 2),
          edge('exit', 'b', 'c', 1),
        ],
      );
      final route = router.findRoute(
        'a',
        'c',
        mode: TravelMode.car,
        turnPenalty: (incoming, outgoing) =>
            incoming == 'quick' && outgoing.id == 'exit' ? 100 : 0,
      )!;
      expect(route.edges.map((e) => e.id), ['slow', 'exit']);
      expect(route.weightedSeconds, 3);
      expect(
        router.findRoute(
          'a',
          'c',
          mode: TravelMode.car,
          turnPenalty: (incoming, outgoing) =>
              outgoing.id == 'exit' ? double.infinity : 0,
        ),
        isNull,
      );
    },
  );
  test('invalid graph bounds and weights cannot silently break A*', () {
    expect(
      () => RiskRouter(
        vertices: vertices,
        maximumSpeedMps: 1,
        edges: [edge('x', 'a', 'c', .1)],
      ),
      throwsArgumentError,
    );
    expect(
      () => RiskRouter(
        vertices: [...vertices, vertices.first],
        maximumSpeedMps: 1,
        edges: [],
      ),
      throwsArgumentError,
    );
    final router = RiskRouter(
      vertices: vertices,
      maximumSpeedMps: 1,
      edges: [edge('x', 'a', 'c', 2)],
    );
    expect(
      () => router.findRoute('a', 'c', mode: TravelMode.car, riskWeight: -1),
      throwsArgumentError,
    );
    expect(
      () => router.findRoute('missing', 'c', mode: TravelMode.car),
      throwsArgumentError,
    );
    expect(
      () => router.findRoute(
        'a',
        'c',
        mode: TravelMode.car,
        turnPenalty: (_, _) => -1,
      ),
      throwsArgumentError,
    );
  });
  test('A* agrees with an independent Dijkstra oracle on seeded graphs', () {
    final random = Random(73);
    for (var run = 0; run < 30; run++) {
      final vs = [
        for (var i = 0; i < 8; i++)
          RoadVertex('$i', random.nextDouble() * 10, random.nextDouble() * 10),
      ];
      final es = <RoadEdge>[];
      for (final a in vs) {
        for (final b in vs) {
          if (a.id != b.id && random.nextDouble() < .35) {
            es.add(
              edge(
                '${a.id}-${b.id}',
                a.id,
                b.id,
                a.distanceTo(b) / 5 + 1 + random.nextDouble() * 5,
                risk: random.nextDouble(),
                uncertainty: random.nextDouble(),
              ),
            );
          }
        }
      }
      final router = RiskRouter(vertices: vs, edges: es, maximumSpeedMps: 5);
      for (final lambda in [0.0, 1.0, 3.0]) {
        final distances = {'0': 0.0}, unvisited = vs.map((v) => v.id).toSet();
        while (unvisited.isNotEmpty) {
          final sorted = unvisited.toList()
            ..sort(
              (a, b) => (distances[a] ?? double.infinity).compareTo(
                distances[b] ?? double.infinity,
              ),
            );
          final a = sorted.first;
          unvisited.remove(a);
          final cost = distances[a];
          if (cost == null) break;
          for (final e in es.where((e) => e.from == a)) {
            final candidate =
                cost + e.seconds * (1 + lambda * e.risk + .5 * e.uncertainty);
            if (candidate < (distances[e.to] ?? double.infinity)) {
              distances[e.to] = candidate;
            }
          }
        }
        final found = router.findRoute(
          '0',
          '7',
          mode: TravelMode.car,
          riskWeight: lambda,
        );
        if (distances['7'] == null) {
          expect(found, isNull);
        } else {
          expect(found!.weightedSeconds, closeTo(distances['7']!, 1e-8));
        }
      }
    }
  });
  test('only sustained reliable deviation produces a latched check-in', () {
    final monitor = DeviationMonitor();
    expect(monitor.update(sample(0)), MonitorStatus.candidate);
    expect(monitor.update(sample(10)), MonitorStatus.candidate);
    expect(monitor.update(sample(20)), MonitorStatus.checkIn);
    expect(monitor.update(sample(30, distance: 0)), MonitorStatus.checkIn);
    monitor.acknowledge();
    expect(monitor.update(sample(40, distance: 0)), MonitorStatus.onRoute);
  });
  test(
    'poor GPS, old fixes, gaps and isolated spikes cannot trigger alerts',
    () {
      final monitor = DeviationMonitor();
      expect(monitor.update(sample(0)), MonitorStatus.candidate);
      expect(
        monitor.update(sample(10, accuracy: 90)),
        MonitorStatus.unreliable,
      );
      expect(monitor.update(sample(20)), MonitorStatus.candidate);
      expect(monitor.update(sample(21, age: 30)), MonitorStatus.unreliable);
      expect(monitor.update(sample(40)), MonitorStatus.unreliable);
      expect(
        monitor.update(sample(50, distance: 88, accuracy: 10)),
        MonitorStatus.onRoute,
      );
      expect(monitor.update(sample(60, speed: 0)), MonitorStatus.onRoute);
    },
  );
  test('duplicate timestamps cannot advance evidence', () {
    final monitor = DeviationMonitor();
    monitor.update(sample(0));
    expect(monitor.update(sample(0)), MonitorStatus.unreliable);
    expect(monitor.update(sample(10)), MonitorStatus.candidate);
  });
}
