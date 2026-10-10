import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'update_checker.dart';

void main() => runApp(const DietDeskApp());

class DietDeskApp extends StatelessWidget {
  const DietDeskApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DietDesk',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00897B)),
        ),
        home: const HomeShell(),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdate(context));
  }

  static const _tabs = [
    CrudScreen(
      title: 'Clients',
      storeKey: 'clients',
      fields: {'name': 'Name', 'phone': 'Phone', 'goal': 'Goal (e.g. Weight loss)'},
      subtitleKeys: ['phone', 'goal'],
    ),
    CrudScreen(
      title: 'Appointments',
      storeKey: 'appointments',
      fields: {'client': 'Client name', 'date': 'Date (DD-MM-YYYY)', 'time': 'Time', 'type': 'Type (Call/Visit)'},
      subtitleKeys: ['date', 'time', 'type'],
      titleKey: 'client',
    ),
    CrudScreen(
      title: 'Payments',
      storeKey: 'payments',
      fields: {'client': 'Client name', 'amount': 'Amount (Rs)', 'package': 'Package', 'status': 'Status (Paid/Pending)'},
      subtitleKeys: ['package', 'amount', 'status'],
      titleKey: 'client',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _i, children: _tabs),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _i,
          onDestinationSelected: (v) => setState(() => _i = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.people), label: 'Clients'),
            NavigationDestination(icon: Icon(Icons.event), label: 'Appointments'),
            NavigationDestination(icon: Icon(Icons.payments), label: 'Payments'),
          ],
        ),
      );
}

class CrudScreen extends StatefulWidget {
  final String title, storeKey, titleKey;
  final Map<String, String> fields;
  final List<String> subtitleKeys;
  const CrudScreen({
    super.key,
    required this.title,
    required this.storeKey,
    required this.fields,
    required this.subtitleKeys,
    this.titleKey = 'name',
  });
  @override
  State<CrudScreen> createState() => _CrudScreenState();
}

class _CrudScreenState extends State<CrudScreen> {
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(widget.storeKey);
    if (raw != null) {
      setState(() => _items = (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList());
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(widget.storeKey, jsonEncode(_items));
  }

  Future<void> _add() async {
    final ctrls = {for (final k in widget.fields.keys) k: TextEditingController()};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add ${widget.title}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in widget.fields.entries)
                TextField(controller: ctrls[e.key], decoration: InputDecoration(labelText: e.value)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _items.insert(0, {for (final e in ctrls.entries) e.key: e.value.text.trim()}));
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
        body: _items.isEmpty
            ? Center(child: Text('No ${widget.title} yet. Tap + to add.'))
            : ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final d = _items[i];
                  return Dismissible(
                    key: ValueKey('${widget.storeKey}$i${d.hashCode}'),
                    background: Container(color: Colors.red),
                    onDismissed: (_) {
                      setState(() => _items.removeAt(i));
                      _save();
                    },
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text('${d[widget.titleKey] ?? ''}'),
                      subtitle: Text(widget.subtitleKeys.map((k) => '${d[k] ?? ''}').join('  •  ')),
                    ),
                  );
                },
              ),
      );
}
