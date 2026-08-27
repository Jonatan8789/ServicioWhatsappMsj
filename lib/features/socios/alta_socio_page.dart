import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'socio_model.dart';
import 'bloque_horario_model.dart';

class AltaSocioPage extends StatefulWidget {
  final VoidCallback onVolver;
  const AltaSocioPage({super.key, required this.onVolver});

  @override
  State<AltaSocioPage> createState() => _AltaSocioPageState();
}

class _AltaSocioPageState extends State<AltaSocioPage> {
  final _formKey = GlobalKey<FormState>();
  bool _guardando = false;
  bool _cargandoConfig = true;

  // Controladores Base
  final TextEditingController _dniController = TextEditingController();
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _telefonoController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _contactoEmergenciaController =
      TextEditingController();

  // Controladores Convenio Escolar
  bool _esEstudianteEscuela = false;
  final TextEditingController _colegioController = TextEditingController();
  final TextEditingController _gradoAnioController = TextEditingController();
  final TextEditingController _descuentoPorcentajeController =
      TextEditingController(text: '0');

  DateTime? _fechaNacimiento;
  DateTime? _vencimientoApto;

  // Variables Multimedia
  Uint8List? _fotoBytes;
  String? _fotoNombre;
  Uint8List? _aptoBytes;
  String? _aptoNombre;

  // Configuración de Firebase
  List<String> _opcionesDeportes = [];
  List<String> _opcionesFrecuencia = [];
  List<BloqueHorarioModel> _opcionesHorarios = [];

  String? _deporteSeleccionado;
  String? _frecuenciaSeleccionada;
  String? _bloqueHorarioSeleccionadoId;
  final List<String> _diasSeleccionados = [];

  final List<String> _diasSemana = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
  ];

  @override
  void initState() {
    super.initState();
    _cargarConfiguracion();
  }

  @override
  void dispose() {
    _dniController.dispose();
    _nombreController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _contactoEmergenciaController.dispose();
    _colegioController.dispose();
    _gradoAnioController.dispose();
    _descuentoPorcentajeController.dispose();
    super.dispose();
  }

  Future<void> _cargarConfiguracion() async {
    try {
      final configRef = FirebaseFirestore.instance.collection('configuracion');
      final resultados = await Future.wait([
        configRef.doc('deportes').get(),
        configRef.doc('frecuencias').get(),
        configRef.doc('horarios').get(),
      ]);

      if (mounted) {
        setState(() {
          if (resultados[0].exists && resultados[0].data() != null) {
            var data = resultados[0].data() as Map<String, dynamic>;
            _opcionesDeportes = List<String>.from(data['lista'] ?? []);
          }
          if (resultados[1].exists && resultados[1].data() != null) {
            var data = resultados[1].data() as Map<String, dynamic>;
            _opcionesFrecuencia = List<String>.from(data['lista'] ?? []);
          }
          if (resultados[2].exists && resultados[2].data() != null) {
            var data = resultados[2].data() as Map<String, dynamic>;
            if (data.containsKey('bloques')) {
              var bloquesRaw = data['bloques'] as List<dynamic>;
              _opcionesHorarios = bloquesRaw
                  .map(
                    (b) =>
                        BloqueHorarioModel.fromMap(b as Map<String, dynamic>),
                  )
                  .toList();
            }
          }
          _cargandoConfig = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargandoConfig = false);
      }
    }
  }

  Future<void> _seleccionarFoto() async {
    final resultado = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (resultado != null && resultado.files.first.bytes != null) {
      setState(() {
        _fotoBytes = resultado.files.first.bytes;
        _fotoNombre = resultado.files.first.name;
      });
    }
  }

  Future<void> _seleccionarApto() async {
    final resultado = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (resultado != null && resultado.files.first.bytes != null) {
      setState(() {
        _aptoBytes = resultado.files.first.bytes;
        _aptoNombre = resultado.files.first.name;
      });
    }
  }

  Future<String> _subirArchivo(
    Uint8List bytes,
    String carpeta,
    String prefijo,
    String nombreOriginal,
  ) async {
    try {
      final extension = nombreOriginal.contains('.')
          ? nombreOriginal.split('.').last.toLowerCase()
          : 'jpg';
      final nombreFinal =
          '${prefijo}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final ref = FirebaseStorage.instance.ref().child('$carpeta/$nombreFinal');

      final metadata = SettableMetadata(
        contentType: extension == 'pdf'
            ? 'application/pdf'
            : 'image/$extension',
      );

      final uploadTask = await ref.putData(bytes, metadata);
      return await uploadTask.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Error subiendo archivo: $e');
      return '';
    }
  }

  // 📣 DIÁLOGO DE NOTIFICACIÓN CON EL NÚMERO DE SOCIO ASIGNADO
  void _mostrarConfirmacionSocio(String numeroSocio, String nombreSocio) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Text('¡Alta Exitosa!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'El socio $nombreSocio ha sido registrado correctamente.',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.badge_rounded, color: Colors.teal),
                  const SizedBox(width: 10),
                  Text(
                    'Número Asignado: N° $numeroSocio',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onVolver();
            },
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _guardarSocio() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    try {
      String fotoUrlFinal = '';
      String aptoUrlFinal = '';
      final dni = _dniController.text.trim();
      final nombreSocio = _nombreController.text.trim();

      if (_fotoBytes != null && _fotoNombre != null) {
        fotoUrlFinal = await _subirArchivo(
          _fotoBytes!,
          'socios/fotos',
          dni.isEmpty ? 'foto' : dni,
          _fotoNombre!,
        );
      }
      if (_aptoBytes != null && _aptoNombre != null) {
        aptoUrlFinal = await _subirArchivo(
          _aptoBytes!,
          'socios/aptos',
          dni.isEmpty ? 'apto' : dni,
          _aptoNombre!,
        );
      }

      final querySocios = await FirebaseFirestore.instance
          .collection('socios')
          .get();
      final numCorrelativo = querySocios.docs.length + 1;
      final numeroSocioStr = numCorrelativo.toString().padLeft(4, '0');

      final nuevoDocSocioRef = FirebaseFirestore.instance
          .collection('socios')
          .doc();

      final numLimpio = _telefonoController.text.replaceAll(
        RegExp(r'[\s\-\+]'),
        '',
      );

      final nuevoSocio = SocioModel(
        id: nuevoDocSocioRef.id,
        numeroSocio: numeroSocioStr,
        nombre: nombreSocio,
        dni: dni,
        telefono: numLimpio,
        fotoUrl: fotoUrlFinal,
        aptoUrl: aptoUrlFinal,
        fechaAlta: DateTime.now(),
        activo: true,
        fechaNacimiento: _fechaNacimiento,
        vencimientoAptoMedico:
            _vencimientoApto ?? DateTime.now().add(const Duration(days: 365)),
        contactoEmergencia: _contactoEmergenciaController.text.trim(),
        deporte: _deporteSeleccionado ?? 'Socio Natatorio',
        frecuencia: _frecuenciaSeleccionada ?? 'Sin Especificar',
        dias: _diasSeleccionados,
        idBloqueHorario: _bloqueHorarioSeleccionadoId ?? '',
        saldoCuentaCorriente: 0.0,
        esEstudianteEscuela: _esEstudianteEscuela,
        colegioInstitucion: _esEstudianteEscuela
            ? _colegioController.text.trim()
            : null,
        gradoAnio: _esEstudianteEscuela
            ? _gradoAnioController.text.trim()
            : null,
        descuentoEscolarPorcentaje: _esEstudianteEscuela
            ? (double.tryParse(_descuentoPorcentajeController.text.trim()) ??
                  0.0)
            : 0.0,
      );

      final mapData = nuevoSocio.toFirestore();
      mapData['email'] = _emailController.text.trim().toLowerCase();

      await nuevoDocSocioRef.set(mapData);

      if (mounted) {
        setState(() => _guardando = false);
        _mostrarConfirmacionSocio(numeroSocioStr, nombreSocio);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar socio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoConfig) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: widget.onVolver,
                ),
                const SizedBox(width: 16),
                const Text(
                  'Ficha de Alta de Socio',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40.0),
              child: Form(
                key: _formKey,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '1. Datos Personales',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueAccent,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Center(
                              child: Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 65,
                                    backgroundColor: Colors.grey.shade200,
                                    child: _fotoBytes != null
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              65,
                                            ),
                                            child: Image.memory(
                                              _fotoBytes!,
                                              width: 130,
                                              height: 130,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.person_rounded,
                                            size: 60,
                                            color: Colors.grey,
                                          ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: CircleAvatar(
                                      backgroundColor: Colors.teal,
                                      radius: 20,
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.camera_alt_rounded,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                        onPressed: _seleccionarFoto,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_fotoNombre != null)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _fotoNombre!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 32),

                            // 🟢 ÚNICO CAMPO OBLIGATORIO
                            TextFormField(
                              controller: _nombreController,
                              decoration: const InputDecoration(
                                labelText: 'Apellido y Nombre *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.badge_rounded),
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty
                                      ? 'El Apellido y Nombre es obligatorio'
                                      : null,
                            ),
                            const SizedBox(height: 20),

                            // 🟡 CAMPOS OPCIONALES
                            TextFormField(
                              controller: _dniController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'DNI / Identificación (Opcional)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.remember_me_rounded),
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _telefonoController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Teléfono / WhatsApp (Opcional)',
                                hintText: 'Ej: 5491112345678',
                                prefixIcon: Icon(Icons.phone_android_rounded),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Correo Electrónico (Opcional)',
                                hintText: 'ejemplo@correo.com',
                                prefixIcon: Icon(Icons.email_rounded),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 20),
                            ListTile(
                              leading: const Icon(
                                Icons.cake_rounded,
                                color: Colors.teal,
                              ),
                              title: Text(
                                _fechaNacimiento == null
                                    ? 'Fecha de Nacimiento (Opcional)'
                                    : 'Nacimiento: ${DateFormat('dd/MM/yyyy').format(_fechaNacimiento!)}',
                              ),
                              shape: RoundedRectangleBorder(
                                side: BorderSide(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              onTap: () async {
                                final f = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime(2000),
                                  firstDate: DateTime(1920),
                                  lastDate: DateTime.now(),
                                );
                                if (f != null) {
                                  setState(() => _fechaNacimiento = f);
                                }
                              },
                            ),
                            const SizedBox(height: 40),
                            const Text(
                              '2. Área Médica y de Emergencias (Opcional)',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueAccent,
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _contactoEmergenciaController,
                              decoration: const InputDecoration(
                                labelText:
                                    'Contacto de Emergencia (Opcional)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.heart_broken_rounded),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal.shade700,
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(
                                      Icons.cloud_upload_rounded,
                                    ),
                                    label: const Text('Adjuntar Apto Físico'),
                                    onPressed: _seleccionarApto,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      _aptoNombre ??
                                          'Ningún archivo cargado (PDF o Imagen)',
                                      style: TextStyle(
                                        color: _aptoNombre != null
                                            ? Colors.black87
                                            : Colors.grey,
                                        fontSize: 13,
                                        fontWeight: _aptoNombre != null
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            ListTile(
                              leading: const Icon(
                                Icons.verified_user_rounded,
                                color: Colors.orange,
                              ),
                              title: Text(
                                _vencimientoApto == null
                                    ? 'Vencimiento del Apto (Por defecto 1 año)'
                                    : 'Vence el: ${DateFormat('dd/MM/yyyy').format(_vencimientoApto!)}',
                              ),
                              shape: RoundedRectangleBorder(
                                side: BorderSide(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              onTap: () async {
                                final f = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now().add(
                                    const Duration(days: 365),
                                  ),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 730),
                                  ),
                                );
                                if (f != null) {
                                  setState(() => _vencimientoApto = f);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 40),

                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '3. Asignación Deportiva (Opcional)',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueAccent,
                              ),
                            ),
                            const SizedBox(height: 24),
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Deporte Principal',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.sports_rounded),
                              ),
                              value: _deporteSeleccionado,
                              items: _opcionesDeportes
                                  .map(
                                    (d) => DropdownMenuItem(
                                      value: d,
                                      child: Text(d),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _deporteSeleccionado = val),
                            ),
                            const SizedBox(height: 20),
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Frecuencia Semanal',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.calendar_month_rounded),
                              ),
                              value: _frecuenciaSeleccionada,
                              items: _opcionesFrecuencia
                                  .map(
                                    (f) => DropdownMenuItem(
                                      value: f,
                                      child: Text(f),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _frecuenciaSeleccionada = val),
                            ),
                            const SizedBox(height: 20),
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Bloque Horario',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(
                                  Icons.access_time_filled_rounded,
                                ),
                              ),
                              value: _bloqueHorarioSeleccionadoId,
                              items: _opcionesHorarios
                                  .map(
                                    (h) => DropdownMenuItem(
                                      value: h.id,
                                      child: Text(h.etiquetaVisual),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) => setState(
                                () => _bloqueHorarioSeleccionadoId = val,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Días Permitidos:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _diasSemana.map((dia) {
                                final seleccionado = _diasSeleccionados
                                    .contains(dia);
                                return FilterChip(
                                  label: Text(dia),
                                  selected: seleccionado,
                                  selectedColor: Colors.blue.withValues(
                                    alpha: 0.2,
                                  ),
                                  checkmarkColor: Colors.blue,
                                  onSelected: (bool estado) {
                                    setState(() {
                                      if (estado) {
                                        _diasSeleccionados.add(dia);
                                      } else {
                                        _diasSeleccionados.remove(dia);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),

                            const SizedBox(height: 32),
                            const Divider(),
                            const SizedBox(height: 16),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '4. Convenio Escolar / Arancel Especial',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueAccent,
                                  ),
                                ),
                                Switch(
                                  value: _esEstudianteEscuela,
                                  activeColor: Colors.indigo,
                                  onChanged: (val) => setState(
                                    () => _esEstudianteEscuela = val,
                                  ),
                                ),
                              ],
                            ),
                            if (_esEstudianteEscuela) ...[
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _colegioController,
                                decoration: const InputDecoration(
                                  labelText: 'Escuela / Colegio / Institución',
                                  hintText: 'Ej: Escuela San José',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.school_rounded),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _gradoAnioController,
                                      decoration: const InputDecoration(
                                        labelText: 'Grado / Año',
                                        hintText: 'Ej: 4to Grado A',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.class_outlined),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextFormField(
                                      controller:
                                          _descuentoPorcentajeController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: '% Descuento Cuota',
                                        suffixText: '%',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.percent_rounded),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            const SizedBox(height: 40),
                            _guardando
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF1E293B),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 20,
                                      ),
                                      minimumSize: const Size.fromHeight(50),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    icon: const Icon(Icons.save_rounded),
                                    label: const Text(
                                      'Guardar Socio',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed: _guardarSocio,
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}