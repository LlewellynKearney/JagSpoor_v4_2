class CarcassRecord {
  final String id;
  final String hunterId;
  final String species;
  final double carcassWeight;
  final double slaughterFee;
  final int coldroomDays;
  final String status;
  final int isDirty;

  CarcassRecord({
    required this.id,
    required this.hunterId,
    required this.species,
    required this.carcassWeight,
    required this.slaughterFee,
    this.coldroomDays = 0,
    this.status = "In Coldroom",
    this.isDirty = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      "id": id,
      "hunterId": hunterId,
      "species": species,
      "carcassWeight": carcassWeight,
      "slaughterFee": slaughterFee,
      "coldroomDays": coldroomDays,
      "status": status,
      "isDirty": isDirty,
    };
  }

  factory CarcassRecord.fromMap(Map<String, dynamic> map) {
    return CarcassRecord(
      id: map["id"] ?? "",
      hunterId: map["hunterId"] ?? "",
      species: map["species"] ?? "Unknown",
      carcassWeight: (map["carcassWeight"] as num?)?.toDouble() ?? 0.0,
      slaughterFee: (map["slaughterFee"] as num?)?.toDouble() ?? 0.0,
      coldroomDays: map["coldroomDays"] ?? 0,
      status: map["status"] ?? "In Coldroom",
      isDirty: map["isDirty"] ?? 0,
    );
  }

  double calculateHunterTotal(double ratePerKg) {
    // Applying your 5% commission (1.05 markup) to the final butchery cost
    double rawTotal = (carcassWeight * ratePerKg) + slaughterFee;
    return rawTotal * 1.05;
  }
}
