import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ControlAccesoPage extends StatefulWidget {
  final String rolUsuario;

  const ControlAccesoPage({super.key, required this.rolUsuario});

  @override
  State<ControlAccesoPage> createState() => _ControlAccesoPageState();
}

class _ControlAccesoPageState extends State<ControlAccesoPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _busquedaController = TextEditingController();
  final FocusNode _lectorFocusNode = FocusNode();

  Map<String, dynamic>? _socioEncontrado;
  String? _socioIdEncontrado;
  bool _buscando = false;

  // Estados de autorización
  bool _cuotaAlDia = false;
  bool _aptoMedicoVigente = false;
  bool _matriculaAlDia = false;
  bool _estadoHabilitado = false;
  double _saldoCuentaCorriente = 0.0;

  // Control de Clases del Mes Calendario
  String _frecuenciaPase = 'Pase Libre';
  int _limiteClasesMes = 999;
  int _clasesUsadasMes = 0;
  int _creditosRestantes = 999;
  bool _tieneCreditoDisponible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lectorFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _lectorFocusNode.dispose();
    _busquedaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text(
          'Control de Acceso & Recepción Híbrida',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: KeyboardListener(
        focusNode: _lectorFocusNode,
        onKeyEvent: (event) {
          if (!_lectorFocusNode.hasFocus) {
            _busquedaController.selection = TextSelection.fromPosition(
              TextPosition(offset: _busquedaController.text.length),
            );
            _lectorFocusNode.requestFocus();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    _buildTarjetaLector(),
                    const SizedBox(height: 20),
                    Expanded(
                      child: _socioEncontrado == null
                          ? _buildEstadoInicialLector()
                          : _buildFichaValidacionSocio(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(flex: 4, child: _buildMonitorIngresosHoy()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTarjetaLector() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.fingerprint_rounded, size: 36, color: Colors.cyan),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: _busquedaController,
              autofocus: true,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: 'Escanee Huella DigitalPersona, QR o DNI...',
                border: InputBorder.none,
              ),
              onSubmitted: (val) => _procesarEntradaLector(val),
            ),
          ),
          if (_buscando)
            const CircularProgressIndicator()
          else
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => _procesarEntradaLector(_busquedaController.text),
              icon: const Icon(Icons.search, color: Colors.white),
              label: const Text(
                'Validar',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEstadoInicialLector() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.badge_outlined, size: 80, color: Colors.teal),
          SizedBox(height: 16),
          Text(
            'Esperando lectura de credencial o huella...',
            style: TextStyle(
              fontSize: 18,
              color: Colors.blueGrey,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Lector unificado: Valida socios y fichaje de profesores.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildFichaValidacionSocio() {
    final String nombre =
        '${_socioEncontrado!['nombre'] ?? ''} ${_socioEncontrado!['apellido'] ?? ''}'
            .trim();
    final String dni = _socioEncontrado!['dni'] ?? '-';
    final String fotoUrl = _socioEncontrado!['fotoUrl'] ?? '';

    Color colorEstado = _estadoHabilitado ? Colors.green : Colors.red;
    String textoEstado = _estadoHabilitado
        ? 'ACCESO HABILITADO'
        : 'ACCESO DENEGADO';

    String detalleCuota = _cuotaAlDia
        ? 'Al Día'
        : 'Deuda: \$${_saldoCuentaCorriente.abs().toStringAsFixed(0)}';

    String detalleCredito = _limiteClasesMes == 999
        ? 'Pase Libre'
        : 'Quedan $_creditosRestantes de $_limiteClasesMes clases';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorEstado, width: 2.5),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: colorEstado.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              textoEstado,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: colorEstado,
              ),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              CircleAvatar(
                radius: 45,
                backgroundColor: Colors.teal.shade200,
                backgroundImage: fotoUrl.isNotEmpty
                    ? NetworkImage(fotoUrl)
                    : null,
                child: fotoUrl.isEmpty
                    ? const Icon(Icons.person, size: 45, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'DNI: $dni',
                      style: const TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                    Text(
                      'Programa: ${_socioEncontrado!['deporte'] ?? 'General'} ($_frecuenciaPase)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.teal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 28),

          Row(
            children: [
              _buildItemRegla('Estado Financiero', _cuotaAlDia, detalleCuota),
              const SizedBox(width: 8),
              _buildItemRegla(
                'Apto Médico',
                _aptoMedicoVigente,
                _aptoMedicoVigente ? 'Vigente' : 'Vencido',
              ),
              const SizedBox(width: 8),
              _buildItemRegla(
                'Crédito Clases',
                _tieneCreditoDisponible,
                detalleCredito,
              ),
              const SizedBox(width: 8),
              _buildItemRegla(
                'Matrícula',
                _matriculaAlDia,
                _matriculaAlDia ? 'Al Día' : 'Pendiente',
              ),
            ],
          ),
          const Spacer(),

          Row(
            children: [
              if (_estadoHabilitado)
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _registrarIngreso(
                      modo: 'AUTOMATICO',
                      motivoExcepcion: '',
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 24),
                    label: const Text(
                      'REGISTRAR INGRESO Y DESCONTAR CLASE',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: OutlinedButton.icon(
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.orange.shade800,
                      side: BorderSide(color: Colors.orange.shade800, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _solicitarBypassManual(context),
                    icon: const Icon(
                      Icons.published_with_changes_rounded,
                      size: 24,
                    ),
                    label: const Text(
                      'AUTORIZAR EXCEPCIÓN MANUAL (ADMIN)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemRegla(String titulo, bool cumple, String detalle) {
    Color color = cumple ? Colors.green : Colors.red;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(
              cumple ? Icons.check_circle : Icons.cancel,
              color: color,
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    detalle,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitorIngresosHoy() {
    final DateTime hoy = DateTime.now();
    final String hoyStr =
        "${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}";

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Monitor Acceso en Vivo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Chip(
                  label: Text(DateFormat('dd/MM/yyyy').format(hoy)),
                  backgroundColor: const Color(0xFFF1F5F9),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('asistencias_accesos')
                    .where('fechaStr', isEqualTo: hoyStr)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs;

                  if (docs.isEmpty) {
                    return const Center(
                      child: Text('Sin ingresos registrados en el día de hoy.'),
                    );
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 12),
                    itemBuilder: (context, idx) {
                      final data = docs[idx].data() as Map<String, dynamic>;
                      final DateTime hora = (data['fechaHora'] as Timestamp)
                          .toDate();
                      final bool esExcepcion =
                          data['modo'] == 'EXCEPCION_MANUAL';
                      final bool esProfesor = data['tipoEntidad'] == 'Profesor';

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: esProfesor
                              ? Colors.purple.shade100
                              : (esExcepcion
                                    ? Colors.orange.shade100
                                    : Colors.green.shade100),
                          child: Icon(
                            esProfesor
                                ? Icons.badge
                                : (esExcepcion
                                      ? Icons.warning_rounded
                                      : Icons.check_rounded),
                            color: esProfesor
                                ? Colors.purple.shade900
                                : (esExcepcion
                                      ? Colors.orange.shade900
                                      : Colors.green.shade900),
                            size: 20,
                          ),
                        ),
                        title: Text(
                          data['nombreSocio'] ?? 'Usuario',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          esProfesor
                              ? 'Fichaje Docente (${data['tipoFichajeProfe'] ?? 'Ingreso'})'
                              : (esExcepcion
                                    ? 'Excepción: ${data['motivoExcepcion']}'
                                    : 'Acceso OK • Quedan: ${data['creditosRestantes'] ?? 'Libre'}'),
                          style: TextStyle(
                            color: esProfesor
                                ? Colors.purple.shade800
                                : (esExcepcion
                                      ? Colors.orange.shade800
                                      : Colors.grey),
                          ),
                        ),
                        trailing: Text(
                          DateFormat('HH:mm:ss').format(hora),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _procesarEntradaLector(String query) async {
    final String codigoLeido = query.trim();
    if (codigoLeido.isEmpty) return;
    setState(() => _buscando = true);

    try {
      final profeSnap = await _firestore
          .collection('profesores')
          .where('dni', isEqualTo: codigoLeido)
          .limit(1)
          .get();

      if (profeSnap.docs.isNotEmpty) {
        final docProfe = profeSnap.docs.first;
        final dataProfe = docProfe.data();
        await _ficharProfesor(docProfe.id, dataProfe['nombre'] ?? 'Profesor');
        return;
      }

      var snapSocio = await _firestore
          .collection('socios')
          .where('dni', isEqualTo: codigoLeido)
          .limit(1)
          .get();

      if (snapSocio.docs.isEmpty) {
        snapSocio = await _firestore
            .collection('socios')
            .where('huellaHash', isEqualTo: codigoLeido)
            .limit(1)
            .get();
      }

      if (snapSocio.docs.isNotEmpty) {
        final doc = snapSocio.docs.first;
        final data = doc.data();
        final String socioId = doc.id;

        final hoy = DateTime.now();
        final periodoActualStr =
            "${hoy.year}-${hoy.month.toString().padLeft(2, '0')}";

        // 🌟 EVALUACIÓN DE COBERTURA MULTIMES / PROMOCIÓN
        final String? cubiertoHasta = data['mesesCubiertosHasta']?.toString();
        bool promoVigente = false;
        if (cubiertoHasta != null &&
            cubiertoHasta.compareTo(periodoActualStr) >= 0) {
          promoVigente = true;
        }

        final double saldo = (data['saldoCuentaCorriente'] ?? 0.0).toDouble();
        bool cuota =
            saldo >= 0 || promoVigente; // 👈 Habilitado si promo está activa
        bool matricula = data['matriculaAlDia'] == true;

        bool apto = false;
        if (data['vencimientoAptoMedico'] != null) {
          DateTime vencApto = (data['vencimientoAptoMedico'] as Timestamp)
              .toDate();
          apto = vencApto.isAfter(hoy);
        }

        final String frecuenciaRaw = (data['frecuencia'] ?? 'Pase Libre')
            .toString()
            .toLowerCase();
        int limite = 999;

        if (frecuenciaRaw.contains('1') || frecuenciaRaw.contains('una')) {
          limite = 4;
        } else if (frecuenciaRaw.contains('2') ||
            frecuenciaRaw.contains('dos')) {
          limite = 8;
        } else if (frecuenciaRaw.contains('3') ||
            frecuenciaRaw.contains('tres')) {
          limite = 12;
        } else if (frecuenciaRaw.contains('4') ||
            frecuenciaRaw.contains('cuatro')) {
          limite = 16;
        } else if (frecuenciaRaw.contains('libre')) {
          limite = 999;
        }

        final docCreditoRef = _firestore
            .collection('socios')
            .doc(socioId)
            .collection('creditos_mensuales')
            .doc(periodoActualStr);

        final docCredito = await docCreditoRef.get();
        int usadas = 0;

        if (!docCredito.exists) {
          await docCreditoRef.set({
            'periodo': periodoActualStr,
            'clasesUsadas': 0,
            'limiteClases': limite,
            'fechaInicio': DateTime.now(),
          });
        } else {
          usadas = (docCredito.data()?['clasesUsadas'] as num?)?.toInt() ?? 0;
        }

        int restantes = limite == 999 ? 999 : (limite - usadas);
        bool tieneCredito = limite == 999 || restantes > 0;
        bool accesoPermitido = cuota && apto && tieneCredito;

        setState(() {
          _socioIdEncontrado = socioId;
          _socioEncontrado = data;
          _saldoCuentaCorriente = saldo;
          _cuotaAlDia = cuota;
          _matriculaAlDia = matricula;
          _aptoMedicoVigente = apto;
          _frecuenciaPase = data['frecuencia'] ?? 'Pase Libre';
          _limiteClasesMes = limite;
          _clasesUsadasMes = usadas;
          _creditosRestantes = restantes;
          _tieneCreditoDisponible = tieneCredito;
          _estadoHabilitado = accesoPermitido;
        });
      } else {
        _ofrecerEnrolamientoHuella(codigoLeido);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al procesar lectura: $e')));
    } finally {
      setState(() => _buscando = false);
    }
  }

  Future<void> _ficharProfesor(String profesorId, String nombreProfesor) async {
    final hoy = DateTime.now();
    final inicioHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final String hoyStr =
        "${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}";

    final queryAbierto = await _firestore
        .collection('asistencia')
        .where('profesorId', isEqualTo: profesorId)
        .where('fecha', isGreaterThanOrEqualTo: inicioHoy)
        .where('tipo', isEqualTo: 'Entrada')
        .get();

    String tipoFichaje = 'Entrada';
    if (queryAbierto.docs.isNotEmpty) {
      tipoFichaje = 'Salida';
    }

    final idRegistro = "${hoyStr}_${profesorId}_$tipoFichaje";

    await _firestore.collection('asistencia').doc(idRegistro).set({
      'profesorId': profesorId,
      'nombreProfesor': nombreProfesor,
      'fecha': Timestamp.fromDate(hoy),
      'tipo': tipoFichaje,
      'hora':
          "${hoy.hour.toString().padLeft(2, '0')}:${hoy.minute.toString().padLeft(2, '0')}",
    });

    await _firestore.collection('asistencias_accesos').add({
      'socioId': profesorId,
      'nombreSocio': '[DOCENTE] $nombreProfesor',
      'fechaHora': Timestamp.fromDate(hoy),
      'fechaStr': hoyStr,
      'modo': 'DOCENTE',
      'tipoEntidad': 'Profesor',
      'tipoFichajeProfe': tipoFichaje,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ $tipoFichaje registrada para $nombreProfesor'),
        backgroundColor: Colors.purple.shade800,
      ),
    );

    _busquedaController.clear();
    setState(() => _socioEncontrado = null);
  }

  void _ofrecerEnrolamientoHuella(String huellaHashCapturada) {
    final TextEditingController filtroSocioCtrl = TextEditingController();
    Map<String, dynamic>? socioSeleccionado;
    String? socioIdSeleccionado;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.fingerprint_rounded, color: Colors.orange, size: 28),
                SizedBox(width: 10),
                Text('Huella DigitalPersona no vinculada'),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'La huella leída no está asignada a ningún socio. ¿Deseas vincularla?',
                    style: TextStyle(color: Colors.blueGrey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: filtroSocioCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Buscar por N° de DNI...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) async {
                      if (val.trim().length >= 3) {
                        final res = await _firestore
                            .collection('socios')
                            .where('dni', isEqualTo: val.trim())
                            .limit(1)
                            .get();

                        if (res.docs.isNotEmpty) {
                          setDialogState(() {
                            socioIdSeleccionado = res.docs.first.id;
                            socioSeleccionado = res.docs.first.data();
                          });
                        } else {
                          setDialogState(() {
                            socioIdSeleccionado = null;
                            socioSeleccionado = null;
                          });
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  if (socioSeleccionado != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.teal),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${socioSeleccionado!['nombre']} ${socioSeleccionado!['apellido'] ?? ''}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text('DNI: ${socioSeleccionado!['dni']}'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _busquedaController.clear();
                },
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                onPressed: socioIdSeleccionado == null
                    ? null
                    : () async {
                        await _firestore
                            .collection('socios')
                            .doc(socioIdSeleccionado)
                            .update({
                              'huellaHash': huellaHashCapturada,
                              'fechaEnrolamientoHuella':
                                  FieldValue.serverTimestamp(),
                            });

                        if (mounted) {
                          Navigator.pop(dialogCtx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('¡Huella vinculada con éxito!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _procesarEntradaLector(huellaHashCapturada);
                        }
                      },
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Vincular y Procesar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _registrarIngreso({
    required String modo,
    required String motivoExcepcion,
  }) async {
    if (_socioEncontrado == null) return;

    final DateTime ahora = DateTime.now();
    final String hoyStr =
        "${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}";
    final String periodoClave =
        "${ahora.year}-${ahora.month.toString().padLeft(2, '0')}";

    if (_limiteClasesMes != 999 && modo == 'AUTOMATICO') {
      final docCreditoRef = _firestore
          .collection('socios')
          .doc(_socioIdEncontrado!)
          .collection('creditos_mensuales')
          .doc(periodoClave);

      await docCreditoRef.update({'clasesUsadas': FieldValue.increment(1)});
    }

    await _firestore.collection('asistencias_accesos').add({
      'socioId': _socioIdEncontrado,
      'nombreSocio':
          '${_socioEncontrado!['nombre']} ${_socioEncontrado!['apellido'] ?? ''}'
              .trim(),
      'dniSocio': _socioEncontrado!['dni'],
      'fechaHora': Timestamp.fromDate(ahora),
      'fechaStr': hoyStr,
      'modo': modo,
      'motivoExcepcion': motivoExcepcion,
      'creditosRestantes': _limiteClasesMes == 999
          ? 'Libre'
          : '${_creditosRestantes - 1}/$_limiteClasesMes',
      'operador': widget.rolUsuario,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Ingreso asentado para ${_socioEncontrado!['nombre']}'),
        backgroundColor: Colors.green,
      ),
    );

    setState(() {
      _socioEncontrado = null;
      _busquedaController.clear();
    });
  }

  void _solicitarBypassManual(BuildContext context) {
    final TextEditingController motivoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Autorización de Excepción Manual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Autorizar ingreso excepcional para socio no habilitado.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(
                labelText: 'Motivo de la excepción',
                hintText: 'Ej: Regularizó recién / Apto en trámite',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (motivoCtrl.text.trim().isEmpty) return;
              Navigator.pop(dialogCtx);
              _registrarIngreso(
                modo: 'EXCEPCION_MANUAL',
                motivoExcepcion: motivoCtrl.text.trim(),
              );
            },
            child: const Text('Autorizar e Ingresar'),
          ),
        ],
      ),
    );
  }
}
