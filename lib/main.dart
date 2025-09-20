import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;

/* ================================================================
                           MAIN
================================================================*/
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(MemoryAdapter());
  Hive.registerAdapter(MediaAdapter());
  Hive.registerAdapter(TagAdapter());
  Hive.registerAdapter(SettingsAdapter());
  await Hive.openBox<Memory>('memories');
  await Hive.openBox<Tag>('tags');
  await Hive.openBox<Settings>('settings');
  // ------------------ reminders ------------------
  AwesomeNotifications().initialize(null, [
    NotificationChannel(
      channelKey: 'memory_channel',
      channelName: 'Memory reminders',
      channelDescription: 'Anniversary reminders',
      defaultColor: Colors.indigo,
      importance: NotificationImportance.High,
    ),
  ]);
  runApp(const MyApp());
}

/* ================================================================
                       MODELS / ADAPTERS
================================================================*/
@HiveType(typeId: 0)
class Memory {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;
  @HiveField(2)
  final DateTime date;
  @HiveField(3)
  final List<Media> media; // photos + videos
  @HiveField(4)
  final String notes;
  @HiveField(5)
  final List<String> tagIds;
  @HiveField(6)
  final bool isFav;
  @HiveField(7)
  final String? audioPath;
  @HiveField(8)
  final LatLng? location;
  @HiveField(9)
  final String? mood; // emoji

  Memory({
    required this.id,
    required this.title,
    required this.date,
    this.media = const [],
    this.notes = '',
    this.tagIds = const [],
    this.isFav = false,
    this.audioPath,
    this.location,
    this.mood,
  });

  bool get hasPhoto => media.any((m) => m.type == MediaType.image);
  bool get hasVideo => media.any((m) => m.type == MediaType.video);

  // Helper method for JSON conversion
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'date': date.toIso8601String(),
      'media': media.map((m) => m.toJson()).toList(),
      'notes': notes,
      'tagIds': tagIds,
      'isFav': isFav,
      'audioPath': audioPath,
      'location': location != null
          ? {'lat': location!.latitude, 'lng': location!.longitude}
          : null,
      'mood': mood,
    };
  }

  // Helper method to create Memory from JSON
  factory Memory.fromJson(Map<String, dynamic> json) {
    return Memory(
      id: json['id'],
      title: json['title'],
      date: DateTime.parse(json['date']),
      media: (json['media'] as List).map((m) => Media.fromJson(m)).toList(),
      notes: json['notes'],
      tagIds: List<String>.from(json['tagIds']),
      isFav: json['isFav'],
      audioPath: json['audioPath'],
      location: json['location'] != null
          ? LatLng(json['location']['lat'], json['location']['lng'])
          : null,
      mood: json['mood'],
    );
  }
}

@HiveType(typeId: 1)
class Media {
  @HiveField(0)
  final String path;
  @HiveField(1)
  final MediaType type;

  Media(this.path, this.type);

  Map<String, dynamic> toJson() {
    return {'path': path, 'type': type.index};
  }

  factory Media.fromJson(Map<String, dynamic> json) {
    return Media(json['path'], MediaType.values[json['type']]);
  }
}

enum MediaType { image, video }

@HiveType(typeId: 2)
class Tag {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String name;
  @HiveField(2)
  final Color color;

  Tag(this.id, this.name, this.color);

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'color': color.value};
  }

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(json['id'], json['name'], Color(json['color']));
  }
}

@HiveType(typeId: 3)
class Settings {
  @HiveField(0)
  bool biometricLock;
  @HiveField(1)
  String themeMode; // system, light, dark
  @HiveField(2)
  int accentColor; // color value
  @HiveField(3)
  bool hiddenUnlocked; // transient

  Settings({
    this.biometricLock = false,
    this.themeMode = 'system',
    this.accentColor = 0, // Initialize to 0, will be set in factory constructor
    this.hiddenUnlocked = false,
  });

  // Factory constructor to properly initialize with Colors.indigo.value
  factory Settings.initial() {
    return Settings(
      biometricLock: false,
      themeMode: 'system',
      accentColor: Colors.indigo.value,
      hiddenUnlocked: false,
    );
  }

  Settings copyWith({
    bool? biometricLock,
    String? themeMode,
    int? accentColor,
    bool? hiddenUnlocked,
  }) {
    return Settings(
      biometricLock: biometricLock ?? this.biometricLock,
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      hiddenUnlocked: hiddenUnlocked ?? this.hiddenUnlocked,
    );
  }
}

/* ---------- adapters ---------- */
class MemoryAdapter extends TypeAdapter<Memory> {
  @override
  final int typeId = 0;

  @override
  Memory read(BinaryReader reader) {
    return Memory(
      id: reader.read(),
      title: reader.read(),
      date: DateTime.fromMillisecondsSinceEpoch(reader.read()),
      media: reader.read().cast<Media>(),
      notes: reader.read(),
      tagIds: reader.read().cast<String>(),
      isFav: reader.read(),
      audioPath: reader.read(),
      location: reader.read(),
      mood: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, Memory obj) {
    writer.write(obj.id);
    writer.write(obj.title);
    writer.write(obj.date.millisecondsSinceEpoch);
    writer.write(obj.media);
    writer.write(obj.notes);
    writer.write(obj.tagIds);
    writer.write(obj.isFav);
    writer.write(obj.audioPath);
    writer.write(obj.location);
    writer.write(obj.mood);
  }
}

class MediaAdapter extends TypeAdapter<Media> {
  @override
  final int typeId = 1;

  @override
  Media read(BinaryReader reader) =>
      Media(reader.read(), MediaType.values[reader.read()]);

  @override
  void write(BinaryWriter writer, Media obj) {
    writer.write(obj.path);
    writer.write(obj.type.index);
  }
}

class TagAdapter extends TypeAdapter<Tag> {
  @override
  final int typeId = 2;

  @override
  Tag read(BinaryReader reader) =>
      Tag(reader.read(), reader.read(), Color(reader.read()));

  @override
  void write(BinaryWriter writer, Tag obj) {
    writer.write(obj.id);
    writer.write(obj.name);
    writer.write(obj.color.value);
  }
}

class SettingsAdapter extends TypeAdapter<Settings> {
  @override
  final int typeId = 3;

  @override
  Settings read(BinaryReader reader) {
    return Settings(
      biometricLock: reader.read(),
      themeMode: reader.read(),
      accentColor: reader.read(),
      hiddenUnlocked: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, Settings obj) {
    writer.write(obj.biometricLock);
    writer.write(obj.themeMode);
    writer.write(obj.accentColor);
    writer.write(obj.hiddenUnlocked);
  }
}

/* ================================================================
                           APP
================================================================*/
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<Settings>>(
      valueListenable: Hive.box<Settings>('settings').listenable(),
      builder: (_, box, __) {
        // Get settings or create with initial values
        final s = box.get('settings') ?? Settings.initial();
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Memory Dates',
          themeMode: s.themeMode == 'system'
              ? ThemeMode.system
              : (s.themeMode == 'dark' ? ThemeMode.dark : ThemeMode.light),
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: Color(s.accentColor),
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: Color(s.accentColor),
            brightness: Brightness.dark,
          ),
          home: const AuthGate(),
        );
      },
    );
  }
}

/* ================================================================
                        AUTH GATE (BIO LOCK)
================================================================*/
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final s =
        Hive.box<Settings>('settings').get('settings') ?? Settings.initial();
    if (!s.biometricLock) {
      _goHome();
      return;
    }
    final bool can = await _localAuth.canCheckBiometrics;
    if (!can) {
      _goHome();
      return;
    }
    try {
      final bool ok = await _localAuth.authenticate(
        localizedReason: 'Unlock your memories',
        options: const AuthenticationOptions(biometricOnly: true),
      );
      if (ok) _goHome();
    } catch (_) {
      _goHome();
    }
  }

  void _goHome() => Navigator.pushReplacement(
    context,
    MaterialPageRoute(builder: (_) => const HomePage()),
  );

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/* ================================================================
                         HOME (TABS)
================================================================*/
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late TabController _tabController;
  int _sort = 0; // 0 newest, 1 oldest, 2 A-Z
  String _search = '';
  DateTimeRange? _range;
  bool _photoOnly = false;
  String? _tagFilter;
  final bool _showHidden = false;
  final int _viewMode = 0; // 0 list, 1 grid, 2 stats

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  /* ------------------ helpers ------------------ */
  Iterable<Memory> _filter(Iterable<Memory> list) {
    Iterable<Memory> out = list;
    if (_search.isNotEmpty) {
      out = out.where(
        (m) =>
            m.title.toLowerCase().contains(_search.toLowerCase()) ||
            m.notes.toLowerCase().contains(_search.toLowerCase()),
      );
    }
    if (_range != null) {
      out = out.where(
        (m) => m.date.isAfter(_range!.start) && m.date.isBefore(_range!.end),
      );
    }
    if (_photoOnly) {
      out = out.where((m) => m.hasPhoto);
    }
    if (_tagFilter != null) {
      out = out.where((m) => m.tagIds.contains(_tagFilter));
    }
    if (!_showHidden) {
      out = out.where((m) => !m.tagIds.contains('hidden'));
    }
    return out;
  }

  List<Memory> _sorted(Iterable<Memory> list) {
    final l = _filter(list).toList();
    if (_sort == 0) {
      l.sort((a, b) => b.date.compareTo(a.date));
    }
    if (_sort == 1) {
      l.sort((a, b) => a.date.compareTo(b.date));
    }
    if (_sort == 2) {
      l.sort((a, b) => a.title.compareTo(b.title));
    }
    return l;
  }

  /* ------------------ build ------------------ */
  @override
  Widget build(BuildContext context) {
    final box = Hive.box<Memory>('memories');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memories'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'All'),
            Tab(icon: Icon(Icons.star), text: 'Favs'),
            Tab(icon: Icon(Icons.calendar_month), text: 'Timeline'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.sort), onPressed: _sortSheet),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _filterSheet,
          ),
          IconButton(icon: const Icon(Icons.settings), onPressed: _settings),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddEditPage()),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SearchBar(
              hintText: 'Search title or notes',
              onChanged: (v) => setState(() => _search = v),
              leading: const Icon(Icons.search),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<Box<Memory>>(
              valueListenable: box.listenable(),
              builder: (_, box, __) {
                final all = _sorted(box.values);
                final fav = _sorted(box.values.where((m) => m.isFav));
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _view(all),
                    _view(fav),
                    _timeline(_sorted(box.values)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /* ------------------ view switcher ------------------ */
  Widget _view(List<Memory> list) {
    if (_viewMode == 2) {
      return _StatsWidget(memories: list);
    }
    if (_viewMode == 1) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: .8,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) => _MemoryCard(memory: list[i]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (_, i) => _MemoryCard(memory: list[i]),
    );
  }

  Widget _timeline(List<Memory> list) {
    final buckets = <int, List<Memory>>{};
    for (final m in list) {
      final y = m.date.year;
      buckets.putIfAbsent(y, () => []).add(m);
    }
    final years = buckets.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: years.length,
      itemBuilder: (_, i) {
        final y = years[i];
        final items = buckets[y]!..sort((a, b) => b.date.compareTo(a.date));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$y',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...items.map((m) => _MemoryCard(memory: m)),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  /* ------------------ sheets ------------------ */
  void _sortSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<int>(
            value: 0,
            groupValue: _sort,
            onChanged: (v) => setState(() => _sort = v!),
            title: const Text('Newest first'),
          ),
          RadioListTile<int>(
            value: 1,
            groupValue: _sort,
            onChanged: (v) => setState(() => _sort = v!),
            title: const Text('Oldest first'),
          ),
          RadioListTile<int>(
            value: 2,
            groupValue: _sort,
            onChanged: (v) => setState(() => _sort = v!),
            title: const Text('A-Z'),
          ),
        ],
      ),
    );
  }

  void _filterSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState2) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('With photo only'),
                  value: _photoOnly,
                  onChanged: (v) => setState2(() => _photoOnly = v),
                ),
                ListTile(
                  title: const Text('Pick date range'),
                  leading: const Icon(Icons.date_range),
                  onTap: () async {
                    final r = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (r != null) {
                      setState(() => _range = r);
                    }
                  },
                ),
                const SizedBox(height: 8),
                const Text('Filter by tag'),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: _tagFilter == null,
                      onSelected: (_) => setState2(() => _tagFilter = null),
                    ),
                    ...Hive.box<Tag>('tags').values.map(
                      (t) => FilterChip(
                        label: Text(t.name),
                        selected: _tagFilter == t.id,
                        onSelected: (_) => setState2(() => _tagFilter = t.id),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() => setState(() {}));
  }

  void _settings() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => _SettingsPage()),
  );
}

/* ================================================================
                      MEMORY CARD WIDGET
================================================================*/
class _MemoryCard extends StatelessWidget {
  final Memory memory;

  const _MemoryCard({required this.memory});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(memory.title),
        subtitle: Text(timeago.format(memory.date)),
        trailing: memory.isFav
            ? const Icon(Icons.star, color: Colors.amber)
            : null,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AddEditPage(memory: memory)),
        ),
      ),
    );
  }
}

/* ================================================================
                      STATS WIDGET
================================================================*/
class _StatsWidget extends StatelessWidget {
  final List<Memory> memories;

  const _StatsWidget({required this.memories});

  @override
  Widget build(BuildContext context) {
    final yearCount = <int, int>{};
    final monthCount = <int, int>{};
    for (final m in memories) {
      yearCount.update(m.date.year, (v) => v + 1, ifAbsent: () => 1);
      monthCount.update(m.date.month, (v) => v + 1, ifAbsent: () => 1);
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total memories: ${memories.length}',
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 16),
          const Text(
            'Per year',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          ...yearCount.entries.map((e) => Text('${e.key}: ${e.value}')),
          const SizedBox(height: 16),
          const Text(
            'Per month',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          ...monthCount.entries.map((e) => Text('Month ${e.key}: ${e.value}')),
        ],
      ),
    );
  }
}

/* ================================================================
                      SETTINGS PAGE
================================================================*/
class _SettingsPage extends StatelessWidget {
  const _SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s =
        Hive.box<Settings>('settings').get('settings') ?? Settings.initial();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Appearance',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          ListTile(
            title: const Text('Accent color'),
            trailing: CircleAvatar(backgroundColor: Color(s.accentColor)),
            onTap: () async {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Pick color'),
                  content: SingleChildScrollView(
                    child: Wrap(
                      children: Colors.primaries.map((color) {
                        return GestureDetector(
                          onTap: () {
                            Hive.box<Settings>('settings').put(
                              'settings',
                              s.copyWith(accentColor: color.value),
                            );
                            Navigator.pop(context);
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            color: color,
                            margin: const EdgeInsets.all(4),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              );
            },
          ),
          const Divider(),
          const Text(
            'Privacy',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SwitchListTile(
            title: const Text('Biometric lock'),
            value: s.biometricLock,
            onChanged: (v) => Hive.box<Settings>(
              'settings',
            ).put('settings', s.copyWith(biometricLock: v)),
          ),
          const Divider(),
          const Text(
            'Backup',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          ListTile(
            title: const Text('Export JSON'),
            leading: const Icon(Icons.save_alt),
            onTap: () async {
              final dir = await getApplicationDocumentsDirectory();
              final file = File(
                '${dir.path}/memories_${DateTime.now().millisecondsSinceEpoch}.json',
              );
              final data = Hive.box<Memory>(
                'memories',
              ).values.map((m) => m.toJson()).toList();
              await file.writeAsString(jsonEncode(data));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Saved to ${file.path}')),
                );
              }
            },
          ),
          ListTile(
            title: const Text('Import JSON'),
            leading: const Icon(Icons.backup),
            onTap: () async {
              // Simple implementation without file picker
              final dir = await getApplicationDocumentsDirectory();
              final files = dir
                  .listSync()
                  .where((f) => f.path.endsWith('.json'))
                  .toList();
              if (files.isNotEmpty) {
                final file = File(files.first.path);
                final content = await file.readAsString();
                final list = jsonDecode(content) as List;
                for (final j in list) {
                  final m = Memory.fromJson(j);
                  Hive.box<Memory>('memories').put(m.id, m);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Imported')));
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

/* ================================================================
                      ADD / EDIT PAGE
================================================================*/
class AddEditPage extends StatefulWidget {
  final Memory? memory;

  const AddEditPage({super.key, this.memory});

  @override
  State<AddEditPage> createState() => _AddEditPageState();
}

class _AddEditPageState extends State<AddEditPage> {
  late final _title = TextEditingController(text: widget.memory?.title ?? '');
  late final _notes = TextEditingController(text: widget.memory?.notes ?? '');
  late DateTime _date = widget.memory?.date ?? DateTime.now();
  final List<Media> _media = [];
  String? _audioPath;
  final List<String> _tagIds = [];
  LatLng? _location;
  String? _mood;
  bool _isFav = false;

  // Replace Record with FlutterSoundRecorder
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecording = false;
  String? _currentRecordingPath; // Store the current recording path

  @override
  void initState() {
    super.initState();
    _initRecorder();

    if (widget.memory != null) {
      _media.addAll(widget.memory!.media);
      _audioPath = widget.memory!.audioPath;
      _tagIds.addAll(widget.memory!.tagIds);
      _location = widget.memory!.location;
      _mood = widget.memory!.mood;
      _isFav = widget.memory!.isFav;
    }
  }

  // Initialize the recorder
  Future<void> _initRecorder() async {
    try {
      await _recorder.openRecorder();
      if (!mounted) return;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing recorder: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  /* ------------------ media ------------------ */
  Future<void> _pickMedia(bool video) async {
    final picker = ImagePicker();
    final xfiles = video
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickMultiImage();
    if (xfiles == null) return;
    final dir = await getApplicationDocumentsDirectory();
    if (video && xfiles is XFile) {
      final name =
          '${DateTime.now().millisecondsSinceEpoch}${p.extension(xfiles.path)}';
      final saved = await File(xfiles.path).copy('${dir.path}/$name');
      _media.add(Media(saved.path, MediaType.video));
    } else if (xfiles is List<XFile>) {
      for (final x in xfiles) {
        final name =
            '${DateTime.now().millisecondsSinceEpoch}${p.extension(x.path)}';
        final saved = await File(x.path).copy('${dir.path}/$name');
        _media.add(Media(saved.path, MediaType.image));
      }
    }
    setState(() {});
  }

  /* ------------------ audio ------------------ */
  Future<void> _recordAudio() async {
    try {
      if (_isRecording) {
        // Stop recording
        await _recorder.stopRecorder();
        setState(() {
          _isRecording = false;
          _audioPath = _currentRecordingPath; // Use the stored path
          _currentRecordingPath = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Recording stopped')));
        }
      } else {
        // Start recording
        final dir = await getApplicationDocumentsDirectory();
        final name = '${DateTime.now().millisecondsSinceEpoch}.aac';
        final path = p.join(dir.path, name);

        // Store the path for later use
        _currentRecordingPath = path;

        await _recorder.startRecorder(toFile: path);
        setState(() => _isRecording = true);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording… tap again to stop')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  /* ------------------ location ------------------ */
  Future<void> _pickLocation() async {
    // Simple location picker implementation
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Location'),
        content: const Text('Location picker would go here'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() => _location = const LatLng(0, 0));
              Navigator.pop(context);
            },
            child: const Text('Set Location'),
          ),
        ],
      ),
    );
  }

  /* ------------------ save ------------------ */
  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    final box = Hive.box<Memory>('memories');
    final id = widget.memory?.id ?? DateTime.now().toIso8601String();
    final m = Memory(
      id: id,
      title: _title.text.trim(),
      date: _date,
      media: _media,
      notes: _notes.text.trim(),
      tagIds: _tagIds,
      isFav: _isFav,
      audioPath: _audioPath,
      location: _location,
      mood: _mood,
    );
    box.put(id, m);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  /* ------------------ build ------------------ */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.memory == null ? 'Add memory' : 'Edit memory'),
        actions: [IconButton(onPressed: _save, icon: const Icon(Icons.check))],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: Text('Date: ${_date.toString().substring(0, 10)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() => _date = picked);
                }
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                IconButton(
                  onPressed: () => _pickMedia(false),
                  icon: const Icon(Icons.photo),
                ),
                IconButton(
                  onPressed: () => _pickMedia(true),
                  icon: const Icon(Icons.videocam),
                ),
                IconButton(
                  onPressed: _recordAudio,
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                ),
                IconButton(
                  onPressed: _pickLocation,
                  icon: const Icon(Icons.location_on),
                ),
              ],
            ),
            if (_media.isNotEmpty)
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _media.length,
                  itemBuilder: (_, i) {
                    final m = _media[i];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: m.type == MediaType.image
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(m.path),
                                width: 100,
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Icon(Icons.videocam, size: 100),
                    );
                  },
                ),
              ),
            if (_audioPath != null) const Text('🎙️ Voice attached'),
            const SizedBox(height: 16),
            const Text('Mood'),
            Wrap(
              spacing: 8,
              children: ['😊', '😢', '😡', '😎', '🤔'].map((e) {
                return ChoiceChip(
                  label: Text(e, style: const TextStyle(fontSize: 24)),
                  selected: _mood == e,
                  onSelected: (_) => setState(() => _mood = e),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Tags'),
            Wrap(
              spacing: 8,
              children: [
                ...Hive.box<Tag>('tags').values.map(
                  (t) => FilterChip(
                    label: Text(t.name),
                    selected: _tagIds.contains(t.id),
                    onSelected: (sel) => setState(
                      () => sel ? _tagIds.add(t.id) : _tagIds.remove(t.id),
                    ),
                  ),
                ),
                ActionChip(
                  label: const Icon(Icons.add),
                  onPressed: () async {
                    final name = await _inputDialog('New tag');
                    if (name == null || name.isEmpty) return;
                    final color = Colors
                        .primaries[Random().nextInt(Colors.primaries.length)];
                    Hive.box<Tag>('tags').put(name, Tag(name, name, color));
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Favorite'),
              value: _isFav,
              onChanged: (v) => setState(() => _isFav = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
              ),
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _inputDialog(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
