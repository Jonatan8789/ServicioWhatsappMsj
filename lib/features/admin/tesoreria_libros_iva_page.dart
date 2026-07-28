import 'package:flutter/material.dart';
import 'libro_iva_compras_page.dart';
import 'libro_iva_ventas_page.dart';

class TesoreriaLibrosIvaPage extends StatefulWidget {
  const TesoreriaLibrosIvaPage({super.key});

  @override
  State<TesoreriaLibrosIvaPage> createState() => _TesoreriaLibrosIvaPageState();
}

class _TesoreriaLibrosIvaPageState extends State<TesoreriaLibrosIvaPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Tesorería - Consolidador Fiscal & Libros IVA',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: Colors.tealAccent,
            indicatorWeight: 4,
            labelColor: Colors.tealAccent,
            unselectedLabelColor: Colors.white60,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            tabs: [
              Tab(
                icon: Icon(Icons.shopping_cart_checkout_rounded),
                text: 'Libro IVA Compras (Crédito Fiscal)',
              ),
              Tab(
                icon: Icon(Icons.point_of_sale_rounded),
                text: 'Libro IVA Ventas (Débito Fiscal)',
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [LibroIvaComprasPage(), LibroIvaVentasPage()],
        ),
      ),
    );
  }
}
