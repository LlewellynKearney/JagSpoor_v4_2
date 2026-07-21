import 'package:flutter/material.dart';
import '../../shared/data/services/local_database_service.dart';
import '../data/models/carcass_record.dart';

class SlaghuisMatrixScreen extends StatefulWidget {
  const SlaghuisMatrixScreen({super.key});

  @override
  State<SlaghuisMatrixScreen> createState() => _SlaghuisMatrixScreenState();
}

class _SlaghuisMatrixScreenState extends State<SlaghuisMatrixScreen> {
  final LocalDatabaseService _dbService = LocalDatabaseService();
  final _formKey = GlobalKey<FormState>();
  
  String _selectedSpecies = 'Impala';
  double _weight = 0.0;
  
  static const Color accentGold = Color(0xFFC5A059);
  static const Color deepWalnut = Color(0xFF3E2723);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('SLAGHUIS MATRIX', 
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white)),
        backgroundColor: deepWalnut,
        elevation: 0,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _dbService.database.then((db) => db.query('carcass_records')),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text('COLDROOM EMPTY', style: TextStyle(color: Colors.grey, letterSpacing: 2)),
            );
          }

          final records = snapshot.data!.map((m) => CarcassRecord.fromMap(m)).toList();

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              return Card(
                color: const Color(0xFF1A1A1A),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: record.isDirty == 1 ? Colors.orange : accentGold.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(record.species.toUpperCase(), 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  subtitle: Text('WEIGHT: ${record.carcassWeight}kg', style: const TextStyle(color: Colors.grey)),
                  trailing: Text('${record.coldroomDays} DAYS', style: const TextStyle(color: accentGold, fontWeight: FontWeight.bold)),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: accentGold,
        onPressed: () => _showAddCarcassModal(context),
        label: const Text('NEW ENTRY', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }

  void _showAddCarcassModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20, right: 20, top: 20
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('LOG NEW CARCASS', 
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _selectedSpecies,
                dropdownColor: Colors.black,
                style: const TextStyle(color: Colors.white),
                items: ['Impala', 'Kudu', 'Warthog', 'Blue Wildebeest', 'Eland']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _selectedSpecies = v!),
                decoration: const InputDecoration(
                  labelText: 'Species',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Carcass Weight (kg)',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                ),
                onSaved: (v) => _weight = double.tryParse(v ?? '0') ?? 0.0,
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentGold,
                  minimumSize: const Size(double.infinity, 50)
                ),
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    _formKey.currentState!.save();
                    final record = CarcassRecord(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      hunterId: 'CURRENT_SESSION_ID',
                      species: _selectedSpecies,
                      carcassWeight: _weight,
                      slaughterFee: 150.0,
                    );
                    await _dbService.database.then((db) => db.insert('carcass_records', record.toMap()));
                    if (!mounted) return;
                    Navigator.pop(context);
                    setState(() {});
                  }
                },
                child: const Text('ADD TO COLDROOM', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
