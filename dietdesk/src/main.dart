import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'update_checker.dart';

// =====================================================================
// DietDesk - original code. No third-party app code, text or assets used.
// =====================================================================

// ---------- helpers ----------
String _two(int n) => n.toString().padLeft(2, '0');
String fmtDate(DateTime d) => '${_two(d.day)}-${_two(d.month)}-${d.year}';

DateTime? parseDate(String s) {
  final p = s.split('-');
  if (p.length != 3) return null;
  final d = int.tryParse(p[0]), m = int.tryParse(p[1]), y = int.tryParse(p[2]);
  if (d == null || m == null || y == null) return null;
  return DateTime(y, m, d);
}

double num0(dynamic v) => double.tryParse('$v'.replaceAll(',', '')) ?? 0;

String waPhone(String raw) {
  final d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  return d.length == 10 ? '91$d' : d;
}

Future<void> openUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

Future<void> shareWhatsApp(String phone, String text) {
  final p = waPhone(phone);
  return openUrl('https://wa.me/$p?text=${Uri.encodeComponent(text)}');
}

Map<String, dynamic> deepCopy(Map m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

String phoneOf(String clientName) {
  for (final c in Store.i.data['clients']!) {
    if ('${c['name']}' == clientName) return '${c['phone'] ?? ''}';
  }
  return '';
}

// ---------- storage ----------
const kinds = [
  'clients', 'appointments', 'payments', 'weights', 'plans',
  'notes', 'diary', 'activity', 'dietplans', 'templates'
];

class Store extends ChangeNotifier {
  static final Store i = Store._();
  Store._();
  final Map<String, List<Map<String, dynamic>>> data = {for (final k in kinds) k: []};

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    for (final k in kinds) {
      final raw = p.getString(k);
      if (raw != null) {
        data[k] = (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
    notifyListeners();
  }

  Future<void> touch(String k) async {
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(k, jsonEncode(data[k]));
  }

  Future<void> add(String k, Map<String, dynamic> m) async {
    data[k]!.insert(0, m);
    await touch(k);
  }

  Future<void> remove(String k, Map<String, dynamic> m) async {
    data[k]!.removeWhere((e) => identical(e, m));
    await touch(k);
  }

  Future<bool> restore(String raw) async {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (!m.keys.any((k) => kinds.contains(k))) return false;
      for (final k in kinds) {
        final v = m[k];
        data[k] = v is List ? v.map((e) => Map<String, dynamic>.from(e)).toList() : [];
        await touch(k);
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

// ---------- form fields ----------
enum K { text, phone, number, date, time, choice, client, long }

class F {
  final String key, label;
  final K kind;
  final List<String> options;
  const F(this.key, this.label, [this.kind = K.text, this.options = const []]);
}

Widget inputFor(BuildContext ctx, F f, TextEditingController c, List<String> names) {
  const pad = EdgeInsets.only(top: 8);
  switch (f.kind) {
    case K.date:
      return Padding(
        padding: pad,
        child: TextField(
          controller: c,
          readOnly: true,
          decoration: InputDecoration(labelText: f.label, suffixIcon: const Icon(Icons.calendar_today)),
          onTap: () async {
            final d = await showDatePicker(
              context: ctx,
              initialDate: parseDate(c.text) ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (d != null) c.text = fmtDate(d);
          },
        ),
      );
    case K.time:
      return Padding(
        padding: pad,
        child: TextField(
          controller: c,
          readOnly: true,
          decoration: InputDecoration(labelText: f.label, suffixIcon: const Icon(Icons.access_time)),
          onTap: () async {
            final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
            if (t != null) c.text = t.format(ctx);
          },
        ),
      );
    case K.choice:
      return Padding(
        padding: pad,
        child: DropdownButtonFormField<String>(
          decoration: InputDecoration(labelText: f.label),
          hint: Text(c.text.isEmpty ? f.options.first : c.text),
          items: [for (final o in f.options) DropdownMenuItem(value: o, child: Text(o))],
          onChanged: (v) => c.text = v ?? f.options.first,
        ),
      );
    case K.client:
      return Padding(
        padding: pad,
        child: DropdownButtonFormField<String>(
          decoration: InputDecoration(labelText: f.label),
          hint: Text(c.text.isEmpty ? 'Select client' : c.text),
          items: [for (final n in names) DropdownMenuItem(value: n, child: Text(n))],
          onChanged: (v) => c.text = v ?? c.text,
        ),
      );
    case K.long:
      return Padding(
        padding: pad,
        child: TextField(
          controller: c,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: f.label),
        ),
      );
    case K.phone:
      return TextField(controller: c, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: f.label));
    case K.number:
      return TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: f.label));
    case K.text:
      return TextField(controller: c, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: f.label));
  }
}

Future<Map<String, dynamic>?> showForm(
  BuildContext context,
  String title,
  List<F> fields, {
  Map<String, String> initial = const {},
}) async {
  final names = Store.i.data['clients']!.map((c) => '${c['name']}').toList();
  if (fields.any((f) => f.kind == K.client) && names.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pehle Clients tab mein ek client add karo')),
    );
    return null;
  }
  final ctrls = <String, TextEditingController>{};
  for (final f in fields) {
    var v = initial[f.key] ?? '';
    if (v.isEmpty) {
      if (f.kind == K.choice) v = f.options.first;
      if (f.kind == K.client) v = names.first;
      if (f.kind == K.date) v = fmtDate(DateTime.now());
      if (f.kind == K.time) v = TimeOfDay.now().format(context);
    }
    ctrls[f.key] = TextEditingController(text: v);
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final f in fields) inputFor(ctx, f, ctrls[f.key]!, names)],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    ),
  );
  if (ok != true) return null;
  return {for (final e in ctrls.entries) e.key: e.value.text.trim()};
}

Future<bool> confirmDelete(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete?'),
      content: const Text('Ye entry hamesha ke liye hat jayegi.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
      ],
    ),
  );
  return r == true;
}

void snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

// ---------- backup ----------
Future<void> backupMenu(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Backup copy karo'),
            subtitle: const Text('Saara data copy hoga. WhatsApp/Notes mein paste karke save kar lo.'),
            onTap: () async {
              Navigator.pop(ctx);
              await Clipboard.setData(ClipboardData(text: jsonEncode(Store.i.data)));
              if (context.mounted) snack(context, 'Backup copy ho gaya');
            },
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore karo'),
            subtitle: const Text('Backup paste karke data wapas lao (purana data replace hoga)'),
            onTap: () {
              Navigator.pop(ctx);
              restoreDialog(context);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> restoreDialog(BuildContext context) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Restore'),
      content: TextField(
        controller: c,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(hintText: 'Backup yahan paste karo'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
      ],
    ),
  );
  if (ok != true) return;
  final done = await Store.i.restore(c.text.trim());
  if (context.mounted) snack(context, done ? 'Data restore ho gaya' : 'Backup sahi nahi hai');
}

// ---------- app ----------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.i.load();
  runApp(const DietDeskApp());
}

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

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(
          index: _i,
          children: const [
            Dashboard(),
            ClientsScreen(),
            CalendarScreen(),
            PaymentsScreen(),
            TemplatesScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _i,
          onDestinationSelected: (v) => setState(() => _i = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.people), label: 'Clients'),
            NavigationDestination(icon: Icon(Icons.event), label: 'Calendar'),
            NavigationDestination(icon: Icon(Icons.payments), label: 'Payments'),
            NavigationDestination(icon: Icon(Icons.restaurant_menu), label: 'Diets'),
          ],
        ),
      );
}

// ---------- dashboard ----------
class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  Widget _stat(BuildContext ctx, String label, String value, IconData icon) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(height: 8),
                Text(value, style: Theme.of(ctx).textTheme.headlineSmall),
                Text(label, style: Theme.of(ctx).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (ctx, _) {
          final d = Store.i.data;
          final today = fmtDate(DateTime.now());
          final todays = d['appointments']!
              .where((a) => a['date'] == today && a['status'] != 'Cancelled')
              .toList();
          final pendingAmt = d['payments']!
              .where((p) => p['status'] == 'Pending')
              .fold<double>(0, (s, p) => s + num0(p['amount']));
          final paidAmt = d['payments']!
              .where((p) => p['status'] == 'Paid')
              .fold<double>(0, (s, p) => s + num0(p['amount']));
          return Scaffold(
            appBar: AppBar(
              title: const Text('DietDesk'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.backup),
                  tooltip: 'Backup / Restore',
                  onPressed: () => backupMenu(ctx),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(children: [
                  _stat(ctx, 'Clients', '${d['clients']!.length}', Icons.people),
                  _stat(ctx, 'Aaj ki appointments', '${todays.length}', Icons.event),
                ]),
                Row(children: [
                  _stat(ctx, 'Received (Rs)', paidAmt.toStringAsFixed(0), Icons.check_circle),
                  _stat(ctx, 'Pending (Rs)', pendingAmt.toStringAsFixed(0), Icons.hourglass_bottom),
                ]),
                const SizedBox(height: 8),
                Text('Aaj ki appointments', style: Theme.of(ctx).textTheme.titleMedium),
                if (todays.isEmpty)
                  const Padding(padding: EdgeInsets.all(12), child: Text('Aaj koi appointment nahi.')),
                for (final a in todays)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.event)),
                    title: Text('${a['client']}'),
                    subtitle: Text('${a['time']}  •  ${a['type']}  •  ${a['status'] ?? 'Confirmed'}'),
                  ),
              ],
            ),
          );
        },
      );
}

// ---------- clients ----------
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});
  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (ctx, _) {
          final items = Store.i.data['clients']!.where((c) {
            final t = '${c['name']} ${c['phone']}'.toLowerCase();
            return t.contains(_q.toLowerCase());
          }).toList();
          return Scaffold(
            appBar: AppBar(title: const Text('Clients')),
            floatingActionButton: FloatingActionButton(
              onPressed: () async {
                final r = await showForm(ctx, 'Add client', const [
                  F('name', 'Name'),
                  F('phone', 'Phone', K.phone),
                  F('goal', 'Goal', K.choice, ['Weight loss', 'Weight gain', 'Maintenance', 'Medical diet']),
                ]);
                if (r != null && '${r['name']}'.isNotEmpty) Store.i.add('clients', r);
              },
              child: const Icon(Icons.person_add),
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search name / phone',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('Koi client nahi. + dabake add karo.'))
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final c = items[i];
                            return Dismissible(
                              key: ObjectKey(c),
                              background: Container(color: Colors.red),
                              confirmDismiss: (_) => confirmDelete(ctx),
                              onDismissed: (_) => Store.i.remove('clients', c),
                              child: ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.person)),
                                title: Text('${c['name']}'),
                                subtitle: Text('${c['phone'] ?? ''}  •  ${c['goal'] ?? ''}'),
                                onTap: () => Navigator.push(
                                  ctx,
                                  MaterialPageRoute(builder: (_) => ClientProfile(c)),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
}

Future<void> editClient(BuildContext ctx, Map<String, dynamic> c, String title, List<F> fields) async {
  final r = await showForm(ctx, title, fields, initial: {for (final f in fields) f.key: '${c[f.key] ?? ''}'});
  if (r != null) {
    c.addAll(r);
    Store.i.touch('clients');
  }
}

class ClientProfile extends StatelessWidget {
  final Map<String, dynamic> client;
  const ClientProfile(this.client, {super.key});

  static const basicFields = [
    F('age', 'Age', K.number),
    F('gender', 'Gender', K.choice, ['Female', 'Male', 'Other']),
    F('height', 'Height (cm)', K.number),
    F('city', 'City'),
  ];
  static const medicalFields = [
    F('conditions', 'Medical conditions', K.long),
    F('allergies', 'Allergies', K.long),
    F('medicines', 'Medicines', K.long),
  ];
  static const foodFields = [
    F('diettype', 'Diet type', K.choice, ['Vegetarian', 'Non-vegetarian', 'Eggetarian', 'Vegan']),
    F('likes', 'Likes', K.long),
    F('dislikes', 'Dislikes', K.long),
    F('water', 'Water (litres/day)', K.number),
  ];

  Widget _tile(BuildContext ctx, IconData icon, String label, VoidCallback onTap) => Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(height: 6),
                Text(label, textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );

  List<Widget> _info(Map<String, String> lines) {
    final out = <Widget>[];
    lines.forEach((label, key) {
      final v = '${client[key] ?? ''}'.trim();
      if (v.isNotEmpty) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('$label: $v'),
        ));
      }
    });
    return out;
  }

  void _go(BuildContext ctx, Widget w) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final name = '${client['name']}';
    final phone = '${client['phone'] ?? ''}';
    return ListenableBuilder(
      listenable: Store.i,
      builder: (ctx, _) {
        final info = _info({
          'Age': 'age',
          'Gender': 'gender',
          'Height (cm)': 'height',
          'City': 'city',
          'Medical': 'conditions',
          'Allergies': 'allergies',
          'Medicines': 'medicines',
          'Diet type': 'diettype',
          'Likes': 'likes',
          'Dislikes': 'dislikes',
          'Water (L)': 'water',
        });
        return Scaffold(
          appBar: AppBar(title: Text(name)),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(ctx).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('$phone  •  ${client['goal'] ?? ''}'),
                      ...info,
                      const SizedBox(height: 12),
                      Row(children: [
                        OutlinedButton.icon(
                          onPressed: phone.isEmpty ? null : () => openUrl('tel:+${waPhone(phone)}'),
                          icon: const Icon(Icons.call),
                          label: const Text('Call'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: phone.isEmpty ? null : () => openUrl('https://wa.me/${waPhone(phone)}'),
                          icon: const Icon(Icons.chat),
                          label: const Text('WhatsApp'),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.1,
                children: [
                  _tile(ctx, Icons.badge, 'Basic info', () => editClient(ctx, client, 'Basic info', basicFields)),
                  _tile(ctx, Icons.medical_services, 'Medical', () => editClient(ctx, client, 'Medical', medicalFields)),
                  _tile(ctx, Icons.fastfood, 'Food habits', () => editClient(ctx, client, 'Food habits', foodFields)),
                  _tile(ctx, Icons.restaurant_menu, 'Diet plans', () => _go(ctx, ClientDiets(name))),
                  _tile(ctx, Icons.monitor_weight, 'Measurements', () => _go(ctx, MeasureScreen(name))),
                  _tile(ctx, Icons.event, 'Appointments', () => _go(ctx, RecordsScreen(
                        client: name,
                        kind: 'appointments',
                        title: 'Appointments',
                        icon: Icons.event,
                        fields: const [
                          F('date', 'Date', K.date),
                          F('time', 'Time', K.time),
                          F('type', 'Type', K.choice, ['Call', 'Video', 'Visit']),
                          F('status', 'Status', K.choice, ['Confirmed', 'Completed', 'Cancelled']),
                          F('note', 'Note', K.long),
                        ],
                        titleOf: (m) => '${m['date']}  •  ${m['time']}',
                        subtitleOf: (m) => '${m['type']}  •  ${m['status'] ?? 'Confirmed'}  ${m['note'] ?? ''}',
                      ))),
                  _tile(ctx, Icons.payments, 'Payments', () => _go(ctx, RecordsScreen(
                        client: name,
                        kind: 'payments',
                        title: 'Payments',
                        icon: Icons.payments,
                        fields: const [
                          F('package', 'Package', K.choice, ['7 days', '15 days', '30 days', '45 days', '90 days']),
                          F('amount', 'Amount (Rs)', K.number),
                          F('from', 'From', K.date),
                          F('to', 'To', K.date),
                          F('status', 'Status', K.choice, ['Paid', 'Pending']),
                        ],
                        titleOf: (m) => 'Rs ${m['amount']}  •  ${m['package']}',
                        subtitleOf: (m) => '${m['from'] ?? ''} → ${m['to'] ?? ''}  •  ${m['status']}',
                      ))),
                  _tile(ctx, Icons.book, 'Food diary', () => _go(ctx, RecordsScreen(
                        client: name,
                        kind: 'diary',
                        title: 'Food diary',
                        icon: Icons.book,
                        fields: const [
                          F('date', 'Date', K.date),
                          F('meal', 'Meal', K.choice, ['Early morning', 'Breakfast', 'Mid morning', 'Lunch', 'Evening snack', 'Dinner', 'Late night']),
                          F('food', 'Kya khaya', K.long),
                        ],
                        titleOf: (m) => '${m['date']}  •  ${m['meal']}',
                        subtitleOf: (m) => '${m['food'] ?? ''}',
                      ))),
                  _tile(ctx, Icons.directions_run, 'Activity plan', () => _go(ctx, RecordsScreen(
                        client: name,
                        kind: 'activity',
                        title: 'Activity plan',
                        icon: Icons.directions_run,
                        fields: const [
                          F('activity', 'Activity (e.g. Walking)'),
                          F('duration', 'Duration (minutes)', K.number),
                          F('freq', 'Frequency', K.choice, ['Daily', 'Alternate days', '3x / week', '5x / week', 'Weekly']),
                          F('note', 'Note', K.long),
                        ],
                        titleOf: (m) => '${m['activity']}',
                        subtitleOf: (m) => '${m['duration']} min  •  ${m['freq']}  ${m['note'] ?? ''}',
                      ))),
                  _tile(ctx, Icons.note_alt, 'Notes', () => _go(ctx, RecordsScreen(
                        client: name,
                        kind: 'notes',
                        title: 'Notes',
                        icon: Icons.note_alt,
                        fields: const [
                          F('date', 'Date', K.date),
                          F('note', 'Note', K.long),
                        ],
                        titleOf: (m) => '${m['date']}',
                        subtitleOf: (m) => '${m['note'] ?? ''}',
                      ))),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------- generic per-client records ----------
class RecordsScreen extends StatelessWidget {
  final String client, kind, title;
  final IconData icon;
  final List<F> fields;
  final String Function(Map<String, dynamic>) titleOf, subtitleOf;

  const RecordsScreen({
    super.key,
    required this.client,
    required this.kind,
    required this.title,
    required this.icon,
    required this.fields,
    required this.titleOf,
    required this.subtitleOf,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (ctx, _) {
          final items = Store.i.data[kind]!.where((m) => m['client'] == client).toList();
          return Scaffold(
            appBar: AppBar(title: Text('$title - $client')),
            floatingActionButton: FloatingActionButton(
              onPressed: () async {
                final r = await showForm(ctx, 'Add $title', fields);
                if (r != null) {
                  r['client'] = client;
                  Store.i.add(kind, r);
                }
              },
              child: const Icon(Icons.add),
            ),
            body: items.isEmpty
                ? Center(child: Text('Abhi kuch nahi. + dabake add karo.'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final m = items[i];
                      return Dismissible(
                        key: ObjectKey(m),
                        background: Container(color: Colors.red),
                        confirmDismiss: (_) => confirmDelete(ctx),
                        onDismissed: (_) => Store.i.remove(kind, m),
                        child: ListTile(
                          leading: CircleAvatar(child: Icon(icon)),
                          title: Text(titleOf(m)),
                          subtitle: Text(subtitleOf(m)),
                        ),
                      );
                    },
                  ),
          );
        },
      );
}

// ---------- measurements ----------
class MeasureScreen extends StatefulWidget {
  final String client;
  const MeasureScreen(this.client, {super.key});
  @override
  State<MeasureScreen> createState() => _MeasureScreenState();
}

class _MeasureScreenState extends State<MeasureScreen> {
  String _metric = 'weight';
  static const metrics = {
    'weight': 'Weight (kg)',
    'waist': 'Waist (in)',
    'chest': 'Chest (in)',
    'hip': 'Hip (in)',
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (ctx, _) {
          final all = Store.i.data['weights']!.where((w) => w['client'] == widget.client).toList();
          all.sort((a, b) => (parseDate('${a['date']}') ?? DateTime(2000))
              .compareTo(parseDate('${b['date']}') ?? DateTime(2000)));
          final vals = all.map((w) => num0(w[_metric])).where((v) => v > 0).toList();
          return Scaffold(
            appBar: AppBar(title: Text('Measurements - ${widget.client}')),
            floatingActionButton: FloatingActionButton(
              onPressed: () async {
                final r = await showForm(ctx, 'Add measurement', const [
                  F('date', 'Date', K.date),
                  F('weight', 'Weight (kg)', K.number),
                  F('waist', 'Waist (in)', K.number),
                  F('chest', 'Chest (in)', K.number),
                  F('hip', 'Hip (in)', K.number),
                ]);
                if (r != null) {
                  r['client'] = widget.client;
                  Store.i.add('weights', r);
                }
              },
              child: const Icon(Icons.add),
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButton<String>(
                  value: _metric,
                  items: [for (final e in metrics.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _metric = v ?? 'weight'),
                ),
                const SizedBox(height: 8),
                if (vals.length >= 2) ...[
                  Text('${vals.first}  →  ${vals.last}   (${vals.last - vals.first > 0 ? '+' : ''}${(vals.last - vals.first).toStringAsFixed(1)})'),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 160,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: LinePainter(vals, Theme.of(ctx).colorScheme.primary),
                    ),
                  ),
                ] else
                  const Text('Graph ke liye is measurement ki kam se kam 2 entries chahiye.'),
                const SizedBox(height: 12),
                for (final w in all.reversed)
                  ListTile(
                    dense: true,
                    title: Text('${w['date']}'),
                    subtitle: Text(
                      'Wt ${w['weight'] ?? '-'} kg  •  Waist ${w['waist'] ?? '-'}  •  Chest ${w['chest'] ?? '-'}  •  Hip ${w['hip'] ?? '-'}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirmDelete(ctx)) Store.i.remove('weights', w);
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      );
}

class LinePainter extends CustomPainter {
  final List<double> v;
  final Color color;
  LinePainter(this.v, this.color);

  @override
  void paint(Canvas canvas, Size s) {
    if (v.length < 2) return;
    final mn = v.reduce(math.min), mx = v.reduce(math.max);
    final range = (mx - mn) == 0 ? 1.0 : (mx - mn);
    const pad = 10.0;
    final pts = <Offset>[
      for (var i = 0; i < v.length; i++)
        Offset(
          pad + i / (v.length - 1) * (s.width - 2 * pad),
          s.height - pad - (v[i] - mn) / range * (s.height - 2 * pad),
        ),
    ];
    final line = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, line);
    final dot = Paint()..color = color;
    for (final p in pts) {
      canvas.drawCircle(p, 4, dot);
    }
  }

  @override
  bool shouldRepaint(covariant LinePainter old) => true;
}

// ---------- calendar / appointments ----------
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _sel = fmtDate(DateTime.now());

  void _shift(int by) => setState(() => _month = DateTime(_month.year, _month.month + by));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (ctx, _) {
          final primary = Theme.of(ctx).colorScheme.primary;
          final appts = Store.i.data['appointments']!;
          final count = <String, int>{};
          for (final a in appts) {
            if (a['status'] == 'Cancelled') continue;
            final k = '${a['date']}';
            count[k] = (count[k] ?? 0) + 1;
          }
          final first = DateTime(_month.year, _month.month, 1);
          final days = DateTime(_month.year, _month.month + 1, 0).day;
          final offset = (first.weekday + 6) % 7;
          final todayStr = fmtDate(DateTime.now());
          final cells = <Widget>[for (var i = 0; i < offset; i++) const SizedBox.shrink()];
          for (var d = 1; d <= days; d++) {
            final ds = fmtDate(DateTime(_month.year, _month.month, d));
            final sel = ds == _sel;
            final n = count[ds] ?? 0;
            cells.add(InkWell(
              onTap: () => setState(() => _sel = ds),
              child: Container(
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: sel ? primary : null,
                  shape: BoxShape.circle,
                  border: (ds == todayStr && !sel) ? Border.all(color: primary) : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$d', style: TextStyle(color: sel ? Colors.white : null)),
                    if (n > 0)
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sel ? Colors.white : primary,
                        ),
                      ),
                  ],
                ),
              ),
            ));
          }
          final list = appts.where((a) => a['date'] == _sel).toList();
          return Scaffold(
            appBar: AppBar(title: const Text('Appointments')),
            floatingActionButton: FloatingActionButton(
              onPressed: () async {
                final r = await showForm(
                  ctx,
                  'New appointment',
                  const [
                    F('client', 'Client', K.client),
                    F('date', 'Date', K.date),
                    F('time', 'Time', K.time),
                    F('type', 'Type', K.choice, ['Call', 'Video', 'Visit']),
                    F('status', 'Status', K.choice, ['Confirmed', 'Completed', 'Cancelled']),
                    F('note', 'Note', K.long),
                  ],
                  initial: {'date': _sel},
                );
                if (r != null) Store.i.add('appointments', r);
              },
              child: const Icon(Icons.add),
            ),
            body: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
                    Text('${monthNames[_month.month - 1]} ${_month.year}', style: Theme.of(ctx).textTheme.titleMedium),
                    IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
                  ],
                ),
                Row(
                  children: [
                    for (final w in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
                      Expanded(child: Center(child: Text(w, style: Theme.of(ctx).textTheme.bodySmall))),
                  ],
                ),
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.1,
                  children: cells,
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(_sel, style: Theme.of(ctx).textTheme.titleSmall),
                ),
                if (list.isEmpty)
                  const Padding(padding: EdgeInsets.all(12), child: Text('Is din koi appointment nahi.')),
                for (final a in list)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.event)),
                    title: Text('${a['client']}'),
                    subtitle: Text('${a['time']}  •  ${a['type']}  •  ${a['status'] ?? 'Confirmed'}'
                        '${'${a['note'] ?? ''}'.isEmpty ? '' : '\n${a['note']}'}'),
                    isThreeLine: '${a['note'] ?? ''}'.isNotEmpty,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'Delete') {
                          if (await confirmDelete(ctx)) Store.i.remove('appointments', a);
                        } else {
                          a['status'] = v;
                          Store.i.touch('appointments');
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'Confirmed', child: Text('Confirmed')),
                        PopupMenuItem(value: 'Completed', child: Text('Completed')),
                        PopupMenuItem(value: 'Cancelled', child: Text('Cancelled')),
                        PopupMenuItem(value: 'Delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      );
}

// ---------- payments ----------
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (ctx, _) {
          final all = Store.i.data['payments']!;
          final items = _filter == 'All' ? all : all.where((p) => p['status'] == _filter).toList();
          final total = items.fold<double>(0, (s, p) => s + num0(p['amount']));
          return Scaffold(
            appBar: AppBar(title: const Text('Payments')),
            floatingActionButton: FloatingActionButton(
              onPressed: () async {
                final r = await showForm(ctx, 'Add payment', const [
                  F('client', 'Client', K.client),
                  F('package', 'Package', K.choice, ['7 days', '15 days', '30 days', '45 days', '90 days']),
                  F('amount', 'Amount (Rs)', K.number),
                  F('from', 'From', K.date),
                  F('to', 'To', K.date),
                  F('status', 'Status', K.choice, ['Paid', 'Pending']),
                ]);
                if (r != null) Store.i.add('payments', r);
              },
              child: const Icon(Icons.add),
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      for (final f in ['All', 'Paid', 'Pending'])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(f),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                        ),
                      const Spacer(),
                      Text('Total: Rs ${total.toStringAsFixed(0)}'),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text('Tap karke Paid/Pending badlo', style: TextStyle(fontSize: 12)),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('Koi payment nahi.'))
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final p = items[i];
                            final paid = p['status'] == 'Paid';
                            return Dismissible(
                              key: ObjectKey(p),
                              background: Container(color: Colors.red),
                              confirmDismiss: (_) => confirmDelete(ctx),
                              onDismissed: (_) => Store.i.remove('payments', p),
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Icon(paid ? Icons.check : Icons.hourglass_bottom),
                                ),
                                title: Text('${p['client']}  •  Rs ${p['amount']}'),
                                subtitle: Text(
                                  '${p['package'] ?? ''}  •  ${p['from'] ?? p['date'] ?? ''} → ${p['to'] ?? ''}  •  ${p['status']}',
                                ),
                                trailing: paid
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.send),
                                        tooltip: 'WhatsApp reminder',
                                        onPressed: () => shareWhatsApp(
                                          phoneOf('${p['client']}'),
                                          'Namaste ${p['client']}, aapka Rs ${p['amount']} (${p['package']}) ka payment pending hai. Kripya jald kar dein. Dhanyavaad!',
                                        ),
                                      ),
                                onTap: () {
                                  p['status'] = paid ? 'Pending' : 'Paid';
                                  Store.i.touch('payments');
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
}

// ---------- diet plans ----------
const defaultMeals = [
  ['Early Morning', '07:00 AM'],
  ['Breakfast', '09:00 AM'],
  ['Mid Morning', '11:30 AM'],
  ['Lunch', '01:30 PM'],
  ['Evening Snack', '05:00 PM'],
  ['Dinner', '08:30 PM'],
];

Map<String, dynamic> newDay() => <String, dynamic>{
      'meals': <dynamic>[
        for (final m in defaultMeals)
          <String, dynamic>{'name': m[0], 'time': m[1], 'items': <dynamic>[]},
      ],
    };

double dayCalories(Map day) {
  var t = 0.0;
  for (final m in (day['meals'] as List)) {
    for (final it in ((m as Map)['items'] as List)) {
      t += num0((it as Map)['cal']);
    }
  }
  return t;
}

String dietText(Map<String, dynamic> p) {
  final b = StringBuffer('*Diet Plan: ${p['title']}*');
  if ('${p['client'] ?? ''}'.isNotEmpty) b.write('\nClient: ${p['client']}');
  final days = (p['days'] as List?) ?? [];
  for (var i = 0; i < days.length; i++) {
    final day = days[i] as Map;
    b.write('\n\n*Day ${i + 1}*  (${dayCalories(day).toStringAsFixed(0)} kcal)');
    for (final m in (day['meals'] as List)) {
      final mm = m as Map;
      final items = mm['items'] as List;
      if (items.isEmpty) continue;
      b.write('\n\n${mm['name']} (${mm['time']})');
      for (final it in items) {
        final x = it as Map;
        final cal = '${x['cal'] ?? ''}'.isEmpty ? '' : ' - ${x['cal']} kcal';
        b.write('\n- ${x['food']} ${x['qty'] ?? ''}$cal');
      }
    }
  }
  return b.toString();
}

class ClientDiets extends StatelessWidget {
  final String client;
  const ClientDiets(this.client, {super.key});

  Future<void> _new(BuildContext ctx) async {
    final templates = Store.i.data['templates']!;
    final picked = await showModalBottomSheet<int>(
      context: ctx,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Khali plan'),
              onTap: () => Navigator.pop(c, -1),
            ),
            for (var i = 0; i < templates.length; i++)
              ListTile(
                leading: const Icon(Icons.copy_all),
                title: Text('Template: ${templates[i]['title']}'),
                onTap: () => Navigator.pop(c, i),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !ctx.mounted) return;
    final r = await showForm(
      ctx,
      'New diet plan',
      picked == -1
          ? const [F('title', 'Plan title'), F('ndays', 'Kitne din (1-14)', K.number)]
          : const [F('title', 'Plan title')],
    );
    if (r == null) return;
    Map<String, dynamic> plan;
    if (picked == -1) {
      final n = math.max(1, math.min(14, int.tryParse('${r['ndays']}') ?? 1));
      plan = <String, dynamic>{
        'days': <dynamic>[for (var i = 0; i < n; i++) newDay()],
      };
    } else {
      plan = deepCopy(templates[picked]);
    }
    plan['client'] = client;
    plan['title'] = '${r['title']}'.isEmpty ? 'Diet plan' : r['title'];
    plan['date'] = fmtDate(DateTime.now());
    await Store.i.add('dietplans', plan);
    if (ctx.mounted) {
      Navigator.push(ctx, MaterialPageRoute(builder: (_) => DietEditor(plan, 'dietplans')));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (ctx, _) {
          final items = Store.i.data['dietplans']!.where((p) => p['client'] == client).toList();
          return Scaffold(
            appBar: AppBar(title: Text('Diet plans - $client')),
            floatingActionButton: FloatingActionButton(
              onPressed: () => _new(ctx),
              child: const Icon(Icons.add),
            ),
            body: items.isEmpty
                ? const Center(child: Text('Abhi koi diet plan nahi. + dabao.'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = items[i];
                      return Dismissible(
                        key: ObjectKey(p),
                        background: Container(color: Colors.red),
                        confirmDismiss: (_) => confirmDelete(ctx),
                        onDismissed: (_) => Store.i.remove('dietplans', p),
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.restaurant_menu)),
                          title: Text('${p['title']}'),
                          subtitle: Text('${p['date'] ?? ''}  •  ${(p['days'] as List).length} din'),
                          onTap: () => Navigator.push(
                            ctx,
                            MaterialPageRoute(builder: (_) => DietEditor(p, 'dietplans')),
                          ),
                        ),
                      );
                    },
                  ),
          );
        },
      );
}

class DietEditor extends StatefulWidget {
  final Map<String, dynamic> plan;
  final String kind;
  const DietEditor(this.plan, this.kind, {super.key});
  @override
  State<DietEditor> createState() => _DietEditorState();
}

class _DietEditorState extends State<DietEditor> {
  int _d = 0;

  List get _days => widget.plan['days'] as List;

  void _save() => Store.i.touch(widget.kind);

  Future<void> _addItem(BuildContext ctx, Map meal) async {
    final r = await showForm(ctx, 'Food item add karo', const [
      F('food', 'Food item'),
      F('qty', 'Quantity (e.g. 1 bowl)'),
      F('cal', 'Calories (kcal)', K.number),
    ]);
    if (r != null && '${r['food']}'.isNotEmpty) {
      (meal['items'] as List).add(r);
      _save();
    }
  }

  Future<void> _pickTime(BuildContext ctx, Map meal) async {
    final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
    if (t != null && ctx.mounted) {
      meal['time'] = t.format(ctx);
      _save();
    }
  }

  Future<void> _addMeal(BuildContext ctx, Map day) async {
    final r = await showForm(ctx, 'Naya meal slot', const [
      F('name', 'Meal name'),
      F('time', 'Time', K.time),
    ]);
    if (r != null && '${r['name']}'.isNotEmpty) {
      (day['meals'] as List).add(<String, dynamic>{
        'name': r['name'],
        'time': r['time'],
        'items': <dynamic>[],
      });
      _save();
    }
  }

  Future<void> _saveTemplate(BuildContext ctx) async {
    final r = await showForm(
      ctx,
      'Save as template',
      const [F('title', 'Template name')],
      initial: {'title': '${widget.plan['title']}'},
    );
    if (r != null && '${r['title']}'.isNotEmpty) {
      final t = deepCopy(widget.plan);
      t.remove('client');
      t['title'] = r['title'];
      await Store.i.add('templates', t);
      if (ctx.mounted) snack(ctx, 'Template save ho gaya (Diets tab mein dikhega)');
    }
  }

  Widget _mealCard(BuildContext ctx, Map meal) {
    final items = meal['items'] as List;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${meal['name']}', style: Theme.of(ctx).textTheme.titleSmall),
                ),
                TextButton.icon(
                  onPressed: () => _pickTime(ctx, meal),
                  icon: const Icon(Icons.access_time, size: 16),
                  label: Text('${meal['time']}'),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Food add karo',
                  onPressed: () => _addItem(ctx, meal),
                ),
              ],
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text('Koi item nahi', style: TextStyle(fontSize: 12)),
              ),
            for (final it in items)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${(it as Map)['food']}'),
                subtitle: Text('${it['qty'] ?? ''}  •  ${it['cal'] ?? 0} kcal'),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    items.remove(it);
                    _save();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (ctx, _) {
          if (_d >= _days.length) _d = _days.length - 1;
          if (_d < 0) _d = 0;
          final day = _days[_d] as Map;
          final isPlan = widget.kind == 'dietplans';
          return Scaffold(
            appBar: AppBar(
              title: Text('${widget.plan['title']}'),
              actions: [
                if (isPlan)
                  IconButton(
                    icon: const Icon(Icons.share),
                    tooltip: 'WhatsApp par bhejo',
                    onPressed: () => shareWhatsApp(
                      phoneOf('${widget.plan['client']}'),
                      dietText(widget.plan),
                    ),
                  ),
                if (isPlan)
                  IconButton(
                    icon: const Icon(Icons.bookmark_add),
                    tooltip: 'Template save karo',
                    onPressed: () => _saveTemplate(ctx),
                  ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Text copy karo',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: dietText(widget.plan)));
                    if (ctx.mounted) snack(ctx, 'Copy ho gaya');
                  },
                ),
              ],
            ),
            body: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      for (var i = 0; i < _days.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text('Day ${i + 1}'),
                            selected: i == _d,
                            onSelected: (_) => setState(() => _d = i),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        tooltip: 'Naya khali din',
                        onPressed: () {
                          _days.add(newDay());
                          _d = _days.length - 1;
                          _save();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_all),
                        tooltip: 'Is din ki copy',
                        onPressed: () {
                          _days.add(deepCopy(day.cast<String, dynamic>()));
                          _d = _days.length - 1;
                          _save();
                        },
                      ),
                      if (_days.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Ye din hatao',
                          onPressed: () {
                            _days.removeAt(_d);
                            _save();
                          },
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Total calories: ${dayCalories(day).toStringAsFixed(0)} kcal',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      for (final m in (day['meals'] as List)) _mealCard(ctx, m as Map),
                      OutlinedButton.icon(
                        onPressed: () => _addMeal(ctx, day),
                        icon: const Icon(Icons.add),
                        label: const Text('Naya meal slot'),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}

// ---------- diet templates ----------
class TemplatesScreen extends StatelessWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (ctx, _) {
          final items = Store.i.data['templates']!;
          return Scaffold(
            appBar: AppBar(title: const Text('Diet templates')),
            floatingActionButton: FloatingActionButton(
              onPressed: () async {
                final r = await showForm(ctx, 'New template', const [
                  F('title', 'Template name'),
                  F('ndays', 'Kitne din (1-14)', K.number),
                ]);
                if (r == null) return;
                final n = math.max(1, math.min(14, int.tryParse('${r['ndays']}') ?? 1));
                final t = <String, dynamic>{
                  'title': '${r['title']}'.isEmpty ? 'Template' : r['title'],
                  'days': <dynamic>[for (var i = 0; i < n; i++) newDay()],
                };
                await Store.i.add('templates', t);
                if (ctx.mounted) {
                  Navigator.push(ctx, MaterialPageRoute(builder: (_) => DietEditor(t, 'templates')));
                }
              },
              child: const Icon(Icons.add),
            ),
            body: items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Abhi koi template nahi.\n+ dabake naya banao, ya kisi client ka plan banake "Template save karo" dabao.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final t = items[i];
                      return Dismissible(
                        key: ObjectKey(t),
                        background: Container(color: Colors.red),
                        confirmDismiss: (_) => confirmDelete(ctx),
                        onDismissed: (_) => Store.i.remove('templates', t),
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.restaurant_menu)),
                          title: Text('${t['title']}'),
                          subtitle: Text('${(t['days'] as List).length} din'),
                          onTap: () => Navigator.push(
                            ctx,
                            MaterialPageRoute(builder: (_) => DietEditor(t, 'templates')),
                          ),
                        ),
                      );
                    },
                  ),
          );
        },
      );
}
