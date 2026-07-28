import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ConfiguracionPage extends StatefulWidget {
  const ConfiguracionPage({super.key});

  @override
  State<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends State<ConfiguracionPage> {
  final TextEditingController _itemController = TextEditingController();

  // Controladores exclusivos para el ABM de Horarios
  final TextEditingController _idHorarioController = TextEditingController();
  final TextEditingController _inicioHorarioController =
      TextEditingController();
  final TextEditingController _finHorarioController = TextEditingController();

  // --- MÉTODOS PARA DEPORTES Y FRECUENCIAS ---
  Future<void> _agregarItemLista(String documento, String valor) async {
    if (valor.isEmpty) return;
    try {
      final docRef = FirebaseFirestore.instance
          .collection('configuracion')
          .doc(documento);

      await docRef.set({
        'lista': FieldValue.arrayUnion([valor]),
      }, SetOptions(merge: true));

      _itemController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _borrarItemLista(String documento, String valor) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('configuracion')
          .doc(documento);

      await docRef.set({
        'lista': FieldValue.arrayRemove([valor]),
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al borrar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _modificarItemLista(
    String documento,
    String valorViejo,
    String valorNuevo,
  ) async {
    if (valorNuevo.isEmpty || valorViejo == valorNuevo) return;
    try {
      final docRef = FirebaseFirestore.instance
          .collection('configuracion')
          .doc(documento);

      // Modificación secuencial segura sin Batch para JS Web
      await docRef.set({
        'lista': FieldValue.arrayRemove([valorViejo]),
      }, SetOptions(merge: true));

      await docRef.set({
        'lista': FieldValue.arrayUnion([valorNuevo]),
      }, SetOptions(merge: true));

      _itemController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al modificar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- MÉTODOS PARA BLOQUES HORARIOS (MAPAS) ---
  Future<void> _agregarBloqueHorario() async {
    final id = _idHorarioController.text.trim();
    final inicio = _inicioHorarioController.text.trim();
    final fin = _finHorarioController.text.trim();

    if (id.isEmpty || inicio.isEmpty || fin.isEmpty) return;

    try {
      final docRef = FirebaseFirestore.instance
          .collection('configuracion')
          .doc('horarios');

      Map<String, dynamic> nuevoBloque = {
        'id': id,
        'horaInicio': inicio,
        'horaFin': fin,
        'nombre': '',
      };

      await docRef.set({
        'bloques': FieldValue.arrayUnion([nuevoBloque]),
      }, SetOptions(merge: true));

      _idHorarioController.clear();
      _inicioHorarioController.clear();
      _finHorarioController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al crear bloque: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _modificarBloqueHorario(Map<String, dynamic> bloqueViejo) async {
    final id = _idHorarioController.text.trim();
    final inicio = _inicioHorarioController.text.trim();
    final fin = _finHorarioController.text.trim();

    if (inicio.isEmpty || fin.isEmpty) return;

    try {
      final docRef = FirebaseFirestore.instance
          .collection('configuracion')
          .doc('horarios');

      Map<String, dynamic> bloqueModificado = {
        'id': id,
        'horaInicio': inicio,
        'horaFin': fin,
        'nombre': bloqueViejo['nombre'] ?? '',
      };

      await docRef.set({
        'bloques': FieldValue.arrayRemove([bloqueViejo]),
      }, SetOptions(merge: true));

      await docRef.set({
        'bloques': FieldValue.arrayUnion([bloqueModificado]),
      }, SetOptions(merge: true));

      _idHorarioController.clear();
      _inicioHorarioController.clear();
      _finHorarioController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al modificar bloque: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _borrarBloqueHorario(Map<String, dynamic> bloque) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('configuracion')
          .doc('horarios');

      await docRef.set({
        'bloques': FieldValue.arrayRemove([bloque]),
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al borrar bloque: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- FORMULARIOS MODALES (DIALOGS) ---
  void _dialogoConstante(
    String titulo,
    String documento, {
    String? valorExistente,
  }) {
    final esEdicion = valorExistente != null;
    _itemController.text = valorExistente ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(esEdicion ? 'Modificar en $titulo' : 'Agregar a $titulo'),
        content: TextField(
          controller: _itemController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Ej: Pase Libre / Acuagym',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _itemController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (esEdicion) {
                _modificarItemLista(
                  documento,
                  valorExistente,
                  _itemController.text.trim(),
                );
              } else {
                _agregarItemLista(documento, _itemController.text.trim());
              }
              Navigator.pop(context);
            },
            child: Text(esEdicion ? 'Actualizar' : 'Guardar'),
          ),
        ],
      ),
    );
  }

  void _dialogoHorario({Map<String, dynamic>? bloqueExistente}) {
    final esEdicion = bloqueExistente != null;

    if (esEdicion) {
      _idHorarioController.text = bloqueExistente['id'] ?? '';
      _inicioHorarioController.text = bloqueExistente['horaInicio'] ?? '';
      _finHorarioController.text = bloqueExistente['horaFin'] ?? '';
    } else {
      _idHorarioController.clear();
      _inicioHorarioController.clear();
      _finHorarioController.clear();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          esEdicion ? 'Modificar Bloque Horario' : 'Nuevo Bloque Horario',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _idHorarioController,
              enabled: !esEdicion,
              decoration: InputDecoration(
                labelText: 'ID único (Ej: H15)',
                border: const OutlineInputBorder(),
                fillColor: esEdicion ? Colors.grey.shade200 : null,
                filled: esEdicion,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _inicioHorarioController,
              decoration: const InputDecoration(
                labelText: 'Hora Inicio (Ej: 08:00)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _finHorarioController,
              decoration: const InputDecoration(
                labelText: 'Hora Fin (Ej: 09:00)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _idHorarioController.clear();
              _inicioHorarioController.clear();
              _finHorarioController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (esEdicion) {
                _modificarBlockHorario(bloqueExistente);
              } else {
                _agregarBloqueHorario();
              }
              Navigator.pop(context);
            },
            child: Text(esEdicion ? 'Actualizar Bloque' : 'Crear Bloque'),
          ),
        ],
      ),
    );
  }

  void _modificarBlockHorario(Map<String, dynamic> b) {
    _modificarBloqueHorario(b);
  }

  // --- CARDS RENDERIZADORES DE TABLAS ---
  Widget _buildListCard(String titulo, String documento) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('configuracion')
          .doc(documento)
          .snapshots(),
      builder: (context, snapshot) {
        List<String> items = [];
        if (snapshot.hasData && snapshot.data!.exists) {
          var data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('lista')) {
            items = List<String>.from(data['lista'] ?? []);
          }
        }
        return _cardEstructuraBase(
          titulo,
          () => _dialogoConstante(titulo, documento),
          ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) => ListTile(
              title: Text(items[i]),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.edit_note_rounded,
                      color: Colors.blue,
                    ),
                    onPressed: () => _dialogoConstante(
                      titulo,
                      documento,
                      valorExistente: items[i],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _borrarItemLista(documento, items[i]),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHorariosCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('configuracion')
          .doc('horarios')
          .snapshots(),
      builder: (context, snapshot) {
        List<dynamic> bloques = [];
        if (snapshot.hasData && snapshot.data!.exists) {
          var data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('bloques')) {
            bloques = data['bloques'] ?? [];
          }
        }
        return _cardEstructuraBase(
          'Bloques Horarios Estructurados',
          _dialogoHorario,
          ListView.builder(
            itemCount: bloques.length,
            itemBuilder: (context, i) {
              final b = bloques[i] as Map<String, dynamic>;
              return ListTile(
                leading: Chip(label: Text(b['id'] ?? '')),
                title: Text('${b['horaInicio']} a ${b['horaFin']} hs'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.edit_calendar_rounded,
                        color: Colors.blue,
                      ),
                      onPressed: () => _dialogoHorario(bloqueExistente: b),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _borrarBloqueHorario(b),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _cardEstructuraBase(
    String titulo,
    VoidCallback accionAlta,
    Widget listado,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.add_circle,
                  color: Colors.teal,
                  size: 28,
                ),
                onPressed: accionAlta,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: listado,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Panel de Configuración',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const Text(
            'Gestioná constantes resguardando la integridad de las relaciones de los socios.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
              children: [
                _buildListCard('Deportes / Actividades', 'deportes'),
                _buildListCard('Frecuencias Permitidas', 'frecuencias'),
                _buildHorariosCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
