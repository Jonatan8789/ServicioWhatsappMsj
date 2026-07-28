import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ComponenteCombo {
  final String productoId;
  final int cantidad;

  ComponenteCombo({required this.productoId, required this.cantidad});

  factory ComponenteCombo.fromMap(Map<String, dynamic> map) {
    return ComponenteCombo(
      productoId: map['productoId'] ?? '',
      cantidad: (map['cantidad'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {'productoId': productoId, 'cantidad': cantidad};
  }
}

class ProductoBuffetModel {
  final String id;
  final String nombre;
  final String descripcion;
  final String categoria;
  final double precio;
  final double precioCosto;
  final int stock;
  final int stockMinimo;
  final String codigoBarras;
  final String codigoInterno;
  final String? proveedorId;
  final bool disponible;
  final bool esCombo;
  final List<ComponenteCombo> componentes;
  final bool requiereCocina;

  ProductoBuffetModel({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.categoria,
    required this.precio,
    required this.precioCosto,
    required this.stock,
    required this.stockMinimo,
    required this.codigoBarras,
    required this.codigoInterno,
    this.proveedorId,
    required this.disponible,
    required this.esCombo,
    required this.componentes,
    required this.requiereCocina,
  });

  factory ProductoBuffetModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ProductoBuffetModel(
      id: doc.id,
      nombre: data['nombre'] ?? '',
      descripcion: data['descripcion'] ?? '',
      categoria: data['categoria'] ?? '',
      precio:
          (data['precioVenta'] ?? data['precio'] as num?)?.toDouble() ?? 0.0,
      precioCosto: (data['precioCosto'] as num?)?.toDouble() ?? 0.0,
      stock: (data['stockActual'] ?? data['stock'] as num?)?.toInt() ?? 0,
      stockMinimo: (data['stockMinimo'] as num?)?.toInt() ?? 0,
      codigoBarras: data['codigoBarras'] ?? data['codigo_barras'] ?? '',
      codigoInterno: data['codigoInterno'] ?? data['codigo_interno'] ?? '',
      proveedorId: data['proveedorId'],
      disponible: data['disponible'] ?? true,
      esCombo: data['esCombo'] ?? false,
      componentes:
          (data['componentes'] as List<dynamic>?)
              ?.map(
                (item) => ComponenteCombo.fromMap(item as Map<String, dynamic>),
              )
              .toList() ??
          [],
      requiereCocina: data['requiereCocina'] ?? false,
    );
  }
}

class MenuBuffetPage extends StatefulWidget {
  const MenuBuffetPage({super.key});

  @override
  State<MenuBuffetPage> createState() => _MenuBuffetPageState();
}

class _MenuBuffetPageState extends State<MenuBuffetPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _categoriaFiltro = 'Todas';
  String _searchQuery = '';

  final List<String> _categorias = [
    'Todas',
    'Bebidas',
    'Minutas',
    'Menú Diario',
    'Kiosco',
    'Cafetería',
  ];

  void _mostrarFormularioProducto([ProductoBuffetModel? producto]) {
    final formKey = GlobalKey<FormState>();
    final nombreCtrl = TextEditingController(text: producto?.nombre ?? '');
    final descCtrl = TextEditingController(text: producto?.descripcion ?? '');
    final precioCtrl = TextEditingController(
      text: producto?.precio != null ? producto!.precio.toStringAsFixed(0) : '',
    );
    final precioCostoCtrl = TextEditingController(
      text: producto?.precioCosto != null
          ? producto!.precioCosto.toStringAsFixed(0)
          : '',
    );
    final stockCtrl = TextEditingController(
      text: producto?.stock.toString() ?? '0',
    );
    final stockMinimoCtrl = TextEditingController(
      text: producto?.stockMinimo.toString() ?? '5',
    );
    final codBarrasCtrl = TextEditingController(
      text: producto?.codigoBarras ?? '',
    );
    final codInternoCtrl = TextEditingController(
      text: producto?.codigoInterno ?? '',
    );

    String? proveedorSeleccionadoId = producto?.proveedorId;
    String catSel = producto?.categoria ?? 'Minutas';
    bool disponible = producto?.disponible ?? true;

    bool esCombo = producto?.esCombo ?? false;
    List<ComponenteCombo> componentesSeleccionados =
        producto?.componentes != null
        ? List<ComponenteCombo>.from(producto!.componentes)
        : [];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) => AlertDialog(
            title: Text(
              producto == null
                  ? 'Nuevo Artículo / Combo'
                  : 'Editar Artículo / Combo',
            ),
            content: SizedBox(
              width: 600,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        title: const Text(
                          '¿Es un Combo de productos?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                        subtitle: const Text(
                          'Habilita la baja de stock múltiple de sus componentes.',
                        ),
                        value: esCombo,
                        activeThumbColor: Colors.indigo,
                        onChanged: (val) => setModalState(() => esCombo = val),
                      ),
                      const Divider(),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: nombreCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del Producto / Combo',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v!.isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: descCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Descripción / Detalle comercial',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: codBarrasCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Cód. Barras (Escáner)',
                                prefixIcon: Icon(Icons.qr_code_scanner),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: codInternoCtrl,
                              decoration: const InputDecoration(
                                labelText: 'SKU / Cód. Interno',
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
                              controller: precioCostoCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: esCombo
                                    ? 'Costo Estimado (\$)'
                                    : 'Precio Costo (\$ Compra)',
                                prefixIcon: const Icon(
                                  Icons.monetization_on_outlined,
                                ),
                                border: const OutlineInputBorder(),
                              ),
                              validator: (v) => v!.isEmpty ? 'Requerido' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: precioCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Precio Venta al Público (\$ PVP)',
                                prefixIcon: Icon(Icons.attach_money),
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => v!.isEmpty ? 'Requerido' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: catSel,
                              decoration: const InputDecoration(
                                labelText: 'Categoría',
                                border: OutlineInputBorder(),
                              ),
                              items: _categorias
                                  .where((c) => c != 'Todas')
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) => catSel = val!,
                            ),
                          ),
                          if (!esCombo) ...[
                            const SizedBox(width: 16),
                            Expanded(
                              child: StreamBuilder<QuerySnapshot>(
                                stream: _firestore
                                    .collection('proveedores')
                                    .snapshots(),
                                builder: (context, snapProv) {
                                  List<DropdownMenuItem<String>> provItems = [];
                                  if (snapProv.hasData) {
                                    for (var doc in snapProv.data!.docs) {
                                      final d =
                                          doc.data() as Map<String, dynamic>;
                                      provItems.add(
                                        DropdownMenuItem(
                                          value: doc.id,
                                          child: Text(d['razonSocial'] ?? ''),
                                        ),
                                      );
                                    }
                                  }
                                  return DropdownButtonFormField<String>(
                                    initialValue: proveedorSeleccionadoId,
                                    decoration: const InputDecoration(
                                      labelText: 'Proveedor',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: provItems,
                                    onChanged: (val) =>
                                        proveedorSeleccionadoId = val,
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 🛠️ BLOQUE FISCAL DINÁMICO PARA AGREGAR MULTIPRODUCTOS AL COMBO
                      if (esCombo) ...[
                        const Text(
                          'Estructura del Combo (Componentes):',
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
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: StreamBuilder<QuerySnapshot>(
                            stream: _firestore
                                .collection('buffet_productos')
                                .where('esCombo', isEqualTo: false)
                                .snapshots(),
                            builder: (context, snapSub) {
                              if (!snapSub.hasData) {
                                return const LinearProgressIndicator();
                              }
                              final listaDisponibles = snapSub.data!.docs;

                              return Column(
                                children: [
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: componentesSeleccionados.length,
                                    itemBuilder: (context, cIdx) {
                                      final itemCombo =
                                          componentesSeleccionados[cIdx];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4.0,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: DropdownButtonFormField<String>(
                                                initialValue:
                                                    itemCombo.productoId.isEmpty
                                                    ? null
                                                    : itemCombo.productoId,
                                                decoration:
                                                    const InputDecoration(
                                                      border:
                                                          OutlineInputBorder(),
                                                      isDense: true,
                                                    ),
                                                items: listaDisponibles.map((
                                                  d,
                                                ) {
                                                  final raw =
                                                      d.data()
                                                          as Map<
                                                            String,
                                                            dynamic
                                                          >;
                                                  return DropdownMenuItem(
                                                    value: d.id,
                                                    child: Text(
                                                      raw['nombre'] ?? '',
                                                    ),
                                                  );
                                                }).toList(),
                                                onChanged: (v) => setModalState(
                                                  () {
                                                    componentesSeleccionados[cIdx] =
                                                        ComponenteCombo(
                                                          productoId: v!,
                                                          cantidad: itemCombo
                                                              .cantidad,
                                                        );
                                                  },
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            SizedBox(
                                              width: 70,
                                              child: TextFormField(
                                                initialValue: itemCombo.cantidad
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
                                                    itemCombo
                                                        .productoId
                                                        .isNotEmpty
                                                    ? componentesSeleccionados[cIdx] =
                                                          ComponenteCombo(
                                                            productoId:
                                                                itemCombo
                                                                    .productoId,
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
                                                () => componentesSeleccionados
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
                                    label: const Text(
                                      'Agregar Producto al Combo',
                                    ),
                                    onPressed: () => setModalState(
                                      () => componentesSeleccionados.add(
                                        ComponenteCombo(
                                          productoId: '',
                                          cantidad: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: stockCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Stock Actual',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: stockMinimoCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Stock Mínimo Alerta',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
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
                  if (formKey.currentState!.validate()) {
                    final data = {
                      'nombre': nombreCtrl.text.trim(),
                      'descripcion': descCtrl.text.trim(),
                      'categoria': catSel,
                      'precioVenta': double.tryParse(precioCtrl.text) ?? 0.0,
                      'precioCosto':
                          double.tryParse(precioCostoCtrl.text) ?? 0.0,
                      'stock': esCombo
                          ? 0
                          : (int.tryParse(stockCtrl.text) ?? 0),
                      'stockMinimo': esCombo
                          ? 0
                          : (int.tryParse(stockMinimoCtrl.text) ?? 5),
                      'codigoBarras': codBarrasCtrl.text.trim(),
                      'codigoInterno': codInternoCtrl.text.trim(),
                      'proveedorId': esCombo ? null : proveedorSeleccionadoId,
                      'disponible': disponible,
                      'esCombo': esCombo,
                      'componentes': esCombo
                          ? componentesSeleccionados
                                .map((c) => c.toMap())
                                .toList()
                          : [],
                      'requiereCocina':
                          catSel == 'Minutas' || catSel == 'Menú Diario',
                    };

                    if (producto == null) {
                      await _firestore.collection('buffet_productos').add(data);
                    } else {
                      await _firestore
                          .collection('buffet_productos')
                          .doc(producto.id)
                          .update(data);
                    }
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _mostrarFormularioProducto(),
        backgroundColor: Colors.orange.shade700,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Nuevo Artículo / Combo',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gestión del Menú - Buffet',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const Text(
              'Administrá los costos, precios de venta, alertas de stock mínimo y combos articulados del buffet.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextField(
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o escanear código de barras...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: (value) =>
                  setState(() => _searchQuery = value.toLowerCase()),
            ),
            const SizedBox(height: 24),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categorias.map((cat) {
                  final seleccionado = _categoriaFiltro == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: ChoiceChip(
                      label: Text(
                        cat,
                        style: TextStyle(
                          fontWeight: seleccionado
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      selected: seleccionado,
                      selectedColor: Colors.orange.shade100,
                      onSelected: (bool selected) {
                        if (selected) setState(() => _categoriaFiltro = cat);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('buffet_productos').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final List<ProductoBuffetModel> productos = [];
                  for (var doc in snapshot.data!.docs) {
                    final p = ProductoBuffetModel.fromFirestore(doc);
                    if ((_categoriaFiltro == 'Todas' ||
                            p.categoria == _categoriaFiltro) &&
                        (_searchQuery.isEmpty ||
                            p.nombre.toLowerCase().contains(_searchQuery) ||
                            p.codigoBarras.toLowerCase().contains(
                              _searchQuery,
                            ))) {
                      productos.add(p);
                    }
                  }

                  if (productos.isEmpty) {
                    return const Center(
                      child: Text('No se encontraron artículos.'),
                    );
                  }

                  return GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 300,
                          mainAxisSpacing: 20,
                          crossAxisSpacing: 20,
                          childAspectRatio: 1.05,
                        ),
                    itemCount: productos.length,
                    itemBuilder: (context, index) {
                      final prod = productos[index];
                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        color: Colors.white,
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: prod.esCombo
                                          ? Colors.orange.shade100
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      prod.esCombo
                                          ? 'COMBO 🔥'
                                          : prod.categoria,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: prod.esCombo
                                            ? Colors.orange.shade900
                                            : Colors.blueGrey,
                                      ),
                                    ),
                                  ),
                                  Switch(
                                    value: prod.disponible,
                                    activeThumbColor: Colors.green,
                                    onChanged: (val) => _firestore
                                        .collection('buffet_productos')
                                        .doc(prod.id)
                                        .update({'disponible': val}),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                prod.nombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                prod.esCombo
                                    ? 'Contiene: ${prod.componentes.length} artículos'
                                    : 'Stock: ${prod.stock} un.',
                                style: TextStyle(
                                  color:
                                      !prod.esCombo &&
                                          prod.stock <= prod.stockMinimo
                                      ? Colors.red
                                      : Colors.blueGrey,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '\$${prod.precio.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_rounded,
                                      color: Colors.blueGrey,
                                    ),
                                    onPressed: () =>
                                        _mostrarFormularioProducto(prod),
                                  ),
                                ],
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
      ),
    );
  }
}
