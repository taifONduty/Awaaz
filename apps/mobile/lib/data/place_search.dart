import '../domain/models.dart';

class NamedPlace {
  const NamedPlace({
    required this.id,
    required this.nameEn,
    required this.nameBn,
    required this.kind,
    required this.point,
  });
  final String id, nameEn, nameBn, kind;
  final GeoPoint point;
}

abstract interface class PlaceSearchService {
  Future<List<NamedPlace>> searchPlaces(String query);
  void cancelSearch();
}
