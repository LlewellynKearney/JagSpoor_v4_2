import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/models/client_profile.dart';
import '../data/services/client_roster_manager.dart';

/// Outfitter Client Roster — manage the PH's client hunter book.
///
/// Reactive, searchable list of [ClientProfile] entries scoped to the
/// signed-in outfitter. Tap a card to view / edit a client or remove them
/// (with a confirmation modal). "Add Client" opens a sheet capturing name,
/// passport/ID, contact, address, and optional assigned package / booking.
class ClientRosterScreen extends StatefulWidget {
  final ThemeController theme;

  const ClientRosterScreen({super.key, required this.theme});

  @override
  State<ClientRosterScreen> createState() => _ClientRosterScreenState();
}

class _ClientRosterScreenState extends State<ClientRosterScreen> {
  final _manager = ClientRosterManager.instance;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ClientProfile> _filter(List<ClientProfile> clients) {
    if (_query.isEmpty) return clients;
    final q = _query.toLowerCase();
    return clients
        .where((c) =>
            c.fullName.toLowerCase().contains(q) ||
            c.idPassportNumber.toLowerCase().contains(q) ||
            c.cellNumber.toLowerCase().contains(q) ||
            c.email.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.cardColor,
        foregroundColor: theme.textColor,
        title: const Text('Client Roster'),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: theme.accentColor,
        foregroundColor: theme.backgroundColor,
        onPressed: () => _openEditor(null),
        child: const Icon(Icons.person_add_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: theme.textColor),
              decoration: InputDecoration(
                hintText: 'Search by name, ID, phone, email…',
                hintStyle: TextStyle(color: theme.subtitleColor),
                prefixIcon: Icon(Icons.search, color: theme.subtitleColor),
                filled: true,
                fillColor: theme.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ClientProfile>>(
              stream: _manager.getMyClientsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _EmptyState(
                    theme: theme,
                    icon: Icons.error_outline_rounded,
                    title: 'Could not load clients',
                    message: snapshot.error.toString(),
                  );
                }
                final all = snapshot.data ?? const <ClientProfile>[];
                final clients = _filter(all);
                if (clients.isEmpty) {
                  return _EmptyState(
                    theme: theme,
                    icon: Icons.group_rounded,
                    title: all.isEmpty
                        ? 'No clients in your roster yet'
                        : 'No clients match your search',
                    message: all.isEmpty
                        ? 'Tap + to add your first client hunter.'
                        : 'Try a different search term.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: clients.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final c = clients[i];
                    return _ClientCard(
                      client: c,
                      theme: theme,
                      onTap: () => _openEditor(c),
                      onDelete: () => _confirmDelete(c),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openEditor(ClientProfile? existing) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ClientEditorSheet(
        theme: widget.theme,
        existing: existing,
        onSave: (client) async {
          Navigator.of(context).pop();
          if (existing == null) {
            await _manager.addClient(client);
            _snack('Client added to roster');
          } else {
            await _manager.updateClient(
              client.copyWith(updatedAt: DateTime.now()),
            );
            _snack('Client updated');
          }
        },
      ),
    );
  }

  void _confirmDelete(ClientProfile client) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.theme.cardColor,
        title: Text('Remove client?',
            style: TextStyle(color: widget.theme.textColor)),
        content: Text(
          'Remove ${client.fullName} from your roster? Linked hunt logs and '
          'issued permits are kept (they keep their own client snapshot).',
          style: TextStyle(color: widget.theme.subtitleColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(context).pop();
              await _manager.deleteClient(client.id);
              _snack('${client.fullName} removed');
            },
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: widget.theme.accentColor),
    );
  }
}

class _ClientCard extends StatelessWidget {
  final ClientProfile client;
  final ThemeController theme;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ClientCard({
    required this.client,
    required this.theme,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: theme.cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.textColor.withAlpha(20), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: theme.accentColor.withAlpha(40),
                foregroundColor: theme.accentColor,
                child: const Icon(Icons.person_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.fullName,
                      style: TextStyle(
                        color: theme.textColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    if (client.idPassportNumber.isNotEmpty ||
                        client.nationality.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (client.idPassportNumber.isNotEmpty)
                            client.idPassportNumber,
                          if (client.nationality.isNotEmpty)
                            client.nationality,
                        ].join(' • '),
                        style: TextStyle(
                            color: theme.subtitleColor, fontSize: 12),
                      ),
                    ],
                    if (client.cellNumber.isNotEmpty ||
                        client.email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (client.cellNumber.isNotEmpty)
                            '☎ ${client.cellNumber}',
                          if (client.email.isNotEmpty) client.email,
                        ].join('  '),
                        style: TextStyle(
                            color: theme.subtitleColor, fontSize: 12),
                      ),
                    ],
                    if (client.assignedPackageName != null) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          _chip(Icons.inventory_2_outlined,
                              client.assignedPackageName!),
                          if (client.permitReferenceIds.isNotEmpty)
                            _chip(Icons.description_outlined,
                                '${client.permitReferenceIds.length} permit(s)'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    color: Colors.red.withAlpha(180)),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.accentColor.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.accentColor),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: theme.accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ClientEditorSheet extends StatefulWidget {
  final ThemeController theme;
  final ClientProfile? existing;
  final Future<void> Function(ClientProfile client) onSave;

  const _ClientEditorSheet({
    required this.theme,
    required this.onSave,
    this.existing,
  });

  @override
  State<_ClientEditorSheet> createState() => _ClientEditorSheetState();
}

class _ClientEditorSheetState extends State<_ClientEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _nationalityController = TextEditingController();
  final _cellController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _packageNameController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameController.text = e.fullName;
      _idController.text = e.idPassportNumber;
      _nationalityController.text = e.nationality;
      _cellController.text = e.cellNumber;
      _emailController.text = e.email;
      _addressController.text = e.address;
      _packageNameController.text = e.assignedPackageName ?? '';
      _notesController.text = e.notes ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _nationalityController.dispose();
    _cellController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _packageNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final padBottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: padBottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.subtitleColor.withAlpha(60),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                widget.existing == null
                    ? 'Add Client Hunter'
                    : 'Edit Client Hunter',
                style: TextStyle(
                    color: theme.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _field(_nameController, 'Full Name *',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null),
              const SizedBox(height: 12),
              _field(_idController, 'Passport / ID Number',
                  hint: 'e.g. SA passport or ID'),
              const SizedBox(height: 12),
              _field(_nationalityController, 'Nationality',
                  hint: 'e.g. South African'),
              const SizedBox(height: 12),
              _field(_cellController, 'Cell Number',
                  keyboard: TextInputType.phone),
              const SizedBox(height: 12),
              _field(_emailController, 'Email',
                  keyboard: TextInputType.emailAddress),
              const SizedBox(height: 12),
              _field(_addressController, 'Address', maxLines: 2),
              const SizedBox(height: 12),
              _field(_packageNameController, 'Assigned Package / Booking',
                  hint: 'Optional package name'),
              const SizedBox(height: 12),
              _field(_notesController, 'Notes', maxLines: 3),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.accentColor,
                  foregroundColor: theme.backgroundColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check_rounded),
                label: Text(widget.existing == null ? 'ADD TO ROSTER' : 'SAVE'),
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;
                  final existing = widget.existing;
                  final client = ClientProfile(
                    id: existing?.id ?? '',
                    outfitterId: existing?.outfitterId ?? '',
                    fullName: _nameController.text.trim(),
                    idPassportNumber: _idController.text.trim(),
                    nationality: _nationalityController.text.trim(),
                    cellNumber: _cellController.text.trim(),
                    email: _emailController.text.trim(),
                    address: _addressController.text.trim(),
                    assignedPackageId: existing?.assignedPackageId,
                    assignedPackageName: _packageNameController.text.trim().isEmpty
                        ? existing?.assignedPackageName
                        : _packageNameController.text.trim(),
                    assignedBookingId: existing?.assignedBookingId,
                    permitReferenceIds:
                        existing?.permitReferenceIds ?? const [],
                    notes: _notesController.text.trim().isEmpty
                        ? null
                        : _notesController.text.trim(),
                    createdAt: existing?.createdAt,
                  );
                  await widget.onSave(client);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    TextInputType? keyboard,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    final theme = widget.theme;
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      maxLines: maxLines,
      style: TextStyle(color: theme.textColor),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: theme.subtitleColor),
        hintText: hint,
        hintStyle: TextStyle(color: theme.subtitleColor.withAlpha(80)),
        filled: true,
        fillColor: theme.backgroundColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.textColor.withAlpha(20)),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ThemeController theme;
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.theme,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.subtitleColor.withAlpha(120)),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: theme.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.subtitleColor, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
