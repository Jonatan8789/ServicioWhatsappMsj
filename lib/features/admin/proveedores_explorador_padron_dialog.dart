import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'proveedores_abm_dialog.dart';

class ProveedoresExploradorPadronDialog extends StatefulWidget {
  const ProveedoresExploradorPadronDialog({super.key});

  @override
  State<ProveedoresExploradorPadronDialog> createState() =>
      _ProveedoresExploradorPadronDialogState();
}

class _ProveedoresExploradorPadronDialogState
    extends State<ProveedoresExploradorPadronDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _busqueda = '';
  String _filtroCondicionIVA = 'TODOS';
  String _filtroEstado = 'TODOS'; // TODOS, ACTIVO, INACTIVO
  String _filtroProvincia = 'TODAS';

  final List<String> _provinciasArg = [
    'TODAS',
    'Buenos Aires',
    'CABA',
    'Catamarca',
    'Chaco',
    'Chubut',
    'Córdoba',
    'Corrientes',
    'Entre Ríos',
    'Formosa',
    'Jujuy',
    'La Pampa',
    'La Rioja',
    'Mendoza',
    'Misiones',
    'Neuquén',
    'Río Negro',
    'Salta',
    'San Juan',
    'San Luis',
    'Santa Cruz',
    'Santa Fe',
    'Santiago del Estero',
    'Tierra del Fuego',
    'Tucumán',
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Icon(Icons.badge_rounded, color: Colors.teal),
              SizedBox(width: 10),
              Text(
                'Padrón Central de Proveedores & Prestadores',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const ProveedoresAbmDialog(),
              );
            },
            icon: const Icon(Icons.person_add_rounded, size: 18),
            label: const Text('Nuevo Proveedor'),
          ),
        ],
      ),
      content: SizedBox(
        width:
            MediaQuery.of(context).size.width * 0.85, // Se adapta dinámicamente
        height: 600,
        child: Column(
          children: [
            // 🔍 BARRA DE FILTROS DEL PADRÓN
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar por Razón Social, CUIT o Fantasía',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onChanged: (v) =>
                          setState(() => _busqueda = v.trim().toLowerCase()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _filtroCondicionIVA,
                      decoration: const InputDecoration(
                        labelText: 'Condición IVA',
                        isDense: true,
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items:
                          [
                                'TODOS',
                                'Responsable Inscripto',
                                'Monotributo',
                                'Exento',
                              ]
                              .map(
                                (e) =>
                                    DropdownMenuItem(value: e, child: Text(e)),
                              )
                              .toList(),
                      onChanged: (v) =>
                          setState(() => _filtroCondicionIVA = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _filtroEstado,
                      decoration: const InputDecoration(
                        labelText: 'Estado',
                        isDense: true,
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: ['TODOS', 'ACTIVO', 'INACTIVO']
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _filtroEstado = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _filtroProvincia,
                      decoration: const InputDecoration(
                        labelText: 'Provincia',
                        isDense: true,
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: _provinciasArg
                          .map(
                            (p) => DropdownMenuItem(value: p, child: Text(p)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _filtroProvincia = v!),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 📋 GRILLA CON SCROLL HORIZONTAL Y VERTICAL
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('proveedores')
                    .orderBy('razonSocial')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data!.docs;

                  final filtrados = docs.where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final String rs = (d['razonSocial'] ?? '')
                        .toString()
                        .toLowerCase();
                    final String cuit = (d['cuit'] ?? '')
                        .toString()
                        .toLowerCase();
                    final String fan = (d['nombreFantasia'] ?? '')
                        .toString()
                        .toLowerCase();
                    final String condIVA = d['condicionIVA'] ?? '';
                    final String prov = d['provincia'] ?? '';
                    final bool activo = d['activo'] ?? true;
                    final String estadoStr = activo ? 'ACTIVO' : 'INACTIVO';

                    bool matchBusqueda =
                        _busqueda.isEmpty ||
                        rs.contains(_busqueda) ||
                        cuit.contains(_busqueda) ||
                        fan.contains(_busqueda);
                    bool matchIVA =
                        _filtroCondicionIVA == 'TODOS' ||
                        condIVA == _filtroCondicionIVA;
                    bool matchProv =
                        _filtroProvincia == 'TODAS' || prov == _filtroProvincia;
                    bool matchEstado =
                        _filtroEstado == 'TODOS' || estadoStr == _filtroEstado;

                    return matchBusqueda &&
                        matchIVA &&
                        matchProv &&
                        matchEstado;
                  }).toList();

                  if (filtrados.isEmpty) {
                    return const Center(
                      child: Text(
                        'No hay proveedores registrados que coincidan con la búsqueda.',
                      ),
                    );
                  }

                  return Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: Scrollbar(
                        thumbVisibility: true,
                        notificationPredicate: (notif) => notif.depth == 1,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              const Color(0xFF1E293B),
                            ),
                            headingTextStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            columns: const [
                              DataColumn(label: Text('Estado')),
                              DataColumn(
                                label: Text('Razón Social / Fantasía'),
                              ),
                              DataColumn(label: Text('CUIT')),
                              DataColumn(label: Text('Cond. IVA / IIBB')),
                              DataColumn(label: Text('Provincia / Loc.')),
                              DataColumn(label: Text('Días Crédito')),
                              DataColumn(label: Text('CBU / Alias')),
                              DataColumn(label: Text('Contacto')),
                              DataColumn(label: Text('Acciones')),
                            ],
                            rows: filtrados.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final String id = doc.id;
                              final bool esActivo = data['activo'] ?? true;

                              return DataRow(
                                color: WidgetStateProperty.resolveWith<Color?>((
                                  Set<WidgetState> states,
                                ) {
                                  return esActivo ? null : Colors.red.shade50;
                                }),
                                cells: [
                                  // Badge de Estado + Toggle Inactivar
                                  DataCell(
                                    Tooltip(
                                      message: esActivo
                                          ? 'Proveedor Activo'
                                          : 'Proveedor Inactivo (Deshabilitado)',
                                      child: Chip(
                                        label: Text(
                                          esActivo ? 'ACTIVO' : 'INACTIVO',
                                          style: TextStyle(
                                            color: esActivo
                                                ? Colors.green.shade900
                                                : Colors.red.shade900,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                        backgroundColor: esActivo
                                            ? Colors.green.shade100
                                            : Colors.red.shade100,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          data['razonSocial'] ?? '-',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (data['nombreFantasia'] != null &&
                                            data['nombreFantasia']
                                                .toString()
                                                .isNotEmpty)
                                          Text(
                                            data['nombreFantasia'],
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  DataCell(Text(data['cuit'] ?? '-')),
                                  DataCell(
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          data['condicionIVA'] ?? '-',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        Text(
                                          data['jurisdiccionIIBB'] ?? '-',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.teal,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      '${data['provincia'] ?? ''} - ${data['localidad'] ?? ''}',
                                    ),
                                  ),
                                  DataCell(
                                    Center(
                                      child: Text(
                                        '${data['diasVencimientoFactura'] ?? 30}d',
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(data['alias'] ?? data['cbu'] ?? '-'),
                                  ),
                                  DataCell(
                                    Text(
                                      data['telefono'] ?? data['email'] ?? '-',
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // ✏️ Botón Editar
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit_rounded,
                                            color: Colors.blue,
                                          ),
                                          tooltip: 'Editar Proveedor',
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder: (context) =>
                                                  ProveedoresAbmDialog(
                                                    proveedorExistente: data,
                                                    proveedorId: id,
                                                  ),
                                            );
                                          },
                                        ),
                                        // 🚫 / ✅ Botón Inactivar / Activar
                                        IconButton(
                                          icon: Icon(
                                            esActivo
                                                ? Icons.block_rounded
                                                : Icons.check_circle_rounded,
                                            color: esActivo
                                                ? Colors.orange.shade800
                                                : Colors.green,
                                          ),
                                          tooltip: esActivo
                                              ? 'Inactivar Proveedor'
                                              : 'Reactivar Proveedor',
                                          onPressed: () =>
                                              _toggleEstadoProveedor(
                                                id,
                                                esActivo,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  // 🔄 Cambiar Estado (Activo / Inactivo) en Firestore
  Future<void> _toggleEstadoProveedor(String id, bool estadoActual) async {
    final bool nuevoEstado = !estadoActual;

    await _firestore.collection('proveedores').doc(id).update({
      'activo': nuevoEstado,
      'actualizadoEl': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nuevoEstado
                ? 'Proveedor reactivado con éxito.'
                : 'Proveedor marcado como inactivo.',
          ),
          backgroundColor: nuevoEstado ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
