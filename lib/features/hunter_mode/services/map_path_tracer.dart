import 'package:latlong2/latlong2.dart';


class MapPathTracer {
  static final MapPathTracer instance = MapPathTracer._internal();
  MapPathTracer._internal();


  final List<LatLng> _activeHuntingPath = [];
  bool _isTrackingActive = false;


  bool get isTracking => _isTrackingActive;
  List<LatLng> get currentPath => List.unmodifiable(_activeHuntingPath);


  // Toggle the path recording engine lifecycle
  void startNewPathTracing() {
    _activeHuntingPath.clear();
    _isTrackingActive = true;
    print('📍 PATH TRACER ACTIVE: Initiating off-grid trail breadcrumb recording.');
  }


  void stopPathTracing() {
    _isTrackingActive = false;
    print('🛑 PATH TRACER PAUSED: Trail logging frozen.');
  }


  // Append new telemetry coordinate check-ins into the trail tracking array
  void appendCoordinate(double lat, double lon) {
    if (!_isTrackingActive) return;
    
    final LatLng point = LatLng(lat, lon);
    
    // Safety filter: Avoid logging duplicate resting position nodes
    if (_activeHuntingPath.isEmpty || _activeHuntingPath.last != point) {
      _activeHuntingPath.add(point);
    }
  }


  void clearRecordedPath() {
    _activeHuntingPath.clear();
  }
}
