import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';

/// In-app CMS for editors/admins.
///
/// Scope (pilot):
///  * Editions — list with rights status; publish/unpublish (RLS blocks
///    publishing when rights are not cleared: `edition_is_public` is false so
///    it simply never surfaces for readers).
///  * Verse contents — pick edition + verse, edit body/notes, set status.
///  * Rights — admin only: view/edit status, license, attribution.
///  * Audit — admin only: recent changes.
/// All writes go straight through Supabase with the user's JWT; RLS enforces
/// role. A full web CMS (Supabase Studio or a Next.js admin) can be layered on
/// later without schema changes.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});
  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 4, vsync: this);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final client = ref.watch(supabaseProvider);
    final role = ref.watch(userRoleProvider).value ?? 'reader';
    if (client == null || (role != 'editor' && role != 'admin')) {
      return Scaffold(appBar: AppBar(title: Text(l.admin)), body: const Center(child: Text('Editor or admin role required.')));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l.adminCms),
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Editions'), Tab(text: 'Contents'), Tab(text: 'Rights'), Tab(text: 'Audit')]),
      ),
      body: TabBarView(controller: _tabs, children: [
        _EditionsTab(client: client, isAdmin: role == 'admin'),
        _ContentsTab(client: client),
        _RightsTab(client: client, isAdmin: role == 'admin'),
        _AuditTab(client: client, isAdmin: role == 'admin'),
      ]),
    );
  }
}

// ----------------------------------------------------------------- editions
class _EditionsTab extends StatefulWidget {
  const _EditionsTab({required this.client, required this.isAdmin});
  final SupabaseClient client;
  final bool isAdmin;
  @override
  State<_EditionsTab> createState() => _EditionsTabState();
}

class _EditionsTabState extends State<_EditionsTab> {
  late Future<List<Map<String, dynamic>>> _f = _load();
  Future<List<Map<String, dynamic>>> _load() => widget.client.from('v_editions').select().order('sort_order');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _f,
      builder: (c, snap) {
        if (!snap.hasData) return snap.hasError ? Center(child: Text('${snap.error}')) : const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        return RefreshIndicator(
          onRefresh: () async => setState(() => _f = _load()),
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (c, i) {
              final e = rows[i];
              final cleared = const {'public_domain', 'open_license', 'permission_granted', 'original'}.contains(e['rights_status']);
              return ListTile(
                leading: Icon(cleared ? Icons.verified : Icons.gpp_bad_outlined, color: cleared ? Colors.green : Colors.red),
                title: Text(e['title']),
                subtitle: Text('${e['slug']} · ${e['kind']} · ${e['language_code']}/${e['script_code']} · rights: ${e['rights_status']} · ${e['status']}'),
                trailing: DropdownButton<String>(
                  value: e['status'],
                  items: const ['draft', 'in_review', 'published', 'archived'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) async {
                    if (v == null) return;
                    if (v == 'published' && !cleared) {
                      ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Cannot publish: rights not cleared. Fix rights first.')));
                      return;
                    }
                    await widget.client.from('editions').update({'status': v}).eq('id', e['id']);
                    setState(() => _f = _load());
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ----------------------------------------------------------------- contents
class _ContentsTab extends StatefulWidget {
  const _ContentsTab({required this.client});
  final SupabaseClient client;
  @override
  State<_ContentsTab> createState() => _ContentsTabState();
}

class _ContentsTabState extends State<_ContentsTab> {
  String? _editionId;
  List<Map<String, dynamic>> _editions = [];
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.client.from('editions').select('id, slug, title').order('sort_order').then((r) => setState(() => _editions = r));
  }

  Future<void> _load() async {
    if (_editionId == null) return;
    setState(() => _loading = true);
    final rows = await widget.client.from('verse_contents').select('id, body, notes, status, verses!inner(ref)').eq('edition_id', _editionId!).order('ref', referencedTable: 'verses');
    setState(() { _rows = rows; _loading = false; });
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final body = TextEditingController(text: row['body']);
    final notes = TextEditingController(text: row['notes'] ?? '');
    var status = row['status'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text('Verse ${row['verses']['ref']}'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: body, maxLines: 8, decoration: const InputDecoration(labelText: 'Body', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes (public)', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: status,
                  items: const ['draft', 'in_review', 'published', 'archived'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setS(() => status = v ?? status),
                  decoration: const InputDecoration(labelText: 'Status'),
                ),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save'))],
        ),
      ),
    );
    if (ok == true) {
      try {
        await widget.client.from('verse_contents').update({'body': body.text, 'notes': notes.text.isEmpty ? null : notes.text, 'status': status}).eq('id', row['id']);
        await _load();
      } on PostgrestException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: DropdownButtonFormField<String>(
          value: _editionId,
          hint: const Text('Choose edition'),
          items: _editions.map((e) => DropdownMenuItem(value: e['id'] as String, child: Text('${e['title']} (${e['slug']})', overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) { setState(() => _editionId = v); _load(); },
        ),
      ),
      if (_loading) const LinearProgressIndicator(),
      Expanded(
        child: ListView.builder(
          itemCount: _rows.length,
          itemBuilder: (c, i) {
            final r = _rows[i];
            return ListTile(
              leading: Text(r['verses']['ref'], style: Theme.of(c).textTheme.labelLarge),
              title: Text(r['body'], maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(r['status']),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _edit(r),
            );
          },
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------- rights
class _RightsTab extends StatefulWidget {
  const _RightsTab({required this.client, required this.isAdmin});
  final SupabaseClient client;
  final bool isAdmin;
  @override
  State<_RightsTab> createState() => _RightsTabState();
}

class _RightsTabState extends State<_RightsTab> {
  late Future<List<Map<String, dynamic>>> _f = widget.client.from('rights').select('id, status, license, license_url, rights_holder, attribution_text, permission_granted_on, permission_expires_on, notes, sources(title)').order('created_at');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _f,
      builder: (c, snap) {
        if (!snap.hasData) return snap.hasError ? Center(child: Text('${snap.error}')) : const Center(child: CircularProgressIndicator());
        return ListView(children: [
          for (final r in snap.data!)
            ListTile(
              leading: Icon(const {'public_domain', 'open_license', 'permission_granted', 'original'}.contains(r['status']) ? Icons.check_circle : Icons.block, color: const {'public_domain', 'open_license', 'permission_granted', 'original'}.contains(r['status']) ? Colors.green : Colors.red),
              title: Text('${r['status']} · ${r['license'] ?? '-'}'),
              subtitle: Text('${r['attribution_text']}\n${r['sources']?['title'] ?? ''}'),
              isThreeLine: true,
              trailing: widget.isAdmin
                  ? DropdownButton<String>(
                      value: r['status'],
                      items: const ['public_domain', 'open_license', 'permission_granted', 'original', 'pending', 'restricted'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (v) async {
                        if (v == null) return;
                        try {
                          await widget.client.from('rights').update({'status': v}).eq('id', r['id']);
                          setState(() => _f = widget.client.from('rights').select('id, status, license, license_url, rights_holder, attribution_text, permission_granted_on, permission_expires_on, notes, sources(title)').order('created_at'));
                        } on PostgrestException catch (e) {
                          if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(e.message)));
                        }
                      },
                    )
                  : null,
            ),
        ]);
      },
    );
  }
}

// -------------------------------------------------------------------- audit
class _AuditTab extends StatelessWidget {
  const _AuditTab({required this.client, required this.isAdmin});
  final SupabaseClient client;
  final bool isAdmin;
  @override
  Widget build(BuildContext context) {
    if (!isAdmin) return const Center(child: Text('Admin only.'));
    return FutureBuilder(
      future: client.from('audit_log').select('table_name, row_id, action, actor_id, at').order('at', ascending: false).limit(200),
      builder: (c, snap) {
        if (!snap.hasData) return snap.hasError ? Center(child: Text('${snap.error}')) : const Center(child: CircularProgressIndicator());
        return ListView(children: [
          for (final a in snap.data!)
            ListTile(dense: true, title: Text('${a['action']} ${a['table_name']}'), subtitle: Text('${a['at']} · ${a['actor_id'] ?? 'system'}'), trailing: Text((a['row_id'] ?? '').toString().substring(0, 8))),
        ]);
      },
    );
  }
}
