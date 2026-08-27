import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'socio_model.dart';
import '../cuentas_corrientes/cuenta_corriente_page.dart';
import '../../pages/plan_pago_dialog.dart';

class SociosPage extends StatefulWidget {
  final String rolUsuario;
  final VoidCallback onNuevoSocio;
  final Function(SocioModel) onVerSocio;
  final Function(SocioModel) onEditarSocio;

  const SociosPage({
    super.key,
    required this.rolUsuario,
    required this.onNuevoSocio,
    required this.onVerSocio,
    required this.onEditarSocio,
  });

  @override
  State<SociosPage> createState() => _SociosPageState();
}

class _SociosPageState extends State<SociosPage> {
  String _terminoBusqueda = "";

  void _abrirRefinanciacionSocio(SocioModel socio) async {
    final res = await showDialog(
      context: context,
      builder: (context) => PlanPagoDialog(socio: socio),
    );
    if (res == true) {
      setState(() {}); // Actualiza la lista si se formalizó un plan
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool esAdmin = widget.rolUsuario == 'admin';

    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // CABECERA: TÍTULO Y BOTÓN DE ALTA
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Gestión de Socios',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    'Buscá, administrá y revisá las cuentas de tus clientes.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
              if (esAdmin)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'Nuevo Socio',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: widget.onNuevoSocio,
                ),
            ],
          ),
          const SizedBox(height: 30),

          // BARRA DE BÚSQUEDA
          TextField(
            decoration: InputDecoration(
              hintText: 'Buscar por Nombre, DNI o Número de Socio...',
              prefixIcon: const Icon(Icons.search, color: Colors.blueGrey),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (valor) {
              setState(() {
                _terminoBusqueda = valor.toLowerCase();
              });
            },
          ),
          const SizedBox(height: 20),

          // LISTA DE SOCIOS (STREAMBUILDER)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('socios')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('Aún no hay socios registrados.'),
                  );
                }

                final sociosFiltrados = snapshot.data!.docs
                    .map((doc) => SocioModel.fromFirestore(doc))
                    .where((socio) {
                      return socio.nombre.toLowerCase().contains(
                            _terminoBusqueda,
                          ) ||
                          socio.dni.toLowerCase().contains(_terminoBusqueda) ||
                          socio.numeroSocio.toLowerCase().contains(
                            _terminoBusqueda,
                          );
                    })
                    .toList();

                if (sociosFiltrados.isEmpty) {
                  return const Center(
                    child: Text('No se encontraron socios con esa búsqueda.'),
                  );
                }

                return ListView.builder(
                  itemCount: sociosFiltrados.length,
                  itemBuilder: (context, index) {
                    final socio = sociosFiltrados[index];
                    final hoy = DateTime.now();
                    final bool aptoValido =
                        socio.vencimientoAptoMedico != null &&
                        socio.vencimientoAptoMedico!.isAfter(hoy);

                    // Valida si el socio posee alguna deuda pendiente
                    final bool tieneDeuda = socio.saldoCuentaCorriente != 0;

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.teal.withOpacity(0.1),
                          child: socio.fotoUrl.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: Image.network(
                                    socio.fotoUrl,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(
                                              Icons.person,
                                              color: Colors.teal,
                                            ),
                                  ),
                                )
                              : const Icon(Icons.person, color: Colors.teal),
                        ),
                        title: Row(
                          children: [
                            Text(
                              socio.nombre,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'N° ${socio.numeroSocio}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.blueGrey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (socio.esEstudianteEscuela) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  border: Border.all(
                                    color: Colors.amber.shade200,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '🏫 Dto. Escolar ${socio.descuentoEscolarPorcentaje.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Text('${socio.deporte} • DNI: ${socio.dni}'),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.favorite,
                                    size: 14,
                                    color: aptoValido
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    aptoValido
                                        ? 'Apto Médico al día'
                                        : 'APTO VENCIDO',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: aptoValido
                                          ? Colors.green.shade700
                                          : Colors.red.shade700,
                                      fontWeight: aptoValido
                                          ? FontWeight.normal
                                          : FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.badge_outlined,
                                    size: 14,
                                    color: socio.matriculaAlDia
                                        ? Colors.green
                                        : Colors.orange.shade800,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    socio.matriculaAlDia
                                        ? 'Matrícula Al Día (${socio.fechaPagoMatricula != null ? DateFormat('dd/MM/yy').format(socio.fechaPagoMatricula!) : 'OK'})'
                                        : 'MATRÍCULA PENDIENTE',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: socio.matriculaAlDia
                                          ? Colors.green.shade800
                                          : Colors.orange.shade900,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.event_available,
                                    size: 14,
                                    color: Colors.indigo,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Último pago: ${socio.ultimoMesPago}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.indigo,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: tieneDeuda
                                    ? Colors.red.withOpacity(0.1)
                                    : Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                tieneDeuda
                                    ? 'Debe \$${socio.saldoCuentaCorriente.abs().toStringAsFixed(0)}'
                                    : 'Al día',
                                style: TextStyle(
                                  color: tieneDeuda ? Colors.red : Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // 🤝 BOTÓN REFINANCIACIÓN (SOLO SI TIENE DEUDA)
                            if (tieneDeuda)
                              IconButton(
                                icon: const Icon(
                                  Icons.handshake_outlined,
                                  color: Colors.orange,
                                  size: 24,
                                ),
                                tooltip: 'Refinanciar Deuda (Plan de Pagos)',
                                onPressed: () =>
                                    _abrirRefinanciacionSocio(socio),
                              ),

                            IconButton(
                              icon: const Icon(
                                Icons.visibility_rounded,
                                color: Colors.teal,
                              ),
                              tooltip: 'Ver Ficha',
                              onPressed: () => widget.onVerSocio(socio),
                            ),

                            IconButton(
                              icon: const Icon(
                                Icons.attach_money_rounded,
                                color: Colors.green,
                              ),
                              tooltip: 'Cuenta Corriente',
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        CuentaCorrienteSocioPage(
                                          socioId: socio.id,
                                          nombreSocio: socio.nombre,
                                        ),
                                  ),
                                );
                              },
                            ),

                            if (esAdmin)
                              IconButton(
                                icon: const Icon(
                                  Icons.edit_note_rounded,
                                  color: Colors.blueGrey,
                                ),
                                tooltip: 'Editar Socio',
                                onPressed: () => widget.onEditarSocio(socio),
                              ),
                          ],
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
    );
  }
}
