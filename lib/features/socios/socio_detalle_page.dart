import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
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
  String _etiquetaHorarioTraduccion = 'Cargando horario...';

  @override
  void initState() {
    super.initState();
    _obtenerTraduccionHorario();
  }

  Future<void> _obtenerTraduccionHorario() async {
    final String bloqueId = widget.socio.idBloqueHorario;
    if (bloqueId.isEmpty) {
      if (mounted)
        setState(() => _etiquetaHorarioTraduccion = 'Sin horario asignado');
      return;
    }

    try {
      final docHorarios = await FirebaseFirestore.instance
          .collection('configuracion')
          .doc('horarios')
          .get();

      if (docHorarios.exists && docHorarios.data() != null) {
        final data = docHorarios.data()!;
        final bloques = data['bloques'] as List<dynamic>? ?? [];

        for (var b in bloques) {
          if (b['id'] == bloqueId) {
            final desde = b['horaDesde'] ?? '';
            final hasta = b['horaHasta'] ?? '';
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
      if (mounted) {
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
      await FirebaseFirestore.instance
          .collection('socios')
          .doc(widget.socio.id)
          .update({
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

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final bool aptoValido =
        widget.socio.vencimientoAptoMedico != null &&
        widget.socio.vencimientoAptoMedico!.isAfter(hoy);
    final bool tieneHuellaDigital = widget.socio.huellaHash.isNotEmpty;

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
                  'Ficha Detallada: ${widget.socio.nombre}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          children: [
                            // 📸 FOTO CON CONTROL DE CARGA Y FALLBACK
                            CircleAvatar(
                              radius: 75,
                              backgroundColor: Colors.teal.withOpacity(0.1),
                              child: widget.socio.fotoUrl.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(75),
                                      child: Image.network(
                                        widget.socio.fotoUrl,
                                        width: 150,
                                        height: 150,
                                        fit: BoxFit.cover,
                                        loadingBuilder: (context, child, progress) {
                                          if (progress == null) return child;
                                          return const CircularProgressIndicator(
                                            color: Colors.teal,
                                          );
                                        },
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(
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
                              widget.socio.matriculaAlDia
                                  ? Colors.green
                                  : Colors.red,
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

                            if (!widget.socio.matriculaAlDia) ...[
                              const SizedBox(height: 20),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.amber.shade900,
                                  side: BorderSide(
                                    color: Colors.amber.shade400,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.history_toggle_off_rounded,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Indicar Pago Previo Matrícula',
                                ),
                                onPressed: _registrarMatriculaPrevio,
                              ),
                            ],
                          ],
                        ),
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
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSeccionTitulo('Contacto & Datos Personales'),
                          const SizedBox(height: 20),
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
                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),

                          _buildSeccionTitulo('Deporte & Horarios'),
                          const SizedBox(height: 20),
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
                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),

                          _buildSeccionTitulo('Control Médico & Biometría'),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              _buildDatoItem(
                                'Vencimiento Apto Médico',
                                widget.socio.vencimientoAptoMedico != null
                                    ? DateFormat('dd/MM/yyyy').format(
                                        widget.socio.vencimientoAptoMedico!,
                                      )
                                    : 'No cargado',
                                Icons.medical_services_outlined,
                              ),
                              _buildDatoItem(
                                'Huella Digital',
                                tieneHuellaDigital
                                    ? 'Enrolada ✅'
                                    : 'Pendiente de Lectura ⚠️',
                                Icons.fingerprint_rounded,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0A3B43),
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(
                                      Icons.file_present_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Ver Adjunto Apto Físico',
                                    ),
                                    onPressed: () => _abrirAptoMedico(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionTitulo(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Color(0xFF0A3B43),
    ),
  );

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

  Widget _buildEstadoFicha(String t, String v, Color c) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(t, style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
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
    ],
  );
}
