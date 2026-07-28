import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'socio_model.dart';

class SocioDetallePage extends StatelessWidget {
  final SocioModel socio;
  final VoidCallback onVolver;

  const SocioDetallePage({
    super.key,
    required this.socio,
    required this.onVolver,
  });

  Future<void> _abrirAptoMedico(BuildContext context) async {
    if (socio.aptoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este socio no cuenta con un documento de apto físico adjunto.',
          ),
        ),
      );
      return;
    }

    final Uri url = Uri.parse(socio.aptoUrl);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw 'No se pudo abrir la URL';
      }
    } catch (e) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Enlace del Apto Médico'),
          content: SelectableText(socio.aptoUrl),
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

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final bool aptoValido =
        socio.vencimientoAptoMedico != null &&
        socio.vencimientoAptoMedico!.isAfter(hoy);

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
                  onPressed: onVolver,
                ),
                const SizedBox(width: 16),
                Text(
                  'Ficha Detallada: ${socio.nombre}',
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
                    'N° ${socio.numeroSocio}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.blueGrey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (socio.esEstudianteEscuela) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.school,
                          size: 16,
                          color: Colors.amber.shade900,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Convenio Escolar (${socio.descuentoEscolarPorcentaje.toStringAsFixed(0)}% OFF)',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                            CircleAvatar(
                              radius: 75,
                              backgroundColor: Colors.teal.withValues(
                                alpha: 0.1,
                              ),
                              child: socio.fotoUrl.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(75),
                                      child: Image.network(
                                        socio.fotoUrl,
                                        width: 150,
                                        height: 150,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(
                                              Icons.person_rounded,
                                              size: 70,
                                              color: Colors.teal,
                                            ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.person_rounded,
                                      size: 70,
                                      color: Colors.teal,
                                    ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              socio.nombre,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'DNI ${socio.dni}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 16),

                            _buildEstadoFicha(
                              'Cuenta Corriente',
                              socio.saldoCuentaCorriente < 0
                                  ? 'Debe \$${socio.saldoCuentaCorriente.abs().toStringAsFixed(0)}'
                                  : 'Al día',
                              socio.saldoCuentaCorriente < 0
                                  ? Colors.red
                                  : Colors.green,
                            ),
                            const SizedBox(height: 16),

                            _buildEstadoFicha(
                              'Control Médico',
                              aptoValido ? 'Apto Vigente' : 'APTO VENCIDO',
                              aptoValido ? Colors.green : Colors.red,
                            ),
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
                          _buildSeccionTitulo(
                            'Información Personal y Contacto',
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              _buildDatoItem(
                                'Teléfono Móvil',
                                socio.telefono,
                                Icons.phone_rounded,
                              ),
                              _buildDatoItem(
                                'Fecha de Nacimiento',
                                socio.fechaNacimiento != null
                                    ? DateFormat(
                                        'dd/MM/yyyy',
                                      ).format(socio.fechaNacimiento!)
                                    : 'No registrada',
                                Icons.cake_rounded,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              _buildDatoItem(
                                'Fecha de Alta en Club',
                                DateFormat(
                                  'dd/MM/yyyy',
                                ).format(socio.fechaAlta),
                                Icons.calendar_today_rounded,
                              ),
                              _buildDatoItem(
                                'Estado del Socio',
                                socio.activo ? 'Activo' : 'Inactivo',
                                Icons.gpp_good_rounded,
                              ),
                            ],
                          ),

                          if (socio.esEstudianteEscuela) ...[
                            const SizedBox(height: 32),
                            const Divider(),
                            const SizedBox(height: 16),
                            _buildSeccionTitulo(
                              'Convenio Escolar y Bonificación',
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                _buildDatoItem(
                                  'Institución / Colegio',
                                  socio.colegioInstitucion ?? 'No especificada',
                                  Icons.school_rounded,
                                ),
                                _buildDatoItem(
                                  'Grado / Año',
                                  socio.gradoAnio ?? 'No especificado',
                                  Icons.class_rounded,
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                _buildDatoItem(
                                  'Descuento Aplicado',
                                  '${socio.descuentoEscolarPorcentaje.toStringAsFixed(0)}% sobre tarifa base',
                                  Icons.percent_rounded,
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 32),
                          const Divider(),
                          const SizedBox(height: 16),

                          _buildSeccionTitulo('Área de Emergencias y Salud'),
                          const SizedBox(height: 20),

                          Row(
                            children: [
                              _buildDatoItem(
                                'Contacto de Emergencia',
                                socio.contactoEmergencia.isEmpty
                                    ? 'No provisto'
                                    : socio.contactoEmergencia,
                                Icons.heart_broken_rounded,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _buildDatoItem(
                                'Vencimiento de Certificado',
                                socio.vencimientoAptoMedico != null
                                    ? DateFormat(
                                        'dd/MM/yyyy',
                                      ).format(socio.vencimientoAptoMedico!)
                                    : 'No registrado',
                                Icons.shield_rounded,
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal.shade700,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.picture_as_pdf_rounded,
                                    ),
                                    label: const Text(
                                      'Ver Documento Adjunto',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed: () => _abrirAptoMedico(context),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 32),
                          const Divider(),
                          const SizedBox(height: 16),

                          _buildSeccionTitulo(
                            'Inscripción y Distribución Horaria',
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              _buildDatoItem(
                                'Actividad / Deporte',
                                socio.deporte,
                                Icons.sports_rounded,
                              ),
                              _buildDatoItem(
                                'Frecuencia Semanal',
                                socio.frecuencia,
                                Icons.loop_rounded,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          Row(
                            children: [
                              _buildDatoItem(
                                'Días Asignados',
                                socio.dias.isEmpty
                                    ? 'Ninguno seleccionado'
                                    : socio.dias.join(' - '),
                                Icons.calendar_month_rounded,
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

  Widget _buildSeccionTitulo(String titulo) {
    return Text(
      titulo,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.blueAccent,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildDatoItem(String etiqueta, String valor, IconData icono) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiqueta,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(icono, size: 18, color: Colors.blueGrey.shade400),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoFicha(String titulo, String valor, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              valor,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
