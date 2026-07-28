import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'inventario_general_model.dart';

class InventarioGeneralPage extends StatefulWidget {
  const InventarioGeneralPage({super.key});

  @override
  State<InventarioGeneralPage> createState() => _InventarioGeneralPageState();
}

class _InventarioGeneralPageState extends State<InventarioGeneralPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _filtroTipo = 'Todos';
  String _filtroUbicacion = 'Todas';
  String _searchQuery = '';

  final List<String> _tiposInventario = [
    'Todos',
    'Buffet',
    'Pro-Shop / Indumentaria',
    'Insumos / Mantenimiento',
    'Artículos de Alquiler',
  ];
  final List<String> _ubicaciones = [
    'Todas',
    'Depósito Central',
    'Barra Buffet',
    'Mostrador Recepción',
  ];

  void _mostrarFormularioArticulo([InventarioGeneralModel? articulo]) {
    final _formKey = GlobalKey<FormState>();
    final _nombreCtrl = TextEditingController(text: articulo?.nombre ?? '');
    final _descCtrl = TextEditingController(text: articulo?.descripcion ?? '');
    final _precioVentaCtrl = TextEditingController(
      text: articulo?.precioVenta != null
          ? articulo!.precioVenta.toStringAsFixed(0)
          : '',
    );
    final _precioCostoCtrl = TextEditingController(
      text: articulo?.precioCosto != null
          ? articulo!.precioCosto.toStringAsFixed(0)
          : '',
    );
    final _stockActualCtrl = TextEditingController(
      text: articulo?.stockActual?.toString() ?? '0',
    );
    final _stockMinimoCtrl = TextEditingController(
      text: articulo?.stockMinimo?.toString() ?? '5',
    );
    final _codBarrasCtrl = TextEditingController(
      text: articulo?.codigoBarras ?? '',
    );
    final _codInternoCtrl = TextEditingController(
      text: articulo?.codigoInterno ?? '',
    );

    String _tipoSel = articulo?.tipoInventario ?? 'Buffet';
    String _ubicSel = articulo?.ubicacion ?? 'Depósito Central';
    String _categoriaCtrl = articulo?.categoria ?? 'Varios';
    String? _proveedorId = articulo?.proveedorId;
    bool _esCombo = articulo?.esCombo ?? false;
    bool _disponible = articulo?.disponible ?? true;
    List<ComponenteComboGeneral> _componentesSeleccionados =
        articulo?.componentes != null
        ? List<ComponenteComboGeneral>.from(articulo!.componentes)
        : [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text(
            articulo == null
                ? '⚙️ Dar de Alta en Inventario Central'
                : '📝 Editar Ítem de Inventario',
          ),
          content: SizedBox(
            width: 650,
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: const Text(
                        '¿Es un Combo / Pack Articulado?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      subtitle: const Text(
                        'Agrupa sub-artículos del inventario central para descontar stock en lote.',
                      ),
                      value: _esCombo,
                      activeColor: Colors.indigo,
                      onChanged: (v) => setModalState(() => _esCombo = v),
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nombreCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del Artículo / Insumo',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? 'Campo obligatorio' : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _tipoSel,
                            decoration: const InputDecoration(
                              labelText: 'Tipo de Inventario',
                              border: OutlineInputBorder(),
                            ),
                            items: _tiposInventario
                                .where((t) => t != 'Todos')
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setModalState(() => _tipoSel = v!),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _ubicSel,
                            decoration: const InputDecoration(
                              labelText: 'Ubicación / Destino',
                              border: OutlineInputBorder(),
                            ),
                            items: _ubicaciones
                                .where((u) => u != 'Todas')
                                .map(
                                  (u) => DropdownMenuItem(
                                    value: u,
                                    child: Text(u),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setModalState(() => _ubicSel = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _codBarrasCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Código de Barras (EAN)',
                              prefixIcon: Icon(Icons.qr_code),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _codInternoCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Código Interno / SKU',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _precioCostoCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Costo Reposición (\$ Neto)',
                              prefixIcon: Icon(Icons.inventory),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _precioVentaCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Precio de Venta (\$ PVP)',
                              prefixIcon: Icon(
                                Icons.attach_money,
                                color: Colors.green,
                              ),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!_esCombo) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _stockActualCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Stock Físico Inicial',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _stockMinimoCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Punto de Alerta (Mínimo)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // LÓGICA DE DETALLE DINÁMICO DE COMBOS (SACADA DE BUFFET PARA INVENTARIO GENERAL)
                    if (_esCombo) ...[
                      const SizedBox(height: 16),
                      StreamBuilder<QuerySnapshot>(
                        stream: _firestore
                            .collection('inventario_general')
                            .snapshots(),
                        builder: (context, snapSub) {
                          if (!snapSub.hasData)
                            return const LinearProgressIndicator();
                          final disponibles = snapSub.data!.docs
                              .where((d) => d.id != (articulo?.id ?? ''))
                              .toList();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Componentes del Combo General:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    ListView.builder(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount:
                                          _componentesSeleccionados.length,
                                      itemBuilder: (context, cIdx) {
                                        final comp =
                                            _componentesSeleccionados[cIdx];
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4.0,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: DropdownButtonFormField<String>(
                                                  value:
                                                      comp
                                                          .itemInventarioId
                                                          .isEmpty
                                                      ? null
                                                      : comp.itemInventarioId,
                                                  decoration:
                                                      const InputDecoration(
                                                        border:
                                                            OutlineInputBorder(),
                                                        isDense: true,
                                                      ),
                                                  items: disponibles
                                                      .map(
                                                        (d) => DropdownMenuItem(
                                                          value: d.id,
                                                          child: Text(
                                                            d['nombre'] ?? '',
                                                          ),
                                                        ),
                                                      )
                                                      .toList(),
                                                  onChanged: (v) => setModalState(
                                                    () => _componentesSeleccionados[cIdx] =
                                                        ComponenteComboGeneral(
                                                          itemInventarioId: v!,
                                                          cantidad:
                                                              comp.cantidad,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              SizedBox(
                                                width: 80,
                                                child: TextFormField(
                                                  initialValue: comp.cantidad
                                                      .toString(),
                                                  keyboardType:
                                                      TextInputType.number,
                                                  decoration:
                                                      const InputDecoration(
                                                        labelText: 'Cant',
                                                        border:
                                                            OutlineInputBorder(),
                                                        isDense: true,
                                                      ),
                                                  onChanged: (v) =>
                                                      comp
                                                          .itemInventarioId
                                                          .isNotEmpty
                                                      ? _componentesSeleccionados[cIdx] =
                                                            ComponenteComboGeneral(
                                                              itemInventarioId:
                                                                  comp.itemInventarioId,
                                                              cantidad:
                                                                  int.tryParse(
                                                                    v,
                                                                  ) ??
                                                                  1,
                                                            )
                                                      : null,
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.delete,
                                                  color: Colors.red,
                                                ),
                                                onPressed: () => setModalState(
                                                  () =>
                                                      _componentesSeleccionados
                                                          .removeAt(cIdx),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    TextButton.icon(
                                      icon: const Icon(Icons.add),
                                      label: const Text('Añadir Componente'),
                                      onPressed: () => setModalState(
                                        () => _componentesSeleccionados.add(
                                          ComponenteComboGeneral(
                                            itemInventarioId: '',
                                            cantidad: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  final data = {
                    'nombre': _nombreCtrl.text.trim(),
                    'descripcion': _descCtrl.text.trim(),
                    'categoria': _categoriaCtrl,
                    'tipoInventario': _tipoSel,
                    'ubicacion': _ubicSel,
                    'precioVenta':
                        double.tryParse(_precioVentaCtrl.text) ?? 0.0,
                    'precioCosto':
                        double.tryParse(_precioCostoCtrl.text) ?? 0.0,
                    'stockActual': _esCombo
                        ? 0
                        : (int.tryParse(_stockActualCtrl.text) ?? 0),
                    'stockMinimo': _esCombo
                        ? 0
                        : (int.tryParse(_stockMinimoCtrl.text) ?? 5),
                    'codigoBarras': _codBarrasCtrl.text.trim(),
                    'codigoInterno': _codInternoCtrl.text.trim(),
                    'esCombo': _esCombo,
                    'componentes': _esCombo
                        ? _componentesSeleccionados
                              .map((c) => c.toMap())
                              .toList()
                        : [],
                    'disponible': _disponible,
                    'requiereCocina':
                        _tipoSel == 'Buffet' &&
                        (_categoriaCtrl == 'Minutas' ||
                            _categoriaCtrl == 'Menú Diario'),
                  };

                  if (articulo == null) {
                    await _firestore.collection('inventario_general').add(data);
                  } else {
                    await _firestore
                        .collection('inventario_general')
                        .doc(articulo.id)
                        .update(data);
                  }
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: const Text('Guardar Máster'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.orange.shade700,
        onPressed: () => _mostrarFormularioArticulo(),
        icon: const Icon(Icons.add_box_rounded, color: Colors.white),
        label: const Text(
          'Alta de Inventario Central',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🗃️ Central Única de Inventario',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const Text(
              'Explorador logístico maestro del club. Controlá mercadería de Buffet, Pro-Shop, Insumos y Alquileres de forma unificada.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),

            // FILTROS AVANZADOS DE CENTRALIZACIÓN
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar por Nombre, Código de Barras o SKU...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _filtroTipo,
                    decoration: const InputDecoration(
                      labelText: 'Filtrar por Depósito / Tipo',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                    ),
                    items: _tiposInventario
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _filtroTipo = v!),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _filtroUbicacion,
                    decoration: const InputDecoration(
                      labelText: 'Filtrar por Ubicación',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                    ),
                    items: _ubicaciones
                        .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                        .toList(),
                    onChanged: (v) => setState(() => _filtroUbicacion = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // EXPLORADOR EN FORMATO TABLA DE CONTROL DE AUDITORÍA
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('inventario_general')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final docs = snapshot.data!.docs;

                    List<InventarioGeneralModel> filtrados = [];
                    for (var d in docs) {
                      final item = InventarioGeneralModel.fromFirestore(d);
                      final matchTipo =
                          _filtroTipo == 'Todos' ||
                          item.tipoInventario == _filtroTipo;
                      final matchUbic =
                          _filtroUbicacion == 'Todas' ||
                          item.ubicacion == _filtroUbicacion;
                      final matchBusqueda =
                          _searchQuery.isEmpty ||
                          item.nombre.toLowerCase().contains(_searchQuery) ||
                          item.codigoBarras.contains(_searchQuery) ||
                          item.codigoInterno.toLowerCase().contains(
                            _searchQuery,
                          );

                      if (matchTipo && matchUbic && matchBusqueda) {
                        filtrados.add(item);
                      }
                    }

                    if (filtrados.isEmpty)
                      return const Center(
                        child: Text(
                          'No hay artículos que coincidan con la búsqueda.',
                        ),
                      );

                    return ListView.separated(
                      itemCount: filtrados.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final item = filtrados[idx];
                        final bool critico =
                            !item.esCombo &&
                            item.stockActual <= item.stockMinimo;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: item.esCombo
                                ? Colors.orange.shade50
                                : (critico
                                      ? Colors.red.shade50
                                      : Colors.blue.shade50),
                            child: Icon(
                              item.esCombo
                                  ? Icons.local_fire_department
                                  : (item.tipoInventario.contains('Shop')
                                        ? Icons.shopping_bag
                                        : Icons.inventory_2),
                              color: item.esCombo
                                  ? Colors.orange
                                  : (critico ? Colors.red : Colors.blue),
                            ),
                          ),
                          title: Text(
                            item.nombre,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            'SKU: ${item.codigoInterno.isEmpty ? '-' : item.codigoInterno} | Sector: ${item.tipoInventario} ➔ ${item.ubicacion}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    item.esCombo
                                        ? '🔥 PACK COMBO'
                                        : 'Stock: ${item.stockActual} un.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: critico
                                          ? Colors.red
                                          : Colors.black87,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    'PVP: \$${item.precioVenta.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.teal,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit_note,
                                  color: Colors.blueGrey,
                                ),
                                onPressed: () =>
                                    _mostrarFormularioArticulo(item),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
