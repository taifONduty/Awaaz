import 'dart:math' as math;

import 'models.dart';

// Planar metric reference graph. Production uses a geodesic street graph in
// GraphHopper; these fixtures are not Dhaka map data.
class RoadVertex {
  const RoadVertex(this.id, this.xMetres, this.yMetres);
  final String id;
  final double xMetres;
  final double yMetres;
  double distanceTo(RoadVertex other) => math.sqrt(
    math.pow(xMetres - other.xMetres, 2) + math.pow(yMetres - other.yMetres, 2),
  );
}

class RoadEdge {
  RoadEdge({
    required this.id,
    required this.from,
    required this.to,
    required this.seconds,
    required this.risk,
    required this.uncertainty,
    Set<TravelMode> modes = const {TravelMode.car, TravelMode.walk},
    this.closed = false,
  }) : modes = Set.unmodifiable(modes);
  final String id;
  final String from;
  final String to;
  final double seconds;
  final double risk;
  final double uncertainty;
  final Set<TravelMode> modes;
  final bool closed;
}

class RoutingResult {
  RoutingResult(List<RoadEdge> edges, this.weightedSeconds)
    : edges = List.unmodifiable(edges);
  final List<RoadEdge> edges;
  final double weightedSeconds;
  double get travelSeconds => edges.fold(0, (sum, e) => sum + e.seconds);
}

typedef TurnPenalty = double Function(String? incomingEdge, RoadEdge outgoing);

Map<String, RoadVertex> _indexVertices(Iterable<RoadVertex> values) {
  final result = <String, RoadVertex>{};
  for (final value in values) {
    if (value.id.isEmpty || result.containsKey(value.id)) {
      throw ArgumentError('Duplicate or empty vertex ID');
    }
    result[value.id] = value;
  }
  return Map.unmodifiable(result);
}

class RiskRouter {
  RiskRouter({
    required Iterable<RoadVertex> vertices,
    required Iterable<RoadEdge> edges,
    required this.maximumSpeedMps,
  }) : vertices = _indexVertices(vertices),
       edges = List.unmodifiable(edges) {
    if (!maximumSpeedMps.isFinite || maximumSpeedMps <= 0) {
      throw ArgumentError('Invalid speed bound');
    }
    final unique = <String>{};
    for (final v in this.vertices.values) {
      if (!v.xMetres.isFinite || !v.yMetres.isFinite) {
        throw ArgumentError('Invalid vertex');
      }
    }
    for (final e in this.edges) {
      if (!unique.add(e.id) ||
          !this.vertices.containsKey(e.from) ||
          !this.vertices.containsKey(e.to) ||
          !e.seconds.isFinite ||
          e.seconds <= 0 ||
          !e.risk.isFinite ||
          e.risk < 0 ||
          e.risk > 1 ||
          !e.uncertainty.isFinite ||
          e.uncertainty < 0 ||
          e.uncertainty > 1 ||
          e.seconds + 1e-9 <
              this.vertices[e.from]!.distanceTo(this.vertices[e.to]!) /
                  maximumSpeedMps) {
        throw ArgumentError(
          'Invalid edge or inadmissible speed bound: ${e.id}',
        );
      }
      (_outgoing[e.from] ??= []).add(e);
    }
  }
  final Map<String, RoadVertex> vertices;
  final List<RoadEdge> edges;
  final double maximumSpeedMps;
  final Map<String, List<RoadEdge>> _outgoing = {};

  // Frozen nonnegative weights. Incoming-edge state makes turn costs correct.
  // Weighted optimization does not enforce an exact maximum travel-time budget.
  RoutingResult? findRoute(
    String start,
    String goal, {
    required TravelMode mode,
    double riskWeight = 2,
    double uncertaintyWeight = 0.5,
    TurnPenalty? turnPenalty,
  }) {
    if (!vertices.containsKey(start) || !vertices.containsKey(goal)) {
      throw ArgumentError('Unknown vertex');
    }
    if (!riskWeight.isFinite ||
        riskWeight < 0 ||
        !uncertaintyWeight.isFinite ||
        uncertaintyWeight < 0) {
      throw ArgumentError('Invalid weights');
    }
    final origin = (start, null as String?);
    final best = <(String, String?), double>{origin: 0};
    final previous = <(String, String?), ((String, String?), RoadEdge)>{};
    final queue = _MinQueue();
    double heuristic(String id) =>
        vertices[id]!.distanceTo(vertices[goal]!) / maximumSpeedMps;
    queue.add(_Entry(origin, 0, heuristic(start)));
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (current.cost != best[current.state]) continue;
      if (current.state.$1 == goal) {
        final path = <RoadEdge>[];
        var state = current.state;
        while (previous.containsKey(state)) {
          final step = previous[state]!;
          path.add(step.$2);
          state = step.$1;
        }
        return RoutingResult(path.reversed.toList(), current.cost);
      }
      for (final edge in _outgoing[current.state.$1] ?? <RoadEdge>[]) {
        if (edge.closed || !edge.modes.contains(mode)) continue;
        final turn = turnPenalty?.call(current.state.$2, edge) ?? 0;
        if (turn == double.infinity) continue;
        if (!turn.isFinite || turn < 0) {
          throw ArgumentError('Invalid turn penalty');
        }
        final cost =
            current.cost +
            edge.seconds *
                (1 +
                    riskWeight * edge.risk +
                    uncertaintyWeight * edge.uncertainty) +
            turn;
        if (!cost.isFinite) {
          throw ArgumentError('Route cost overflow');
        }
        final next = (edge.to, edge.id as String?);
        if (cost < (best[next] ?? double.infinity)) {
          best[next] = cost;
          previous[next] = (current.state, edge);
          queue.add(_Entry(next, cost, cost + heuristic(edge.to)));
        }
      }
    }
    return null;
  }
}

class _Entry {
  const _Entry(this.state, this.cost, this.priority);
  final (String, String?) state;
  final double cost;
  final double priority;
}

class _MinQueue {
  final List<_Entry> _heap = [];
  bool get isNotEmpty => _heap.isNotEmpty;
  void add(_Entry item) {
    _heap.add(item);
    var i = _heap.length - 1;
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_heap[parent].priority <= item.priority) break;
      _heap[i] = _heap[parent];
      i = parent;
    }
    _heap[i] = item;
  }

  _Entry removeFirst() {
    final first = _heap.first, last = _heap.removeLast();
    if (_heap.isEmpty) return first;
    var i = 0;
    while (i * 2 + 1 < _heap.length) {
      var child = i * 2 + 1;
      if (child + 1 < _heap.length &&
          _heap[child + 1].priority < _heap[child].priority) {
        child++;
      }
      if (last.priority <= _heap[child].priority) break;
      _heap[i] = _heap[child];
      i = child;
    }
    _heap[i] = last;
    return first;
  }
}
