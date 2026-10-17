enum MonitorStatus { onRoute, candidate, checkIn, unreliable }

// Inputs come from a matcher against the user-approved corridor. The native
// service must supply monotonic timestamps, fix age and GPS uncertainty.
class CorridorSample {
  const CorridorSample({
    required this.elapsed,
    required this.distanceMetres,
    required this.accuracyMetres,
    required this.fixAge,
    required this.speedMps,
  });
  final Duration elapsed;
  final double distanceMetres;
  final double accuracyMetres;
  final Duration fixAge;
  final double speedMps;
}

class DeviationMonitor {
  DeviationMonitor({
    this.corridorMetres = 80,
    this.requiredDuration = const Duration(seconds: 20),
    this.requiredSamples = 3,
    this.maximumGap = const Duration(seconds: 12),
  }) {
    if (!corridorMetres.isFinite ||
        corridorMetres <= 0 ||
        requiredSamples < 2 ||
        requiredDuration <= Duration.zero ||
        maximumGap <= Duration.zero) {
      throw ArgumentError('Invalid deviation policy');
    }
  }
  final double corridorMetres;
  final Duration requiredDuration;
  final int requiredSamples;
  final Duration maximumGap;
  Duration? _firstOutside;
  Duration? _previous;
  int _outsideCount = 0;
  bool _latched = false;

  void acknowledge() {
    _firstOutside = null;
    _previous = null;
    _outsideCount = 0;
    _latched = false;
  }

  MonitorStatus update(CorridorSample sample) {
    if (_previous != null && sample.elapsed <= _previous!) {
      return _latched ? MonitorStatus.checkIn : MonitorStatus.unreliable;
    }
    final gap = _previous == null ? Duration.zero : sample.elapsed - _previous!;
    _previous = sample.elapsed;
    final reliable =
        sample.elapsed >= Duration.zero &&
        sample.distanceMetres.isFinite &&
        sample.distanceMetres >= 0 &&
        sample.accuracyMetres.isFinite &&
        sample.accuracyMetres > 0 &&
        sample.accuracyMetres <= 35 &&
        sample.fixAge >= Duration.zero &&
        sample.fixAge <= const Duration(seconds: 8) &&
        sample.speedMps.isFinite &&
        sample.speedMps >= 0;
    if (_latched) return MonitorStatus.checkIn;
    if (!reliable || gap > maximumGap) {
      _firstOutside = null;
      _outsideCount = 0;
      return MonitorStatus.unreliable;
    }
    if (sample.distanceMetres - sample.accuracyMetres <= corridorMetres ||
        sample.speedMps < 0.8) {
      _firstOutside = null;
      _outsideCount = 0;
      return MonitorStatus.onRoute;
    }
    _firstOutside ??= sample.elapsed;
    _outsideCount++;
    if (_outsideCount >= requiredSamples &&
        sample.elapsed - _firstOutside! >= requiredDuration) {
      _latched = true;
      return MonitorStatus.checkIn;
    }
    return MonitorStatus.candidate;
  }
}
