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

  Map<String, dynamic>? _socioEncontrado;
  String? _socioIdEncontrado;
  bool _buscando = false;

  // Modales y estados de autorización
  bool _cuotaAlDia = false;
  bool _aptoMedicoVigente = false;
  bool _estadoHabilitado = false;
  double _saldoCuentaCorriente = 0.0;

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
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔍 PANEL IZQUIERDO: BÚSQUEDA / LECTOR Y VALIDACIÓN
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

            // 📋 PANEL DERECHO: MONITOR DE INGRESOS EN TIEMPO REAL (HISTORIAL DEL DÍA)
            Expanded(flex: 4, child: _buildMonitorIngresosHoy()),
          ],
        ),
      ),
    );
  }

  // 📡 CARD 1: INPUT DE ENTRADA (HUELLA / LECTOR / DNI)
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
                hintText: 'Escanee Huella, QR o ingrese N° DNI / Socio...',
                border: InputBorder.none,
              ),
              onSubmitted: (val) => _buscarSocio(val),
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
              onPressed: () => _buscarSocio(_busquedaController.text),
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
            'Pase la tarjeta o ingrese el DNI del socio para verificar estado.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // 🎴 FICHA COMPLETA DE VALIDACIÓN CON SEMÁFORO Y DETALLE DE SALDO
  Widget _buildFichaValidacionSocio() {
    final String nombre =
        '${_socioEncontrado!['nombre'] ?? ''} ${_socioEncontrado!['apellido'] ?? ''}';
    final String dni = _socioEncontrado!['dni'] ?? '-';
    final String fotoUrl = _socioEncontrado!['fotoUrl'] ?? '';

    Color colorEstado = _estadoHabilitado ? Colors.green : Colors.red;
    String textoEstado = _estadoHabilitado
        ? 'ACCESO HABILITADO'
        : 'ACCESO DENEGADO';

    // Formateo del estado de cuota
    String detalleCuota = _cuotaAlDia
        ? 'Al Día (\$${_saldoCuentaCorriente.toStringAsFixed(0)})'
        : 'Deuda: \$${_saldoCuentaCorriente.abs().toStringAsFixed(0)}';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorEstado, width: 2.5),
      ),
      child: Column(
        children: [
          // CABECERA DEL SEMÁFORO
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

          // FOTO Y DATOS PERSONALES
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
                      'Actividad: ${_socioEncontrado!['deporte'] ?? 'General'}',
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
          const Divider(height: 32),

          // GRILLA DE CHEQUEO TÉCNICO (CON SALDO EN CUENTA CORRIENTE)
          Row(
            children: [
              _buildItemRegla('Estado Financiero', _cuotaAlDia, detalleCuota),
              const SizedBox(width: 16),
              _buildItemRegla(
                'Apto Médico',
                _aptoMedicoVigente,
                _aptoMedicoVigente ? 'Vigente' : 'Vencido / Sin Apto',
              ),
            ],
          ),
          const Spacer(),

          // BOTONES DE ACCIÓN (MARCACIÓN AUTOMÁTICA O BYPASS MANUAL)
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
                      'REGISTRAR INGRESO',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
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
        padding: const EdgeInsets.all(12),
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
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    detalle,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
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

  // 📺 MONITOR DERECHO: HISTORIAL EN TIEMPO REAL
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
                  'Ingresos de Hoy',
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
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
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

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: esExcepcion
                              ? Colors.orange.shade100
                              : Colors.green.shade100,
                          child: Icon(
                            esExcepcion
                                ? Icons.warning_rounded
                                : Icons.check_rounded,
                            color: esExcepcion
                                ? Colors.orange.shade900
                                : Colors.green.shade900,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          data['nombreSocio'] ?? 'Socio',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          esExcepcion
                              ? 'Excepción: ${data['motivoExcepcion']}'
                              : 'Validación Automática',
                          style: TextStyle(
                            color: esExcepcion
                                ? Colors.orange.shade800
                                : Colors.grey,
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

  // 🔍 LÓGICA DE BÚSQUEDA Y EVALUACIÓN DE REGLAS (ADAPTADA A SOCIO_MODEL)
  Future<void> _buscarSocio(String query) async {
    final String codigoLeido = query.trim();
    if (codigoLeido.isEmpty) return;
    setState(() => _buscando = true);

    try {
      // 1. Buscar por DNI
      var snap = await _firestore
          .collection('socios')
          .where('dni', isEqualTo: codigoLeido)
          .limit(1)
          .get();

      // 2. Si no es DNI, buscar por Hash Biométrico de la huella
      if (snap.docs.isEmpty) {
        snap = await _firestore
            .collection('socios')
            .where('huellaHash', isEqualTo: codigoLeido)
            .limit(1)
            .get();
      }

      if (snap.docs.isNotEmpty) {
        final doc = snap.docs.first;
        final data = doc.data();

        // 💵 EVALUACIÓN DE CUOTA: Usa saldoCuentaCorriente (>= 0 es al día)
        final double saldo = (data['saldoCuentaCorriente'] ?? 0.0).toDouble();
        bool cuota = saldo >= 0;

        // 🏥 EVALUACIÓN DE APTO MÉDICO: Usa vencimientoAptoMedico
        bool apto = false;
        if (data['vencimientoAptoMedico'] != null) {
          DateTime vencApto = (data['vencimientoAptoMedico'] as Timestamp)
              .toDate();
          apto = vencApto.isAfter(DateTime.now());
        }

        setState(() {
          _socioIdEncontrado = doc.id;
          _socioEncontrado = data;
          _saldoCuentaCorriente = saldo;
          _cuotaAlDia = cuota;
          _aptoMedicoVigente = apto;
          _estadoHabilitado = cuota && apto;
        });
      } else {
        // 🟡 NO HUBO COINCIDENCIA -> OFRECER VINCULAR HUELLA
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

  // 🖐️ DIÁLOGO DE ENROLAMIENTO EN CALIENTE
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
                Text('Huella no reconocida'),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'La huella o código leído no está asignado a ningún socio. ¿Deseas vincularlo ahora a la ficha de un socio existente?',
                    style: TextStyle(color: Colors.blueGrey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: filtroSocioCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Buscar Socio por N° de DNI...',
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
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.teal,
                          ),
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
                child: const Text('Cancelar / Ignorar'),
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
                              content: Text(
                                '¡Huella vinculada con éxito a ${socioSeleccionado!['nombre']}!',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _buscarSocio(huellaHashCapturada);
                        }
                      },
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Vincular y Dar Ingreso'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ✍️ REGISTRO DE ASISTENCIA
  Future<void> _registrarIngreso({
    required String modo,
    required String motivoExcepcion,
  }) async {
    if (_socioEncontrado == null) return;

    final DateTime ahora = DateTime.now();
    final String hoyStr =
        "${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}";

    await _firestore.collection('asistencias_accesos').add({
      'socioId': _socioIdEncontrado,
      'nombreSocio':
          '${_socioEncontrado!['nombre']} ${_socioEncontrado!['apellido'] ?? ''}',
      'dniSocio': _socioEncontrado!['dni'],
      'fechaHora': Timestamp.fromDate(ahora),
      'fechaStr': hoyStr,
      'modo': modo,
      'motivoExcepcion': motivoExcepcion,
      'operador': widget.rolUsuario,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Ingreso registrado correctamente para ${_socioEncontrado!['nombre']}',
        ),
        backgroundColor: Colors.green,
      ),
    );

    // Limpiar pantalla para la siguiente lectura
    setState(() {
      _socioEncontrado = null;
      _busquedaController.clear();
    });
  }

  // 🔓 DIÁLOGO DE BYPASS MANUAL
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
              'Está por autorizar el ingreso a un socio no habilitado por reglas automáticas.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(
                labelText: 'Motivo de la excepción (Obligatorio)',
                hintText:
                    'Ej: Trajo certificado físico / Pagó en efectivo recién',
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
