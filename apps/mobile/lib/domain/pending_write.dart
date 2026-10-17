import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'account_models.dart';
import 'models.dart';

enum WriteKind { circle, invitation, report }

@immutable
class PendingWrite {
  PendingWrite._({
    required this.id,
    required this.kind,
    required this.createdAt,
    required Map<String, Object> payload,
  }) : payload = Map.unmodifiable(payload);
  final String id;
  final WriteKind kind;
  final DateTime createdAt;
  // Only validated scalars. No auth tokens, invitation secrets or ownership fields.
  final Map<String, Object> payload;

  factory PendingWrite.circle(String name, DateTime now) =>
      PendingWrite.fromJson({
        'id': const Uuid().v4(),
        'kind': 'circle',
        'createdAt': now.toUtc().toIso8601String(),
        'payload': {'name': name.trim()},
      });
  factory PendingWrite.invitation(
    String circleId,
    String recipientId,
    DateTime now,
  ) => PendingWrite.fromJson({
    'id': const Uuid().v4(),
    'kind': 'invitation',
    'createdAt': now.toUtc().toIso8601String(),
    'payload': {
      'circleId': circleId.toLowerCase(),
      'recipientId': recipientId.trim().toLowerCase(),
    },
  });
  factory PendingWrite.report(
    ReportCategory category,
    String text,
    double latitude,
    double longitude,
    DateTime now,
  ) => PendingWrite.fromJson({
    'id': const Uuid().v4(),
    'kind': 'report',
    'createdAt': now.toUtc().toIso8601String(),
    'payload': {
      'category': category.name,
      'description': text.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'observedAt': now.toUtc().toIso8601String(),
    },
  });

  String get intent => jsonEncode([
    kind.name,
    {
      for (final entry in payload.entries)
        if (entry.key != 'observedAt') entry.key: entry.value,
    },
  ]);
  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'payload': payload,
  };

  static String checkedId(String value) {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(value)) {
      throw const ApiFailure('invalid_request');
    }
    return value.toLowerCase();
  }

  factory PendingWrite.fromJson(Map<String, Object?> data) {
    final id = checkedId(jsonString(data, 'id'));
    final kind = WriteKind.values.byName(jsonString(data, 'kind'));
    final createdAt = jsonDate(data, 'createdAt');
    final raw = jsonObject(data['payload']);
    late final Map<String, Object> payload;
    switch (kind) {
      case WriteKind.circle:
        final name = jsonString(raw, 'name').trim();
        if (raw.length != 1 || name.isEmpty || name.runes.length > 80) {
          throw const ApiFailure('invalid_request');
        }
        payload = {'name': name};
      case WriteKind.invitation:
        if (raw.length != 2) throw const ApiFailure('invalid_request');
        payload = {
          'circleId': checkedId(jsonString(raw, 'circleId')),
          'recipientId': checkedId(jsonString(raw, 'recipientId')),
        };
      case WriteKind.report:
        final category = reportCategory(raw);
        final description = jsonString(raw, 'description').trim();
        final latitude = jsonNumber(raw, 'latitude'),
            longitude = jsonNumber(raw, 'longitude');
        final observed = jsonDate(raw, 'observedAt');
        if (raw.length != 5 ||
            description.runes.length < 10 ||
            description.runes.length > 700 ||
            latitude < 23.62 ||
            latitude > 24.02 ||
            longitude < 90.2 ||
            longitude > 90.58 ||
            observed != createdAt) {
          throw const ApiFailure('invalid_request');
        }
        payload = {
          'category': category.name,
          'description': description,
          'latitude': latitude,
          'longitude': longitude,
          'observedAt': observed.toIso8601String(),
        };
    }
    if (data.length != 4) throw const ApiFailure('invalid_request');
    return PendingWrite._(
      id: id,
      kind: kind,
      createdAt: createdAt,
      payload: payload,
    );
  }
}
