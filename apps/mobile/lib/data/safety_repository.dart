import '../domain/models.dart';
import '../domain/risk_router.dart';

abstract interface class SafetyRepository {
  bool get geographic;
  List<Destination> get destinations;
  List<CommunityReport> get reports;
  Future<List<RouteOption>> routes(
    Destination destination,
    TravelMode mode,
    DemoScenario scenario,
  );
}

class RouteUnavailable implements Exception {}

class DemoSafetyRepository implements SafetyRepository {
  @override
  bool get geographic => false;
  @override
  List<Destination> get destinations => const [
    Destination('lake', 'Dhanmondi Lake', 'ধানমন্ডি লেক'),
    Destination('campus', 'University of Dhaka', 'ঢাকা বিশ্ববিদ্যালয়'),
    Destination('station', 'Agargaon Metro Station', 'আগারগাঁও মেট্রো স্টেশন'),
  ];
  @override
  List<CommunityReport> get reports => const [
    CommunityReport(
      category: ReportCategory.obstruction,
      place: 'Farmgate',
      description: 'construction',
      reviewed: false,
    ),
    CommunityReport(
      category: ReportCategory.lighting,
      place: 'Green Road',
      description: 'lights',
      reviewed: true,
    ),
  ];
  @override
  Future<List<RouteOption>> routes(
    Destination destination,
    TravelMode mode,
    DemoScenario scenario,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (scenario == DemoScenario.offline ||
        scenario == DemoScenario.routeError) {
      throw RouteUnavailable();
    }
    final walking = mode == TravelMode.walk;
    // A* runs on a tiny metric fixture graph, never actual Dhaka streets. Route
    // risk, coverage, time and geometry are illustrative for every destination.
    final scale = walking ? 0.5 : 1.0;
    final timeScale = walking ? 1.75 : 1.0;
    final vertices = [
      RoadVertex('start', 0, 0),
      RoadVertex('b', 2200 * scale, 1200 * scale),
      RoadVertex('c', 4300 * scale, 1200 * scale),
      RoadVertex('goal', 5400 * scale, 0),
    ];
    final router = RiskRouter(
      vertices: vertices,
      maximumSpeedMps: 20,
      edges: [
        RoadEdge(
          id: 'main',
          from: 'start',
          to: 'goal',
          seconds: 1200 * timeScale,
          risk: .55,
          uncertainty: .3,
        ),
        RoadEdge(
          id: 'west',
          from: 'start',
          to: 'b',
          seconds: 600 * timeScale,
          risk: .12,
          uncertainty: .5,
        ),
        RoadEdge(
          id: 'north',
          from: 'b',
          to: 'c',
          seconds: 400 * timeScale,
          risk: .08,
          uncertainty: .5,
        ),
        RoadEdge(
          id: 'east',
          from: 'c',
          to: 'goal',
          seconds: 440 * timeScale,
          risk: .1,
          uncertainty: .5,
        ),
      ],
    );
    RouteOption option(RoutePreference preference) {
      final route = router.findRoute(
        'start',
        'goal',
        mode: mode,
        riskWeight: preference == RoutePreference.lowerRisk ? 2 : 0,
        uncertaintyWeight: preference == RoutePreference.lowerRisk ? .5 : 0,
      )!;
      final metres = route.edges.fold<double>(
        0,
        (sum, edge) =>
            sum +
            router.vertices[edge.from]!.distanceTo(router.vertices[edge.to]!),
      );
      return RouteOption(
        id: '${destination.id}-${mode.name}-${preference.name}',
        preference: preference,
        minutes: (route.travelSeconds / 60).round(),
        kilometres: (metres / 100).round() / 10,
        coverage: preference == RoutePreference.lowerRisk ? .46 : .51,
      );
    }

    return [option(RoutePreference.lowerRisk), option(RoutePreference.fastest)];
  }
}
