import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/familia_service.dart';
import 'socio_model.dart';

class SocioDetallePage extends StatefulWidget {
  final SocioModel socio;
  final VoidCallback onVolver;

  const SocioDetallePage({
    super.key,
    required this.socio,
    required this.onVolver,
  });

  @override
  State<SocioDetallePage> createState() => _SocioDetallePageState();
}

class _SocioDetallePageState extends State<SocioDetallePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FamiliaService _familiaService = FamiliaService();
  String _etiquetaHorarioTraduccion = 'Cargando horario...';

  // 👨‍👩‍👧‍👦 Se mantiene en estado local porque widget.socio es inmutable:
  // así la sección de grupo familiar refleja los cambios sin depender de
  // que la pantalla padre vuelva a pasar un SocioModel actualizado.
  String? _grupoFamiliarId;

  @override
  void initState() {
    super.initState();
    _grupoFamiliarId = widget.socio.grupoFamiliarId;
    _obtenerTraduccionHorario();
  }

  // 🚨 Misma tabla de mapeo que usa control_acceso_page.dart para inicializar
  // 'limiteClases' en el mismo documento que ese lector consulta: si acá se
  // creaba el doc con SOLO el incremento (sin este baseline), el socio
  // terminaba con un límite MENOR al que le corresponde por su frecuencia.
  int _limiteClasesDesdeFrecuencia(String? frecuencia) {
    final String frecuenciaRaw = (frecuencia ?? 'Pase Libre').toLowerCase();
    if (frecuenciaRaw.contains('1') || frecuenciaRaw.contains('una')) {
      return 4;
    } else if (frecuenciaRaw.contains('2') || frecuenciaRaw.contains('dos')) {
      return 8;
    } else if (frecuenciaRaw.contains('3') || frecuenciaRaw.contains('tres')) {
      return 12;
    } else if (frecuenciaRaw.contains('4') ||
        frecuenciaRaw.contains('cuatro')) {
      return 16;
    }
    return 999;
  }

  Future<void> _obtenerTraduccionHorario() async {
    final String bloqueId = widget.socio.idBloqueHorario;
    if (bloqueId.isEmpty) {
      if (mounted) {
        setState(() => _etiquetaHorarioTraduccion = 'Sin horario asignado');
      }
      return;
    }

    try {
      final docHorarios = await _firestore
          .collection('configuracion')
          .doc('horarios')
          .get();

      if (docHorarios.exists && docHorarios.data() != null) {
        final data = docHorarios.data()!;
        final bloques = data['bloques'] as List<dynamic>? ?? [];

        for (var b in bloques) {
          if (b['id'] == bloqueId) {
            // 🚨 configuracion_page.dart escribe 'horaInicio'/'horaFin', no
            // 'horaDesde'/'horaHasta' — con las claves viejas esto nunca
            // encontraba el horario real del bloque.
            final desde = b['horaInicio'] ?? '';
            final hasta = b['horaFin'] ?? '';
            final nombre = b['nombre'] ?? '';

            if (mounted) {
              setState(() {
                _etiquetaHorarioTraduccion =
                    desde.isNotEmpty && hasta.isNotEmpty
                    ? '$nombre ($desde hs a $hasta hs)'
                    : (nombre.isNotEmpty ? nombre : bloqueId);
              });
            }
            return;
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _etiquetaHorarioTraduccion = bloqueId);
    }
  }

  // 🧹 RESETEAR HUELLAS VINCULADAS AL SOCIO
  Future<void> _resetearHuellasSocio() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.restart_alt_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Resetear Biometría'),
          ],
        ),
        content: Text(
          '¿Estás seguro de eliminar las ${widget.socio.huellasHashes.length} huellas asociadas a ${widget.socio.nombre}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Confirmar Reseteo',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firestore.collection('socios').doc(widget.socio.id).update({
        'huellasHashes': [],
        'huellaHash': '',
        'fechaReseteoHuellas': DateTime.now(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🧹 Huellas desvinculadas con éxito.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {});
      }
    }
  }

  // ➕ ACREDITACIÓN INDIVIDUAL O MASIVA DE CLASES EXTRA
  void _mostrarDialogoAcreditarClases() {
    final cantCtrl = TextEditingController(text: '1');
    bool aplicarAMasivo = false;
    String deporteMasivo = widget.socio.deporte;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.add_task_rounded, color: Colors.teal),
              SizedBox(width: 8),
              Text('Acreditar Clases / Créditos Extra'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: cantCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cantidad de Clases a Acreditar',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.plus_one_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text(
                    '¿Aplicar a TODOS los socios de la actividad?',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: Text(
                    'Acreditará masivamente a alumnos de $deporteMasivo',
                  ),
                  value: aplicarAMasivo,
                  activeColor: Colors.teal,
                  onChanged: (val) => setModalState(() => aplicarAMasivo = val),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
              ),
              onPressed: () async {
                final int cantidadExtra = int.tryParse(cantCtrl.text) ?? 1;
                final hoy = DateTime.now();
                final periodoClave =
                    "${hoy.year}-${hoy.month.toString().padLeft(2, '0')}";

                if (aplicarAMasivo) {
                  // Acreditación Masiva
                  final sociosSnap = await _firestore
                      .collection('socios')
                      .where('deporte', isEqualTo: deporteMasivo)
                      .get();

                  // 🚨 Antes hacía un `credRef.get()` POR SOCIO dentro del
                  // loop para saber si ya tenía crédito cargado este
                  // período — con cientos de socios en un deporte, eso son
                  // cientos de lecturas secuenciales antes de escribir nada.
                  // Mismo fix que liquidacion_cuotas_service.dart: una sola
                  // consulta collectionGroup fuera del loop.
                  final creditosPeriodoSnap = await _firestore
                      .collectionGroup('creditos_mensuales')
                      .where('periodo', isEqualTo: periodoClave)
                      .get();
                  final Set<String> sociosConCredito = creditosPeriodoSnap
                      .docs
                      .map((d) => d.reference.parent.parent!.id)
                      .toSet();

                  final batch = _firestore.batch();
                  for (var doc in sociosSnap.docs) {
                    final credRef = _firestore
                        .collection('socios')
                        .doc(doc.id)
                        .collection('creditos_mensuales')
                        .doc(periodoClave);

                    if (!sociosConCredito.contains(doc.id)) {
                      final int limiteBase = _limiteClasesDesdeFrecuencia(
                        doc.data()['frecuencia']?.toString(),
                      );
                      batch.set(credRef, {
                        'periodo': periodoClave,
                        'clasesUsadas': 0,
                        'fechaInicio': DateTime.now(),
                        'limiteClases': limiteBase + cantidadExtra,
                      });
                    } else {
                      batch.set(credRef, {
                        'limiteClases': FieldValue.increment(cantidadExtra),
                      }, SetOptions(merge: true));
                    }
                  }
                  await batch.commit();
                } else {
                  // Acreditación Individual
                  final credRef = _firestore
                      .collection('socios')
                      .doc(widget.socio.id)
                      .collection('creditos_mensuales')
                      .doc(periodoClave);

                  final credSnap = await credRef.get();
                  if (!credSnap.exists) {
                    final int limiteBase = _limiteClasesDesdeFrecuencia(
                      widget.socio.frecuencia,
                    );
                    await credRef.set({
                      'periodo': periodoClave,
                      'clasesUsadas': 0,
                      'fechaInicio': DateTime.now(),
                      'limiteClases': limiteBase + cantidadExtra,
                    });
                  } else {
                    await credRef.set({
                      'limiteClases': FieldValue.increment(cantidadExtra),
                    }, SetOptions(merge: true));
                  }
                }

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        aplicarAMasivo
                            ? '✅ Clases acreditadas masivamente para $deporteMasivo.'
                            : '✅ Clases agregadas a ${widget.socio.nombre}.',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text(
                'Acreditar',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirAptoMedico(BuildContext context) async {
    if (widget.socio.aptoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este socio no posee apto físico adjunto.'),
        ),
      );
      return;
    }

    final Uri url = Uri.parse(widget.socio.aptoUrl);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Enlace del Apto Médico'),
            content: SelectableText(widget.socio.aptoUrl),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _registrarMatriculaPrevio() async {
    final DateTime? fechaSeleccionada = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'SELECCIONAR FECHA DE PAGO PREVIA',
    );

    if (fechaSeleccionada != null) {
      await _firestore.collection('socios').doc(widget.socio.id).update({
        'matriculaAlDia': true,
        'fechaPagoMatricula': Timestamp.fromDate(fechaSeleccionada),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Matrícula asentada con fecha ${DateFormat('dd/MM/yyyy').format(fechaSeleccionada)}',
            ),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
      }
    }
  }

  // 🪪 CARNET DIGITAL CON QR — el código codifica el DNI para que el mismo
  // valor sea válido tanto en el escáner de cámara (control_acceso_page)
  // como en cualquier lector QR tipo teclado (USB HID) sin lógica extra.
  void _mostrarCarnetQr() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Carnet Digital'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: widget.socio.dni.isNotEmpty
                    ? QrImageView(
                        data: widget.socio.dni,
                        version: QrVersions.auto,
                        size: 220,
                      )
                    : const SizedBox(
                        width: 220,
                        height: 220,
                        child: Center(
                          child: Text(
                            'Este socio no tiene DNI cargado.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.socio.nombre,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                'N° ${widget.socio.numeroSocio} • DNI ${widget.socio.dni}',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Presentá este código frente a la cámara del lector en recepción.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  // 👨‍👩‍👧‍👦 VINCULAR OTRO SOCIO AL GRUPO FAMILIAR (busca por DNI)
  void _mostrarDialogoVincularFamilia() {
    final dniCtrl = TextEditingController();
    Map<String, dynamic>? encontrado;
    String? encontradoId;
    bool buscando = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Vincular Grupo Familiar'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Buscá por DNI al familiar que ya es socio para sumarlo '
                  'al mismo grupo que ${widget.socio.nombre}.',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: dniCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'DNI del familiar',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: buscando
                          ? null
                          : () async {
                              final dniBuscado = dniCtrl.text.trim();
                              if (dniBuscado.isEmpty) return;
                              setModalState(() {
                                buscando = true;
                                error = null;
                                encontrado = null;
                              });
                              if (dniBuscado == widget.socio.dni) {
                                setModalState(() {
                                  buscando = false;
                                  error =
                                      'Ese es el DNI de ${widget.socio.nombre}.';
                                });
                                return;
                              }
                              final snap = await _firestore
                                  .collection('socios')
                                  .where('dni', isEqualTo: dniBuscado)
                                  .limit(1)
                                  .get();
                              setModalState(() {
                                buscando = false;
                                if (snap.docs.isEmpty) {
                                  error =
                                      'No se encontró ningún socio con ese DNI.';
                                } else {
                                  encontradoId = snap.docs.first.id;
                                  encontrado = snap.docs.first.data();
                                }
                              });
                            },
                      child: buscando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Buscar'),
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
                if (encontrado != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person, color: Colors.teal),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${encontrado!['nombre'] ?? 'Socio'} (N° ${encontrado!['numeroSocio'] ?? '-'})',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: encontrado == null
                  ? null
                  : () async {
                      try {
                        final nuevoGrupoId = await _familiaService.vincular(
                          socioIdA: widget.socio.id,
                          grupoFamiliarIdA: _grupoFamiliarId,
                          socioIdB: encontradoId!,
                          grupoFamiliarIdB: encontrado!['grupoFamiliarId']
                              ?.toString(),
                        );
                        if (context.mounted) {
                          setState(() => _grupoFamiliarId = nuevoGrupoId);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Grupo familiar vinculado.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setModalState(() => error = 'Error al vincular: $e');
                      }
                    },
              child: const Text('Vincular'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _desvincularFamiliar(String socioId, String nombre) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar del Grupo Familiar'),
        content: Text('¿Quitar a $nombre del grupo familiar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _familiaService.desvincular(socioId);
      if (socioId == widget.socio.id && mounted) {
        setState(() => _grupoFamiliarId = null);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Familiar desvinculado.')));
      }
    }
  }

  Widget _buildSeccionGrupoFamiliar() {
    if (_grupoFamiliarId == null || _grupoFamiliarId!.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Sin grupo familiar vinculado.',
            style: TextStyle(color: Colors.grey),
          ),
          OutlinedButton.icon(
            onPressed: _mostrarDialogoVincularFamilia,
            icon: const Icon(Icons.link_rounded, size: 16),
            label: const Text('Vincular Familiar'),
          ),
        ],
      );
    }

    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: _familiaService.streamIntegrantes(_grupoFamiliarId!),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final docs = snapshot.data!;
        final int activos = docs
            .where((d) => d.data()['activo'] == true)
            .length;
        final double descuento = _familiaService.descuentoPorTamano(activos);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (descuento > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$activos integrantes activos → ${descuento.toStringAsFixed(0)}% de descuento en la cuota',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ...docs.map((d) {
              final data = d.data();
              final bool esActual = d.id == widget.socio.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.person,
                      size: 16,
                      color: esActual ? Colors.teal : Colors.blueGrey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${data['nombre'] ?? 'Socio'}${esActual ? ' (esta ficha)' : ''}',
                        style: TextStyle(
                          fontWeight: esActual
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: Colors.red,
                      ),
                      tooltip: 'Quitar del grupo',
                      onPressed: () =>
                          _desvincularFamiliar(d.id, data['nombre'] ?? 'Socio'),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _mostrarDialogoVincularFamilia,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
              label: const Text('Agregar Familiar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool aptoValido = vencimientoVigente(
      widget.socio.vencimientoAptoMedico,
    );
    final int cantHuellas = widget.socio.huellasHashes.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 📱 Por debajo de este ancho la ficha no entra en dos columnas
          // (era un Row fijo flex:1 / flex:2) ni la barra superior en una
          // sola línea: los paneles se apilan dentro del mismo scroll (sin
          // Expanded, en Column cada uno toma su altura natural) y las
          // acciones pasan debajo del título, a lo ancho.
          final bool esMovil = constraints.maxWidth < 700;

          final Widget tituloFicha = Text(
            'Ficha Detallada: ${widget.socio.nombre}',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: esMovil ? 18 : 24,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0F172A),
            ),
          );

          final Widget chipNumeroSocio = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'N° ${widget.socio.numeroSocio}',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.blueGrey,
                fontWeight: FontWeight.bold,
              ),
            ),
          );

          final Widget botonCarnetQr = OutlinedButton.icon(
            icon: const Icon(Icons.qr_code_2_rounded, size: 18),
            label: const Text('Ver Carnet QR'),
            onPressed: _mostrarCarnetQr,
          );

          final Widget botonAcreditarClases = ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.add_task_rounded, size: 18),
            label: const Text('Acreditar Clases Extra'),
            onPressed: _mostrarDialogoAcreditarClases,
          );

          final Widget encabezado = Container(
            padding: EdgeInsets.symmetric(
              horizontal: esMovil ? 16 : 40,
              vertical: esMovil ? 16 : 24,
            ),
            color: Colors.white,
            child: esMovil
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded),
                            onPressed: widget.onVolver,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: tituloFicha),
                          const SizedBox(width: 8),
                          chipNumeroSocio,
                        ],
                      ),
                      const SizedBox(height: 12),
                      botonCarnetQr,
                      const SizedBox(height: 8),
                      botonAcreditarClases,
                    ],
                  )
                : Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        onPressed: widget.onVolver,
                      ),
                      const SizedBox(width: 16),
                      Flexible(child: tituloFicha),
                      const SizedBox(width: 12),
                      chipNumeroSocio,
                      const Spacer(),
                      botonCarnetQr,
                      const SizedBox(width: 12),
                      botonAcreditarClases,
                    ],
                  ),
          );

          final Widget panelFotoEstado = Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: EdgeInsets.all(esMovil ? 20.0 : 32.0),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 75,
                    backgroundColor: Colors.teal.withOpacity(0.1),
                    child: widget.socio.fotoUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(75),
                            child: CachedNetworkImage(
                              imageUrl: widget.socio.fotoUrl,
                              width: 150,
                              height: 150,
                              fit: BoxFit.cover,
                              placeholder: (context, url) =>
                                  const CircularProgressIndicator(
                                    color: Colors.teal,
                                  ),
                              errorWidget: (_, __, ___) => const Icon(
                                Icons.person,
                                size: 70,
                                color: Colors.teal,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            size: 70,
                            color: Colors.teal,
                          ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.socio.nombre,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'DNI ${widget.socio.dni}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  _buildEstadoFicha(
                    'Matrícula Anual',
                    widget.socio.matriculaAlDia
                        ? 'Al día (${widget.socio.fechaPagoMatricula != null ? DateFormat('dd/MM/yy').format(widget.socio.fechaPagoMatricula!) : 'S/D'})'
                        : 'PENDIENTE',
                    widget.socio.matriculaAlDia ? Colors.green : Colors.red,
                    accionIcono: Icons.edit_calendar_rounded,
                    accionTooltip: 'Asentar pago de matrícula con fecha previa',
                    onAccion: _registrarMatriculaPrevio,
                  ),
                  const SizedBox(height: 12),
                  _buildEstadoFicha(
                    'Último Mes Pago',
                    widget.socio.ultimoMesPago.isNotEmpty
                        ? widget.socio.ultimoMesPago
                        : 'Sin Registros',
                    Colors.indigo,
                  ),
                  const SizedBox(height: 12),
                  _buildEstadoFicha(
                    'Control Médico',
                    aptoValido ? 'Apto Vigente' : 'APTO VENCIDO',
                    aptoValido ? Colors.green : Colors.red,
                    accionIcono: Icons.description_outlined,
                    accionTooltip: 'Ver apto médico adjunto',
                    onAccion: () => _abrirAptoMedico(context),
                  ),
                  const SizedBox(height: 12),
                  _buildEstadoFicha(
                    'Estado Cta Cte',
                    widget.socio.saldoCuentaCorriente >= 0
                        ? 'Al día (\$${widget.socio.saldoCuentaCorriente.toStringAsFixed(0)})'
                        : 'Deuda (\$${widget.socio.saldoCuentaCorriente.abs().toStringAsFixed(0)})',
                    widget.socio.saldoCuentaCorriente >= 0
                        ? Colors.green
                        : Colors.red,
                  ),

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),

                  // 🔐 SECCIÓN DE BIOMETRÍA Y RESETEO DE HUELLAS
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Biometría Registrada',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueGrey,
                            ),
                          ),
                          Text(
                            cantHuellas > 0
                                ? '$cantHuellas huella(s) vinculada(s)'
                                : 'Sin huellas enroladas',
                            style: TextStyle(
                              fontSize: 12,
                              color: cantHuellas > 0
                                  ? Colors.green.shade800
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (cantHuellas > 0)
                        IconButton(
                          icon: const Icon(
                            Icons.restart_alt_rounded,
                            color: Colors.red,
                          ),
                          tooltip: 'Resetear Huellas Digitales',
                          onPressed: _resetearHuellasSocio,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );

          // 🗂️ Antes esto era una única Column con 4 secciones (Contacto,
          // Deporte&Horarios, Grupo Familiar, Historial) separadas sólo por
          // Divider()s dentro de un mismo scroll largo — mucha información
          // junta y sin jerarquía visual clara. Ahora son pestañas: cada
          // sección se ve de a una, sin perder nada de contenido.
          final Widget panelDatos = Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DefaultTabController(
              length: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TabBar(
                    isScrollable: true,
                    labelColor: Colors.teal.shade700,
                    unselectedLabelColor: Colors.blueGrey,
                    indicatorColor: Colors.teal,
                    tabAlignment: TabAlignment.start,
                    tabs: const [
                      Tab(text: 'Contacto'),
                      Tab(text: 'Deporte & Horarios'),
                      Tab(text: 'Grupo Familiar'),
                      Tab(text: 'Historial de Asistencias'),
                    ],
                  ),
                  const Divider(height: 1),
                  SizedBox(
                    height: esMovil ? 420 : 380,
                    child: TabBarView(
                      children: [
                        _buildTabContacto(esMovil),
                        _buildTabDeporteHorarios(esMovil),
                        _buildTabGrupoFamiliar(esMovil),
                        _buildTabHistorialAsistencias(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );

          return Column(
            children: [
              encabezado,
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(esMovil ? 16 : 40),
                  child: esMovil
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            panelFotoEstado,
                            const SizedBox(height: 24),
                            panelDatos,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 1, child: panelFotoEstado),
                            const SizedBox(width: 40),
                            Expanded(flex: 2, child: panelDatos),
                          ],
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabContacto(bool esMovil) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildDatoItem(
                'Teléfono Móvil',
                widget.socio.telefono.isNotEmpty
                    ? widget.socio.telefono
                    : 'No registrado',
                Icons.phone,
              ),
              _buildDatoItem(
                'Contacto de Emergencia / Email',
                widget.socio.contactoEmergencia.isNotEmpty
                    ? widget.socio.contactoEmergencia
                    : 'Sin registrar',
                Icons.email_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabDeporteHorarios(bool esMovil) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildDatoItem(
                'Actividad Principal',
                widget.socio.deporte.isNotEmpty
                    ? widget.socio.deporte
                    : 'General',
                Icons.sports,
              ),
              _buildDatoItem(
                'Frecuencia',
                widget.socio.frecuencia.isNotEmpty
                    ? widget.socio.frecuencia
                    : 'Pase Libre',
                Icons.repeat,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildDatoItem(
                'Grado / Año Académico',
                (widget.socio.gradoAnio?.isNotEmpty ?? false)
                    ? widget.socio.gradoAnio!
                    : 'No aplica',
                Icons.school_outlined,
              ),
              _buildDatoItem(
                'Bloque Horario',
                _etiquetaHorarioTraduccion,
                Icons.schedule_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabGrupoFamiliar(bool esMovil) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: _buildSeccionGrupoFamiliar(),
    );
  }

  // 💸 Antes streameaba en vivo TODO el historial del socio sin límite
  // (StreamBuilder + .snapshots() sin .limit()) — para un socio con años de
  // antigüedad eso es una lectura que crece sin techo y se recarga con
  // cada apertura de la ficha. Ahora es una consulta puntual (.get()),
  // ordenada server-side y acotada a los últimos 100 ingresos, que ya
  // sobra para lo que esta pestaña necesita mostrar.
  Widget _buildTabHistorialAsistencias() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: FutureBuilder<QuerySnapshot>(
        future: _firestore
            .collection('asistencias_accesos')
            .where('socioId', isEqualTo: widget.socio.id)
            .orderBy('fechaHora', descending: true)
            .limit(100)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error al cargar asistencias: ${snapshot.error}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.teal),
            );
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'Sin asistencias registradas para este socio.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, idx) {
              final data = docs[idx].data() as Map<String, dynamic>;
              final DateTime fecha =
                  (data['fechaHora'] as Timestamp?)?.toDate() ?? DateTime.now();
              final bool esExcepcion = data['modo'] == 'EXCEPCION_MANUAL';

              return ListTile(
                dense: true,
                leading: Icon(
                  esExcepcion
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  color: esExcepcion ? Colors.orange : Colors.green,
                ),
                title: Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(fecha),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  esExcepcion
                      ? 'Excepción: ${data['motivoExcepcion'] ?? 'Bypass Admin'}'
                      : 'Ingreso Validado (Quedaban: ${data['creditosRestantes'] ?? 'Libre'})',
                  style: TextStyle(
                    color: esExcepcion ? Colors.orange.shade900 : Colors.grey,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }


  Widget _buildDatoItem(String e, String v, IconData i) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(e, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(i, size: 18, color: Colors.blueGrey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                v,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildEstadoFicha(
    String t,
    String v,
    Color c, {
    IconData? accionIcono,
    String? accionTooltip,
    VoidCallback? onAccion,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(t, style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
      Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              v,
              style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          if (onAccion != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(accionIcono, size: 18, color: Colors.blueGrey),
              tooltip: accionTooltip,
              visualDensity: VisualDensity.compact,
              onPressed: onAccion,
            ),
          ],
        ],
      ),
    ],
  );
}
