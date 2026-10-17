import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:awaaz/data/android_trip_platform.dart';
import 'package:awaaz/data/device_location_source.dart';
import 'package:awaaz/domain/trip_monitor.dart';
import 'package:awaaz/ui/trip_monitor_view_model.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'foreground capture/reacquisition works without the plugin service and Awaaz owns native monitoring',
    (tester) async {
      final client = http.Client();
      final locations = GeolocatorLocationSource();
      final trips = TripMonitorViewModel(
        platform: const AndroidTripPlatform(),
        locations: locations,
        allowFixtures: true,
      );
      Future<void> fixture(
        String path, [
        Map<String, Object?> body = const {},
      ]) async {
        final response = await client
            .post(
              Uri.parse('http://10.0.2.2:3031/__fixtures/$path'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 30));
        expect(response.statusCode, 200, reason: response.body);
      }

      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(child: Text('Foreground location diagnostic')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await fixture('trip', {'action': 'prepare'});
        final capturing = locations.acquire();
        await fixture('location-dialog');
        final first = await capturing;
        expect(first.latitude, closeTo(23.76, .001));
        expect(first.longitude, closeTo(90.38, .001));
        expect(first.hasAccuracy, true);
        await locations.cancel();
        await fixture('location');
        final second = await locations.acquire();
        expect(second.latitude, closeTo(23.76, .001));
        expect(second.capturedAt.isBefore(first.capturedAt), false);
        await expectLater(
          Geolocator.getPositionStream(
            locationSettings: AndroidSettings(
              accuracy: LocationAccuracy.high,
              useMSLAltitude: false,
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: 'Synthetic test',
                notificationText: 'Unavailable plugin service',
              ),
            ),
          ).first.timeout(const Duration(seconds: 5)),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'ERROR_WHILE_ACQUIRING_POSITION',
            ),
          ),
        );
        // A failed plugin-service request must not poison the next foreground stream.
        final third = await locations.acquire();
        expect(third.latitude, closeTo(23.76, .001));
        await trips.initialize(null);
        expect(trips.statusConfirmed, true);
        final corridor = ApprovedCorridor(
          graphVersion: 'synthetic-graph-1',
          riskVersion: 'synthetic-risk-1',
          points: [
            [23.76, 90.379],
            [23.76, 90.39],
          ],
          synthetic: true,
        );
        expect(
          await trips.arm('synthetic-foreground-regression', corridor, 'en'),
          true,
          reason: trips.error,
        );
        expect(trips.snapshot.active, true);
        await fixture('trip', {'action': 'onroute'});
        await trips.refresh();
        expect(trips.snapshot.status, 'tracking');
        expect(await trips.stop(), true);
        expect(trips.snapshot.active, false);
        expect(trips.statusConfirmed, true);
        expect(tester.takeException(), isNull);
      } finally {
        await const AndroidTripPlatform().stop();
        trips.dispose();
        await locations.cancel();
        await tester.pumpWidget(const SizedBox());
        client.close();
      }
    },
  );
}
