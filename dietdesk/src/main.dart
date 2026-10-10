import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'update_checker.dart';

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
  return openUrl('https://wa.me/${p.isEmpty ? '' : p}?text=${Uri.encodeComponent(text)}');
}

double num0(dynamic v) => double.tryParse('$v'.replaceAll(',', '')) ?? 0;

// ---------- storage ----------
const kinds = ['clients', 'appointments', 'payments', 'weights', 'plans'];

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

  Future<void> remove(String k, Map<String, dynamic> m) async {
    data[k]!.removeWhere((e) => identical(e, m));
    await touch(k);
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
              initialDate: DateTime.now(),
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

Future<Map<String, dynamic>?> showForm(BuildContext context, String title, List<F> fields) async {
  final names = Store.i.data['clients']!.map((c) => '${c['name']}').toList();
  if (fields.any((f) => f.kind == K.client) && names.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pehle Clients tab mein ek client add karo')),
    );
    return null;
  }
  final ctrls = <String, TextEditingController>{};
  for (final f in fields) {
    var v = '';
    if (f.kind == K.choice) v = f.options.first;
    if (f.kind == K.client) v = names.first;
    if (f.kind == K.date) v = fmtDate(DateTime.now());
    if (f.kind == K.time) v = TimeOfDay.now().format(context);
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
            subtitle: const Text('Saara data copy hoga. Kahin (WhatsApp/Notes) paste karke save kar lo.'),
            onTap: () async {
              Navigator.pop(ctx);
              await Clipboard.setData(ClipboardData(text: jsonEncode(Store.i.data)));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup copy ho gaya')));
              }
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
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(done ? 'Data restore ho gaya' : 'Backup sahi nahi hai')),
    );
  }
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
  Widget build(BuildContext context) {
    final screens = <Widget>[
      const Dashboard(),
      ListScreen(
        title: 'Clients',
        kind: 'clients',
        icon: Icons.person,
        fields: const [
          F('name', 'Name'),
          F('phone', 'Phone', K.phone),
          F('goal', 'Goal', K.choice, ['Weight loss', 'Weight gain', 'Maintenance', 'Medical diet']),
        ],
        titleKey: 'name',
        subtitle: (m) => '${m['phone'] ?? ''}  •  ${m['goal'] ?? ''}',
        onTap: (ctx, m) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => ClientProfile(m))),
      ),
      ListScreen(
        title: 'Appointments',
        kind: 'appointments',
        icon: Icons.event,
        fields: const [
          F('client', 'Client', K.client),
          F('date', 'Date', K.date),
          F('time', 'Time', K.time),
          F('type', 'Type', K.choice, ['Call', 'Video', 'Visit']),
        ],
        titleKey: 'client',
        subtitle: (m) => '${m['date'] ?? ''}  •  ${m['time'] ?? ''}  •  ${m['type'] ?? ''}',
      ),
      ListScreen(
        title: 'Payments',
        kind: 'payments',
        icon: Icons.payments,
        hint: 'Tap karke Paid/Pending badlo',
        fields: const [
          F('client', 'Client', K.client),
          F('date', 'Date', K.date),
          F('amount', 'Amount (Rs)', K.number),
          F('package', 'Package', K.choice, ['15 days', '30 days', '45 days', '90 days']),
          F('status', 'Status', K.choice, ['Paid', 'Pending']),
        ],
        titleKey: 'client',
        subtitle: (m) => '${m['date'] ?? ''}  •  Rs ${m['amount'] ?? ''}  •  ${m['package'] ?? ''}  •  ${m['status'] ?? ''}',
        onTap: (ctx, m) {
          m['status'] = m['status'] == 'Paid' ? 'Pending' : 'Paid';
          Store.i.touch('payments');
        },
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: _i, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) => setState(() => _i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Clients'),
          NavigationDestination(icon: Icon(Icons.event), label: 'Appointments'),
          NavigationDestination(icon: Icon(Icons.payments), label: 'Payments'),
        ],
      ),
    );
  }
}

// ---------- generic list screen ----------
class ListScreen extends StatelessWidget {
  final String title, kind, titleKey;
  final String? hint;
  final IconData icon;
  final List<F> fields;
  final String Function(Map<String, dynamic>) subtitle;
  final void Function(BuildContext, Map<String, dynamic>)? onTap;

  const ListScreen({
    super.key,
    required this.title,
    required this.kind,
    required this.icon,
    required this.fields,
    required this.titleKey,
    required this.subtitle,
    this.onTap,
    this.hint,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (ctx, _) {
          final items = Store.i.data[kind]!;
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            floatingActionButton: FloatingActionButton(
              onPressed: () async {
                final r = await showForm(ctx, 'Add $title', fields);
                if (r != null) Store.i.add(kind, r);
              },
              child: const Icon(Icons.add),
            ),
            body: items.isEmpty
                ? Center(child: Text('No $title yet. Tap + to add.'))
                : Column(
                    children: [
                      if (hint != null)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(hint!, style: Theme.of(ctx).textTheme.bodySmall),
                        ),
                      Expanded(
                        child: ListView.separated(
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
                                title: Text('${m[titleKey] ?? ''}'),
                                subtitle: Text(subtitle(m)),
                                onTap: onTap == null ? null : () => onTap!(ctx, m),
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
          final todays = d['appointments']!.where((a) => a['date'] == today).toList();
          final pending = d['payments']!.where((p) => p['status'] == 'Pending');
          final paid = d['payments']!.where((p) => p['status'] == 'Paid');
          final pendingAmt = pending.fold<double>(0, (s, p) => s + num0(p['amount']));
          final paidAmt = paid.fold<double>(0, (s, p) => s + num0(p['amount']));
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
                    subtitle: Text('${a['time']}  •  ${a['type']}'),
                  ),
              ],
            ),
          );
        },
      );
}

// ---------- client profile ----------
class ClientProfile extends StatelessWidget {
  final Map<String, dynamic> client;
  const ClientProfile(this.client, {super.key});

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _section(BuildContext ctx, String title, {Widget? action}) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 4),
        child: Row(
          children: [
            Expanded(child: Text(title, style: Theme.of(ctx).textTheme.titleMedium)),
            if (action != null) action,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final name = '${client['name']}';
    var phone = '${client['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length == 10) phone = '91$phone';
    return ListenableBuilder(
      listenable: Store.i,
      builder: (ctx, _) {
        final ws = Store.i.data['weights']!.where((w) => w['client'] == name).toList();
        ws.sort((a, b) => (parseDate('${a['date']}') ?? DateTime(2000))
            .compareTo(parseDate('${b['date']}') ?? DateTime(2000)));
        final vals = ws.map((w) => num0(w['weight'])).toList();
        final appts = Store.i.data['appointments']!.where((a) => a['client'] == name).toList();
        final pays = Store.i.data['payments']!.where((p) => p['client'] == name).toList();
        final plans = Store.i.data['plans']!.where((p) => p['client'] == name).toList();
        return Scaffold(
          appBar: AppBar(title: Text(name)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(ctx).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('${client['phone'] ?? ''}  •  ${client['goal'] ?? ''}'),
                      const SizedBox(height: 12),
                      Row(children: [
                        OutlinedButton.icon(
                          onPressed: phone.isEmpty ? null : () => _open('tel:+$phone'),
                          icon: const Icon(Icons.call),
                          label: const Text('Call'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: phone.isEmpty ? null : () => _open('https://wa.me/$phone'),
                          icon: const Icon(Icons.chat),
                          label: const Text('WhatsApp'),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
              _section(
                ctx,
                'Weight progress',
                action: TextButton.icon(
                  onPressed: () async {
                    final r = await showForm(ctx, 'Add weight', const [
                      F('weight', 'Weight (kg)', K.number),
                      F('date', 'Date', K.date),
                    ]);
                    if (r != null) {
                      r['client'] = name;
                      Store.i.add('weights', r);
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ),
              if (vals.length >= 2) ...[
                Text('${vals.first} kg  →  ${vals.last} kg   (${vals.last - vals.first > 0 ? '+' : ''}${(vals.last - vals.first).toStringAsFixed(1)} kg)'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 140,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: LinePainter(vals, Theme.of(ctx).colorScheme.primary),
                  ),
                ),
              ] else
                const Text('Progress graph ke liye kam se kam 2 weight entries add karo.'),
              for (final w in ws.reversed)
                ListTile(
                  dense: true,
                  title: Text('${w['weight']} kg'),
                  subtitle: Text('${w['date']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirmDelete(ctx)) Store.i.remove('weights', w);
                    },
                  ),
                ),
              _section(
                ctx,
                'Diet plans',
                action: TextButton.icon(
                  onPressed: () async {
                    final r = await showForm(ctx, 'New diet plan', const [
                      F('title', 'Plan title (e.g. Week 1)'),
                      F('date', 'Date', K.date),
                      F('breakfast', 'Breakfast', K.long),
                      F('midmorning', 'Mid-morning', K.long),
                      F('lunch', 'Lunch', K.long),
                      F('snack', 'Evening snack', K.long),
                      F('dinner', 'Dinner', K.long),
                      F('notes', 'Notes / instructions', K.long),
                    ]);
                    if (r != null) {
                      r['client'] = name;
                      Store.i.add('plans', r);
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                ),
              ),
              if (plans.isEmpty) const Text('Abhi koi diet plan nahi.'),
              for (final pl in plans)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.restaurant_menu),
                  title: Text('${pl['title']}'),
                  subtitle: Text('${pl['date']}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    ctx,
                    MaterialPageRoute(builder: (_) => PlanView(pl, '${client['phone'] ?? ''}')),
                  ),
                ),
              _section(ctx, 'Appointments'),
              if (appts.isEmpty) const Text('Koi appointment nahi.'),
              for (final a in appts)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.event),
                  title: Text('${a['date']}  •  ${a['time']}'),
                  subtitle: Text('${a['type']}'),
                ),
              _section(ctx, 'Payments'),
              if (pays.isEmpty) const Text('Koi payment nahi.'),
              for (final p in pays)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.payments),
                  title: Text('Rs ${p['amount']}  •  ${p['package']}'),
                  subtitle: Text('${p['date']}  •  ${p['status']}'),
                  trailing: p['status'] == 'Pending'
                      ? IconButton(
                          icon: const Icon(Icons.send),
                          tooltip: 'WhatsApp reminder',
                          onPressed: () => shareWhatsApp(
                            '${client['phone'] ?? ''}',
                            'Namaste $name, aapka Rs ${p['amount']} (${p['package']}) ka payment pending hai. Kripya jald kar dein. Dhanyavaad!',
                          ),
                        )
                      : null,
                ),
            ],
          ),
        );
      },
    );
  }
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

// ---------- diet plan view ----------
String planText(Map<String, dynamic> p) {
  final b = StringBuffer('*Diet Plan - ${p['client']}*\n${p['title']} (${p['date']})\n');
  void line(String label, String key) {
    final v = '${p[key] ?? ''}'.trim();
    if (v.isNotEmpty) b.write('\n*$label:* $v');
  }

  line('Breakfast', 'breakfast');
  line('Mid-morning', 'midmorning');
  line('Lunch', 'lunch');
  line('Evening snack', 'snack');
  line('Dinner', 'dinner');
  line('Notes', 'notes');
  return b.toString();
}

class PlanView extends StatelessWidget {
  final Map<String, dynamic> plan;
  final String phone;
  const PlanView(this.plan, this.phone, {super.key});

  @override
  Widget build(BuildContext context) {
    final text = planText(plan);
    return Scaffold(
      appBar: AppBar(title: Text('${plan['title']}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SelectableText(text.replaceAll('*', ''), style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => shareWhatsApp(phone, text),
            icon: const Icon(Icons.chat),
            label: const Text('WhatsApp par bhejo'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copy ho gaya')));
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              if (await confirmDelete(context)) {
                await Store.i.remove('plans', plan);
                if (context.mounted) Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete plan'),
          ),
        ],
      ),
    );
  }
}
