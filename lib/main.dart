import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glass/glass.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:timeago/timeago.dart' as timeago;

/* ---------- model ---------- */
@HiveType(typeId: 0)
class Memory {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;
  @HiveField(2)
  final DateTime date;
  @HiveField(3)
  final String? imagePath;
  @HiveField(4)
  final String notes;

  Memory({
    required this.id,
    required this.title,
    required this.date,
    this.imagePath,
    this.notes = '',
  });
}

/* ---------- Hive adapter ---------- */
class MemoryAdapter extends TypeAdapter<Memory> {
  @override
  final int typeId = 0;

  @override
  Memory read(BinaryReader reader) {
    return Memory(
      id: reader.read(),
      title: reader.read(),
      date: DateTime.fromMillisecondsSinceEpoch(reader.read()),
      imagePath: reader.read(),
      notes: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, Memory obj) {
    writer.write(obj.id);
    writer.write(obj.title);
    writer.write(obj.date.millisecondsSinceEpoch);
    writer.write(obj.imagePath);
    writer.write(obj.notes);
  }
}

/* ---------- main ---------- */
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(MemoryAdapter());
  await Hive.openBox<Memory>('memories');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Memory Dates',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}

/* ---------- home ---------- */
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<Memory>('memories');
    return Scaffold(
      appBar: AppBar(title: const Text('Memories'), centerTitle: true),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add memory'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddEditPage()),
        ),
      ),
      body: ValueListenableBuilder<Box<Memory>>(
        valueListenable: box.listenable(),
        builder: (context, box, _) {
          final list = box.values.toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          if (list.isEmpty) {
            return const Center(child: Text('No memories yet – add one!'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final m = list[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Hero(
                  tag: m.id,
                  child: MemoryCard(memory: m),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/* ---------- reusable glass card ---------- */
class MemoryCard extends StatelessWidget {
  final Memory memory;
  const MemoryCard({super.key, required this.memory});

  @override
  Widget build(BuildContext context) {
    final subtitle =
        '${timeago.format(memory.date, locale: 'en_short')} • ${memory.date.year}';
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DetailPage(memory: memory)),
      ),
      child:
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              image: memory.imagePath != null
                  ? DecorationImage(
                      image: FileImage(File(memory.imagePath!)),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: .4),
                        BlendMode.darken,
                      ),
                    )
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memory.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ).asGlass(
            tintColor: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: .4),
            clipBorderRadius: BorderRadius.circular(24),
          ),
    );
  }
}

/* ---------- detail / edit / delete ---------- */
class DetailPage extends StatelessWidget {
  final Memory memory;
  const DetailPage({super.key, required this.memory});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => AddEditPage(memory: memory)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              Hive.box<Memory>('memories').delete(memory.id);
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Hero(
        tag: memory.id,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: memory.imagePath != null
              ? BoxDecoration(
                  image: DecorationImage(
                    image: FileImage(File(memory.imagePath!)),
                    fit: BoxFit.cover,
                  ),
                )
              : null,
          child: Container(
            padding: const EdgeInsets.all(32).copyWith(top: 100),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  memory.title,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  memory.date.toString().substring(0, 10),
                  style: const TextStyle(fontSize: 18, color: Colors.white70),
                ),
                if (memory.notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    memory.notes,
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------- add / edit page ---------- */
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
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    _imagePath = widget.memory?.imagePath;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final saved = await File(xfile.path).copy('${dir.path}/$name');
    setState(() => _imagePath = saved.path);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    final box = Hive.box<Memory>('memories');
    final id = widget.memory?.id ?? DateTime.now().toIso8601String();
    final m = Memory(
      id: id,
      title: _title.text.trim(),
      date: _date,
      imagePath: _imagePath,
      notes: _notes.text.trim(),
    );
    box.put(id, m);
    if (mounted) Navigator.pop(context);
  }

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
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Date: ${_date.toString().substring(0, 10)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Photo (optional)'),
              trailing: _imagePath == null
                  ? const Icon(Icons.add_a_photo)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_imagePath!),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    ),
              onTap: _pickImage,
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
}
