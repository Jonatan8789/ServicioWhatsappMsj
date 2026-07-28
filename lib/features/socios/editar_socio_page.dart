import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'socio_model.dart';
import 'bloque_horario_model.dart';

class EditarSocioPage extends StatefulWidget {
  final SocioModel socio;
  final VoidCallback onVolver;

  const EditarSocioPage({
    super.key,
    required this.socio,
    required this.onVolver,
  });

  @override
  State<EditarSocioPage> createState() => _EditarSocioPageState();
}

class _EditarSocioPageState extends State<EditarSocioPage> {
  final _formKey = GlobalKey<FormState>();
  bool _guardando = false;
  bool _cargandoConfig = true;

  late TextEditingController _dniController;
  late TextEditingController _nombreController;
  late TextEditingController _telefonoController;
  late TextEditingController _emailController;
  late TextEditingController _contactoEmergenciaController;

  late bool _esEstudianteEscuela;
  late TextEditingController _colegioController;
  late TextEditingController _gradoAnioController;
  late TextEditingController _descuentoPorcentajeController;

  DateTime? _fechaNacimiento;
  DateTime? _vencimientoApto;

  Uint8List? _fotoBytes;
  String? _fotoNombre;
  Uint8List? _aptoBytes;
  String? _aptoNombre;

  List<String> _opcionesDeportes = [];
  List<String> _opcionesFrecuencia = [];
  List<BloqueHorarioModel> _opcionesHorarios = [];

  String? _deporteSeleccionado;
  String? _frecuenciaSeleccionada;
  String? _bloqueHorarioSeleccionadoId;
  List<String> _diasSeleccionados = [];

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
    _nombreController = TextEditingController(text: widget.socio.nombre);
    _dniController = TextEditingController(text: widget.socio.dni);
    _telefonoController = TextEditingController(text: widget.socio.telefono);
    _emailController = TextEditingController();
    _contactoEmergenciaController = TextEditingController(
      text: widget.socio.contactoEmergencia,
    );

    _esEstudianteEscuela = widget.socio.esEstudianteEscuela;
    _colegioController = TextEditingController(
      text: widget.socio.colegioInstitucion ?? '',
    );
    _gradoAnioController = TextEditingController(
      text: widget.socio.gradoAnio ?? '',
    );
    _descuentoPorcentajeController = TextEditingController(
      text: widget.socio.descuentoEscolarPorcentaje.toStringAsFixed(0),
    );

    _fechaNacimiento = widget.socio.fechaNacimiento;
    _vencimientoApto = widget.socio.vencimientoAptoMedico;

    _deporteSeleccionado = widget.socio.deporte;
    _frecuenciaSeleccionada = widget.socio.frecuencia;
    _bloqueHorarioSeleccionadoId = widget.socio.idBloqueHorario;
    _diasSeleccionados = List<String>.from(widget.socio.dias);

    _cargarDatosSocioYConfig();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _dniController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _contactoEmergenciaController.dispose();
    _colegioController.dispose();
    _gradoAnioController.dispose();
    _descuentoPorcentajeController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatosSocioYConfig() async {
    try {
      final docSocio = await FirebaseFirestore.instance
          .collection('socios')
          .doc(widget.socio.id)
          .get();
      if (docSocio.exists && docSocio.data() != null) {
        final dataSocio = docSocio.data()!;
        _emailController.text = dataSocio['email'] ?? '';
      }

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
      return '';
    }
  }

  Future<void> _actualizarSocio() async {
    if (!_formKey.currentState!.validate()) return;

    if (_deporteSeleccionado == null ||
        _frecuenciaSeleccionada == null ||
        _bloqueHorarioSeleccionadoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleccioná el Deporte, Frecuencia y Bloque Horario.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _guardando = true);

    try {
      String fotoUrlFinal = widget.socio.fotoUrl;
      String aptoUrlFinal = widget.socio.aptoUrl;
      final dni = _dniController.text.trim();

      if (_fotoBytes != null && _fotoNombre != null) {
        fotoUrlFinal = await _subirArchivo(
          _fotoBytes!,
          'socios/fotos',
          dni,
          _fotoNombre!,
        );
      }
      if (_aptoBytes != null && _aptoNombre != null) {
        aptoUrlFinal = await _subirArchivo(
          _aptoBytes!,
          'socios/aptos',
          dni,
          _aptoNombre!,
        );
      }

      final numLimpio = _telefonoController.text.replaceAll(
        RegExp(r'[\s\-\+]'),
        '',
      );

      final socioActualizado = SocioModel(
        id: widget.socio.id,
        numeroSocio: widget.socio.numeroSocio,
        nombre: _nombreController.text.trim(),
        dni: dni,
        telefono: numLimpio,
        fotoUrl: fotoUrlFinal,
        aptoUrl: aptoUrlFinal,
        fechaAlta: widget.socio.fechaAlta,
        activo: widget.socio.activo,
        fechaNacimiento: _fechaNacimiento,
        vencimientoAptoMedico:
            _vencimientoApto ?? DateTime.now().add(const Duration(days: 365)),
        contactoEmergencia: _contactoEmergenciaController.text.trim(),
        deporte: _deporteSeleccionado ?? '',
        frecuencia: _frecuenciaSeleccionada ?? '',
        dias: _diasSeleccionados,
        idBloqueHorario: _bloqueHorarioSeleccionadoId ?? '',
        saldoCuentaCorriente: widget.socio.saldoCuentaCorriente,
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

      final mapData = socioActualizado.toFirestore();
      mapData['email'] = _emailController.text.trim().toLowerCase();

      await FirebaseFirestore.instance
          .collection('socios')
          .doc(widget.socio.id)
          .update(mapData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Datos actualizados correctamente!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onVolver();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar socio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
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
                Text(
                  'Modificar Socio: ${widget.socio.nombre}',
                  style: const TextStyle(
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
                                        : (widget.socio.fotoUrl.isNotEmpty
                                              ? ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(65),
                                                  child: Image.network(
                                                    widget.socio.fotoUrl,
                                                    width: 130,
                                                    height: 130,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          _,
                                                          __,
                                                          ___,
                                                        ) => const Icon(
                                                          Icons.person_rounded,
                                                          size: 60,
                                                          color: Colors.grey,
                                                        ),
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.person_rounded,
                                                  size: 60,
                                                  color: Colors.grey,
                                                )),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: CircleAvatar(
                                      backgroundColor: Colors.teal,
                                      radius: 20,
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.edit_rounded,
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
                            TextFormField(
                              controller: _nombreController,
                              decoration: const InputDecoration(
                                labelText: 'Nombre Completo',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.badge_rounded),
                              ),
                              validator: (v) =>
                                  v!.trim().isEmpty ? 'Requerido' : null,
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _dniController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'DNI / Identificación',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.remember_me_rounded),
                              ),
                              validator: (v) =>
                                  v!.trim().isEmpty ? 'Requerido' : null,
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _telefonoController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText:
                                    'Teléfono / WhatsApp (Notificaciones)',
                                hintText:
                                    'Ej: 5491112345678 (Con código de área)',
                                prefixIcon: Icon(Icons.phone_android_rounded),
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El teléfono es obligatorio para notificaciones';
                                }
                                final numLimpio = value.replaceAll(
                                  RegExp(r'[\s\-\+]'),
                                  '',
                                );
                                if (!RegExp(
                                  r'^\d{10,15}$',
                                ).hasMatch(numLimpio)) {
                                  return 'Ingrese un número válido con código de área (10 a 15 dígitos)';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText:
                                    'Correo Electrónico (Notificaciones)',
                                hintText: 'ejemplo@correo.com',
                                prefixIcon: Icon(Icons.email_rounded),
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El email es obligatorio para notificaciones';
                                }
                                final emailRegex = RegExp(
                                  r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                                );
                                if (!emailRegex.hasMatch(value.trim())) {
                                  return 'Ingrese una dirección de correo válida';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            ListTile(
                              leading: const Icon(
                                Icons.cake_rounded,
                                color: Colors.teal,
                              ),
                              title: Text(
                                _fechaNacimiento == null
                                    ? 'Seleccionar Fecha de Nacimiento'
                                    : 'Nacimiento: ${DateFormat('dd/MM/yyyy').format(_fechaNacimiento!)}',
                              ),
                              shape: RoundedRectangleBorder(
                                side: BorderSide(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              onTap: () async {
                                final f = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      _fechaNacimiento ?? DateTime(2000),
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
                              '2. Área Médica y de Emergencias',
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
                                    'Contacto de Emergencia (Nombre y Teléfono)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.heart_broken_rounded),
                              ),
                              validator: (v) =>
                                  v!.trim().isEmpty ? 'Requerido' : null,
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
                                    label: const Text('Reemplazar Apto Físico'),
                                    onPressed: _seleccionarApto,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      _aptoNombre ??
                                          (widget.socio.aptoUrl.isNotEmpty
                                              ? 'Certificado previo cargado'
                                              : 'Sin archivo'),
                                      style: TextStyle(
                                        color:
                                            (_aptoNombre != null ||
                                                widget.socio.aptoUrl.isNotEmpty)
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
                                    ? 'Vencimiento del Apto'
                                    : 'Vence el: ${DateFormat('dd/MM/yyyy').format(_vencimientoApto!)}',
                              ),
                              shape: RoundedRectangleBorder(
                                side: BorderSide(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              onTap: () async {
                                final f = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      _vencimientoApto ?? DateTime.now(),
                                  firstDate: DateTime.now().subtract(
                                    const Duration(days: 365),
                                  ),
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
                              '3. Asignación Deportiva',
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
                              value:
                                  _opcionesDeportes.contains(
                                    _deporteSeleccionado,
                                  )
                                  ? _deporteSeleccionado
                                  : null,
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
                              value:
                                  _opcionesFrecuencia.contains(
                                    _frecuenciaSeleccionada,
                                  )
                                  ? _frecuenciaSeleccionada
                                  : null,
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
                              value:
                                  _opcionesHorarios.any(
                                    (h) => h.id == _bloqueHorarioSeleccionadoId,
                                  )
                                  ? _bloqueHorarioSeleccionadoId
                                  : null,
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
                                  'Convenio Escolar / Arancel Especial',
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
                                  labelText: 'Escuela / Colegio',
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
                                        border: OutlineInputBorder(),
                                        suffixText: '%',
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
                                      backgroundColor: const Color(0xFF0F172A),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 20,
                                      ),
                                      minimumSize: const Size.fromHeight(50),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.check_circle_rounded,
                                    ),
                                    label: const Text(
                                      'Guardar Cambios',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed: _actualizarSocio,
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
