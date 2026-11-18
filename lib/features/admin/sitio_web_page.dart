import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';

/// Panel de administración del sitio web público (oqua.com.ar o el dominio
/// que se registre) — el sitio en Next.js lee este contenido directo de
/// Firestore/Storage en el navegador, así que editar acá se refleja al
/// instante en la web, sin tocar código ni redesplegar nada.
class SitioWebPage extends StatefulWidget {
  const SitioWebPage({super.key});

  @override
  State<SitioWebPage> createState() => _SitioWebPageState();
}

class _SitioWebPageState extends State<SitioWebPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text('Sitio Web'),
          backgroundColor: const Color(0xFF0A3B43),
          foregroundColor: Colors.white,
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Colors.tealAccent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(text: 'Portada'),
              Tab(text: 'Secciones'),
              Tab(text: 'Galería'),
              Tab(text: 'Nuevos Socios'),
              Tab(text: 'Consultas'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _TabPortada(firestore: _firestore, onMensaje: _snack),
            _TabSecciones(firestore: _firestore, onMensaje: _snack),
            _TabGaleria(firestore: _firestore, onMensaje: _snack),
            _TabPreinscripciones(firestore: _firestore),
            _TabConsultas(firestore: _firestore),
          ],
        ),
      ),
    );
  }
}

typedef MostrarMensaje = void Function(String msg, Color color);

// ============================================================================
// PORTADA: textos del hero, datos de contacto, redes, link al portal.
// ============================================================================
class _TabPortada extends StatefulWidget {
  final FirebaseFirestore firestore;
  final MostrarMensaje onMensaje;
  const _TabPortada({required this.firestore, required this.onMensaje});

  @override
  State<_TabPortada> createState() => _TabPortadaState();
}

class _TabPortadaState extends State<_TabPortada> {
  bool _cargando = true;
  bool _guardando = false;

  final _nombreClubCtrl = TextEditingController();
  final _esloganCtrl = TextEditingController();
  final _heroTituloCtrl = TextEditingController();
  final _heroSubtituloCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _horarioCtrl = TextEditingController();
  final _instagramCtrl = TextEditingController();
  final _facebookCtrl = TextEditingController();
  final _urlPortalCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final doc = await widget.firestore
        .collection('sitio_web')
        .doc('config')
        .get();
    final d = doc.data() ?? {};
    _nombreClubCtrl.text = d['nombreClub'] ?? 'OQUA Club Deportivo';
    _esloganCtrl.text = d['eslogan'] ?? '';
    _heroTituloCtrl.text = d['heroTitulo'] ?? '';
    _heroSubtituloCtrl.text = d['heroSubtitulo'] ?? '';
    _telefonoCtrl.text = d['telefono'] ?? '';
    _whatsappCtrl.text = d['whatsapp'] ?? '';
    _emailCtrl.text = d['email'] ?? '';
    _direccionCtrl.text = d['direccion'] ?? '';
    _horarioCtrl.text = d['horarioAtencion'] ?? '';
    _instagramCtrl.text = d['instagram'] ?? '';
    _facebookCtrl.text = d['facebook'] ?? '';
    _urlPortalCtrl.text = d['urlPortalSocios'] ?? '';
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await widget.firestore.collection('sitio_web').doc('config').set({
        'nombreClub': _nombreClubCtrl.text.trim(),
        'eslogan': _esloganCtrl.text.trim(),
        'heroTitulo': _heroTituloCtrl.text.trim(),
        'heroSubtitulo': _heroSubtituloCtrl.text.trim(),
        'telefono': _telefonoCtrl.text.trim(),
        'whatsapp': _whatsappCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'direccion': _direccionCtrl.text.trim(),
        'horarioAtencion': _horarioCtrl.text.trim(),
        'instagram': _instagramCtrl.text.trim(),
        'facebook': _facebookCtrl.text.trim(),
        'urlPortalSocios': _urlPortalCtrl.text.trim(),
      }, SetOptions(merge: true));
      widget.onMensaje('✅ Portada guardada.', Colors.green);
    } catch (e) {
      widget.onMensaje('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _campo(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Portada y datos de contacto',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 16),
            _campo('Nombre del club', _nombreClubCtrl),
            _campo('Eslogan (pie de página)', _esloganCtrl),
            _campo('Título grande de la portada', _heroTituloCtrl),
            _campo('Subtítulo de la portada', _heroSubtituloCtrl, maxLines: 2),
            _campo('Teléfono', _telefonoCtrl),
            _campo('WhatsApp', _whatsappCtrl),
            _campo('Email', _emailCtrl),
            _campo('Dirección', _direccionCtrl),
            _campo('Horario de atención', _horarioCtrl),
            _campo('Instagram (link completo)', _instagramCtrl),
            _campo('Facebook (link completo)', _facebookCtrl),
            _campo(
              'Link al Portal de Socios (app web, cuando esté publicada)',
              _urlPortalCtrl,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A3B43),
                  foregroundColor: Colors.white,
                ),
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Guardar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// SECCIONES: tarjetas de Natatorio/Pádel/Gimnasio/Buffet (título, texto, foto).
// ============================================================================
class _TabSecciones extends StatefulWidget {
  final FirebaseFirestore firestore;
  final MostrarMensaje onMensaje;
  const _TabSecciones({required this.firestore, required this.onMensaje});

  @override
  State<_TabSecciones> createState() => _TabSeccionesState();
}

class _TabSeccionesState extends State<_TabSecciones> {
  static const List<String> _idsPorDefecto = [
    'natatorio',
    'padel',
    'gimnasio',
    'buffet',
  ];

  Future<void> _editarSeccion(String id, Map<String, dynamic>? data) async {
    final tituloCtrl = TextEditingController(text: data?['titulo'] ?? id);
    final descCtrl = TextEditingController(text: data?['descripcion'] ?? '');
    final detalleCtrl = TextEditingController(text: data?['detalleTexto'] ?? '');
    bool activa = data?['activa'] ?? true;
    String? imagenUrl = data?['imagenUrl'];
    Uint8List? nuevaImagenBytes;
    String? nuevaImagenNombre;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text('Sección: $id'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: tituloCtrl,
                  decoration: const InputDecoration(labelText: 'Título'),
                ),
                TextField(
                  controller: descCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Descripción corta (tarjeta de la home)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: detalleCtrl,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText:
                        'Descripción detallada (página propia de la sección, opcional)',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (nuevaImagenBytes != null)
                  Image.memory(nuevaImagenBytes!, height: 100)
                else if (imagenUrl != null && imagenUrl.isNotEmpty)
                  Image.network(imagenUrl, height: 100),
                TextButton.icon(
                  icon: const Icon(Icons.image),
                  label: const Text('Elegir foto'),
                  onPressed: () async {
                    final res = await FilePicker.pickFiles(
                      type: FileType.image,
                      withData: true,
                    );
                    if (res != null && res.files.first.bytes != null) {
                      setModalState(() {
                        nuevaImagenBytes = res.files.first.bytes;
                        nuevaImagenNombre = res.files.first.name;
                      });
                    }
                  },
                ),
                SwitchListTile(
                  title: const Text('Mostrar en el sitio'),
                  value: activa,
                  onChanged: (v) => setModalState(() => activa = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                String? urlFinal = imagenUrl;
                if (nuevaImagenBytes != null) {
                  final ext = (nuevaImagenNombre ?? 'jpg').split('.').last;
                  final ref = FirebaseStorage.instance.ref().child(
                    'sitio_web/secciones/${id}_${DateTime.now().millisecondsSinceEpoch}.$ext',
                  );
                  await ref.putData(
                    nuevaImagenBytes!,
                    SettableMetadata(contentType: 'image/$ext'),
                  );
                  urlFinal = await ref.getDownloadURL();
                }
                await widget.firestore
                    .collection('sitio_web_secciones')
                    .doc(id)
                    .set({
                      'titulo': tituloCtrl.text.trim(),
                      'descripcion': descCtrl.text.trim(),
                      'detalleTexto': detalleCtrl.text.trim(),
                      'imagenUrl': urlFinal ?? '',
                      'orden': _idsPorDefecto.contains(id)
                          ? _idsPorDefecto.indexOf(id)
                          : 99,
                      'activa': activa,
                    }, SetOptions(merge: true));
                if (ctx.mounted) Navigator.pop(ctx);
                widget.onMensaje('✅ Sección guardada.', Colors.green);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: widget.firestore.collection('sitio_web_secciones').snapshots(),
      builder: (context, snapshot) {
        final existentes = <String, Map<String, dynamic>>{
          for (var doc in snapshot.data?.docs ?? <QueryDocumentSnapshot>[])
            doc.id: doc.data() as Map<String, dynamic>,
        };
        return ListView(
          padding: const EdgeInsets.all(16),
          children: _idsPorDefecto.map((id) {
            final data = existentes[id];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(data?['titulo'] ?? id),
                subtitle: Text(
                  data?['descripcion']?.toString().isNotEmpty == true
                      ? data!['descripcion']
                      : 'Sin descripción cargada todavía',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Icon(
                  (data?['activa'] ?? true) ? Icons.visibility : Icons.visibility_off,
                  color: (data?['activa'] ?? true) ? Colors.green : Colors.grey,
                ),
                onTap: () => _editarSeccion(id, data),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ============================================================================
// GALERÍA: fotos/videos destacados en la home del sitio.
// ============================================================================
class _TabGaleria extends StatefulWidget {
  final FirebaseFirestore firestore;
  final MostrarMensaje onMensaje;
  const _TabGaleria({required this.firestore, required this.onMensaje});

  @override
  State<_TabGaleria> createState() => _TabGaleriaState();
}

class _TabGaleriaState extends State<_TabGaleria> {
  bool _subiendo = false;
  String _categoriaSeleccionada = 'General';

  static const List<String> _categorias = [
    'General',
    'Natatorio',
    'Pádel',
    'Gimnasio',
    'Buffet',
  ];

  Future<void> _subirItem(FileType tipo) async {
    final res = await FilePicker.pickFiles(type: tipo, withData: true);
    if (res == null || res.files.first.bytes == null) return;

    setState(() => _subiendo = true);
    try {
      final bytes = res.files.first.bytes!;
      final nombre = res.files.first.name;
      final ext = nombre.contains('.') ? nombre.split('.').last.toLowerCase() : 'jpg';
      final esVideo = tipo == FileType.video;
      final ref = FirebaseStorage.instance.ref().child(
        'sitio_web/galeria/${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await ref.putData(
        bytes,
        SettableMetadata(contentType: esVideo ? 'video/$ext' : 'image/$ext'),
      );
      final url = await ref.getDownloadURL();
      await widget.firestore.collection('sitio_web_galeria').add({
        'tipo': esVideo ? 'video' : 'foto',
        'categoria': _categoriaSeleccionada,
        'url': url,
        'orden': DateTime.now().millisecondsSinceEpoch,
        'destacado': true,
      });
      widget.onMensaje('✅ Subido a la galería.', Colors.green);
    } catch (e) {
      widget.onMensaje('Error al subir: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _categoriaSeleccionada,
                decoration: const InputDecoration(
                  labelText:
                      'Categoría (para que aparezca en la página de esa sección)',
                  border: OutlineInputBorder(),
                ),
                items: _categorias
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(
                  () => _categoriaSeleccionada = v ?? _categoriaSeleccionada,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_photo_alternate),
                      label: const Text('Subir foto'),
                      onPressed: _subiendo
                          ? null
                          : () => _subirItem(FileType.image),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.videocam),
                      label: const Text('Subir video'),
                      onPressed: _subiendo
                          ? null
                          : () => _subirItem(FileType.video),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_subiendo) const LinearProgressIndicator(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: widget.firestore
                .collection('sitio_web_galeria')
                .orderBy('orden', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    'Todavía no subiste nada a la galería.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: d['tipo'] == 'video'
                            ? Container(
                                color: Colors.black87,
                                child: const Center(
                                  child: Icon(
                                    Icons.play_circle,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                              )
                            : Image.network(d['url'], fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.red,
                            size: 18,
                          ),
                          onPressed: () async {
                            await docs[i].reference.delete();
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// CONSULTAS: formulario de contacto del sitio -> bandeja de entrada admin.
// ============================================================================
// ============================================================================
// NUEVOS SOCIOS: pre-inscripciones del formulario "Pre-inscribite como
// socio" del sitio — datos preliminares para agilizar el alta en recepción.
// ============================================================================
class _TabPreinscripciones extends StatelessWidget {
  final FirebaseFirestore firestore;
  const _TabPreinscripciones({required this.firestore});

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'Contactada':
        return Colors.blue;
      case 'Convertida a socio':
        return Colors.green;
      case 'Descartada':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('sitio_web_preinscripciones')
          .orderBy('fecha', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'Todavía no llegó ninguna pre-inscripción desde el sitio web.',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final estado = d['estado']?.toString() ?? 'Nueva';
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: _colorEstado(estado),
                  child: Text(
                    (d['nombre']?.toString().isNotEmpty == true)
                        ? d['nombre'][0]
                        : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text('${d['nombre'] ?? ''} ${d['apellido'] ?? ''}'),
                subtitle: Text(
                  'DNI ${d['dni'] ?? 'S/D'} · Interés: ${d['deporteInteres'] ?? 'S/D'} · $estado',
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Teléfono: ${d['telefono'] ?? 'S/D'}'),
                        Text('Email: ${d['email'] ?? 'S/D'}'),
                        Text(
                          'Fecha de nacimiento: ${d['fechaNacimiento'] ?? 'S/D'}',
                        ),
                        if ((d['comentarios'] ?? '').toString().isNotEmpty)
                          Text('Comentarios: ${d['comentarios']}'),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children:
                              [
                                    'Nueva',
                                    'Contactada',
                                    'Convertida a socio',
                                    'Descartada',
                                  ]
                                  .where((e) => e != estado)
                                  .map(
                                    (e) => OutlinedButton(
                                      onPressed: () => docs[i].reference
                                          .update({'estado': e}),
                                      child: Text(e),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _TabConsultas extends StatelessWidget {
  final FirebaseFirestore firestore;
  const _TabConsultas({required this.firestore});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('sitio_web_contactos')
          .orderBy('fecha', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'Todavía no llegó ninguna consulta desde el sitio web.',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final atendido = d['estado'] == 'Atendido';
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Icon(
                  atendido ? Icons.check_circle : Icons.mark_email_unread,
                  color: atendido ? Colors.green : Colors.orange,
                ),
                title: Text(d['nombre'] ?? ''),
                subtitle: Text(
                  '${d['email'] ?? ''} ${d['telefono'] ?? ''}\n${d['mensaje'] ?? ''}',
                ),
                isThreeLine: true,
                trailing: atendido
                    ? null
                    : TextButton(
                        onPressed: () => docs[i].reference.update({
                          'estado': 'Atendido',
                        }),
                        child: const Text('Marcar atendido'),
                      ),
              ),
            );
          },
        );
      },
    );
  }
}
