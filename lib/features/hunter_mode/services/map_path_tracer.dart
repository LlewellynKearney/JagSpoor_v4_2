import 'package:latlong2/latlong.dart';

class MapPathTracer {
  static final MapPathTracer instance = MapPathTracer._internal();
  MapPathTracer._internal();

  final List<LatLng> _activeHuntingPath = [];
  final List<LatLng> _bloodTrailVectorPath = [];
  bool _isTrackingActive = false;

  bool get isTracking => _isTrackingActive;
  List<LatLng> get currentPath => List.unmodifiable(_activeHuntingPath);
  List<LatLng> get bloodPath => List.unmodifiable(_bloodTrailVectorPath);

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

  // Appends a confirmed blood drop point to draw the animal's escape route
  void appendBloodDropNode(double lat, double lon) {
    final LatLng point = LatLng(lat, lon);
    if (_bloodTrailVectorPath.isEmpty || _bloodTrailVectorPath.last != point) {
      _bloodTrailVectorPath.add(point);
    }
  }

  void clearAllPaths() {
    _activeHuntingPath.clear();
    _bloodTrailVectorPath.clear();
  }
}
