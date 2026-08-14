import 'package:latlong2/latlong.dart';

class MapPathTracer {
  static final MapPathTracer instance = MapPathTracer._internal();
  MapPathTracer._internal();

  final List<LatLng> _activeHuntingPath = [];
  bool _isTrackingActive = false;

  bool get isTracking => _isTrackingActive;
  List<LatLng> get currentPath => List.unmodifiable(_activeHuntingPath);

  void startNewPathTracing() {
    _activeHuntingPath.clear();
    _isTrackingActive = true;
  }

  void stopPathTracing() {
    _isTrackingActive = false;
  }

  void appendCoordinate(double lat, double lon) {
    if (!_isTrackingActive) return;
    final LatLng point = LatLng(lat, lon);
    if (_activeHuntingPath.isEmpty || _activeHuntingPath.last != point) {
      _activeHuntingPath.add(point);
    }
  }

  void clearAllPaths() {
    _activeHuntingPath.clear();
  }

  // Alias for clearAllPaths for backward compatibility
  void clearRecordedPath() {
    _activeHuntingPath.clear();
  }
}
