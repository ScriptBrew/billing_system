import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://zyqlvpdwnagrhtvavaah.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5cWx2cGR3bmFncmh0dmF2YWFoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA0NzgxNjgsImV4cCI6MjA4NjA1NDE2OH0.x2b4Yj06j3_kp969VCEd5pyeWPcTc03onE-jm8SgTUI',
  );
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: AuthScreen()));
}

// --- AUTH SCREEN ---
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final userCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  MobileScannerController loginScanner = MobileScannerController();

  Future<void> _handleAuth() async {
    try {
      final res = await Supabase.instance.client.from('staff_login').select().eq('username', userCtrl.text).eq('password', passCtrl.text).maybeSingle();
      if (res != null) {
        await loginScanner.stop();
        loginScanner.dispose();
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BillingHome(staffId: res['id'])));
      } else {
        throw "Invalid Credentials";
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey[900],
      body: Center(
        child: Container(
          width: 400, padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.shopping_basket, size: 50, color: Colors.blueGrey),
            const Text("SUPERMARKET POS", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Container(height: 150, width: double.infinity, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
              child: MobileScanner(controller: loginScanner, onDetect: (cap) {
                final code = cap.barcodes.first.rawValue ?? "";
                if (code.contains(":")) {
                  userCtrl.text = code.split(":")[0];
                  passCtrl.text = code.split(":")[1];
                  _handleAuth();
                }
              })),
            const SizedBox(height: 15),
            TextField(controller: userCtrl, decoration: const InputDecoration(labelText: "Username", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: passCtrl, decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder()), obscureText: true),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _handleAuth, style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800]), child: const Text("LOGIN", style: TextStyle(color: Colors.white)))),
          ]),
        ),
      ),
    );
  }
}

// --- BILLING HOME ---
class BillingHome extends StatefulWidget {
  final String staffId;
  const BillingHome({super.key, required this.staffId});
  @override
  State<BillingHome> createState() => _BillingHomeState();
}

class _BillingHomeState extends State<BillingHome> {
  List<Map<String, dynamic>> cart = [];
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final searchCtrl = TextEditingController();
  MobileScannerController? mainController;
  Key scannerKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    mainController = MobileScannerController(detectionTimeoutMs: 1500);
  }

  Future<void> _safeRestart() async {
    if (mainController != null) {
      await mainController!.stop();
      mainController!.dispose();
    }
    await Future.delayed(const Duration(milliseconds: 2000));
    if (mounted) {
      setState(() { 
        mainController = MobileScannerController(detectionTimeoutMs: 1500);
        scannerKey = UniqueKey(); 
      });
    }
  }

  void _onDetect(String code) async {
    final res = await Supabase.instance.client.from('items').select().eq('barcode', code).maybeSingle();
    if (res != null) { _addToCart(res); searchCtrl.clear(); }
  }

  void _searchByName(String name) async {
    final res = await Supabase.instance.client.from('items').select().ilike('name', '%$name%');
    if (res != null && res.isNotEmpty) {
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text("Select Product"),
        content: SizedBox(width: 300, child: ListView.builder(
          shrinkWrap: true,
          itemCount: res.length,
          itemBuilder: (c, i) => ListTile(
            title: Text(res[i]['name']),
            trailing: Text("Rs. ${res[i]['price']}"),
            onTap: () { _addToCart(res[i]); Navigator.pop(ctx); searchCtrl.clear(); },
          ),
        )),
      ));
    }
  }

  void _addToCart(Map<String, dynamic> item) {
    setState(() {
      int i = cart.indexWhere((it) => it['barcode'] == item['barcode']);
      if (i != -1) cart[i]['qty']++; else cart.add({...item, 'qty': 1});
    });
  }

  double get totalAmount => cart.fold(0.0, (sum, i) => sum + (i['price'] * i['qty']));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueGrey[800],
        title: const Text("POS System", style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(onPressed: _showAddDialog, icon: const Icon(Icons.add_circle, color: Colors.white)),
          IconButton(onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthScreen())), icon: const Icon(Icons.logout, color: Colors.white)),
        ],
      ),
      body: Row(children: [
        Container(width: 350, color: Colors.grey[100], padding: const EdgeInsets.all(16),
          child: Column(children: [
            Container(height: 200, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
              child: mainController == null ? const Center(child: CircularProgressIndicator()) : MobileScanner(key: scannerKey, controller: mainController, onDetect: (cap) { if (cap.barcodes.isNotEmpty) _onDetect(cap.barcodes.first.rawValue!); })),
            const SizedBox(height: 20),
            TextField(controller: searchCtrl, decoration: const InputDecoration(labelText: "Scan Barcode or Type Name", border: OutlineInputBorder()), onSubmitted: (val) {
              if (double.tryParse(val) == null) _searchByName(val); else _onDetect(val);
            }),
            const SizedBox(height: 10),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Customer Name", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: "Mobile Number", border: OutlineInputBorder())),
            const Spacer(),
            ElevatedButton.icon(onPressed: () => setState(() { cart.clear(); nameCtrl.clear(); phoneCtrl.clear(); }), icon: const Icon(Icons.refresh), label: const Text("RESET BILL"), style: ElevatedButton.styleFrom(backgroundColor: Colors.red[50], foregroundColor: Colors.red)),
          ])),
        
        Expanded(child: Container(color: Colors.white, padding: const EdgeInsets.all(20),
          child: Column(children: [
            Expanded(child: ListView.separated(
              itemCount: cart.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (ctx, i) => ListTile(
                title: Text(cart[i]['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                subtitle: Text("Rs. ${cart[i]['price']} x ${cart[i]['qty']}"),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.remove_circle, color: Colors.orange), onPressed: () => setState(() => cart[i]['qty'] > 1 ? cart[i]['qty']-- : cart.removeAt(i))),
                  Text("${cart[i]['qty']}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), onPressed: () => setState(() => cart[i]['qty']++)),
                  const SizedBox(width: 10),
                  // DELETE BUTTON
                  IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => cart.removeAt(i))),
                  const SizedBox(width: 10),
                  Text("Rs. ${cart[i]['price'] * cart[i]['qty']}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ]),
              ),
            )),
            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("TOTAL:", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Text("Rs. ${totalAmount.toStringAsFixed(2)}", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.green)),
                ]),
                const SizedBox(height: 15),
                Row(children: [
                  Expanded(child: ElevatedButton(onPressed: () {}, child: const Text("SAVE BILL"))),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800]), child: const Text("GENERATE BILL", style: TextStyle(color: Colors.white)))),
                ])
              ]))
          ])))
      ]),
    );
  }

  void _showAddDialog() async {
    if (mainController != null) { await mainController!.stop(); } 
    final b = TextEditingController(); final n = TextEditingController(); final p = TextEditingController();
    final dialogScanner = MobileScannerController(detectionTimeoutMs: 1500);
    if (!mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      title: const Text("Register Product"),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: 150, child: MobileScanner(controller: dialogScanner, onDetect: (c) { if (c.barcodes.isNotEmpty) b.text = c.barcodes.first.rawValue ?? ""; })),
        TextField(controller: b, decoration: const InputDecoration(labelText: "Barcode")),
        TextField(controller: n, decoration: const InputDecoration(labelText: "Name")),
        TextField(controller: p, decoration: const InputDecoration(labelText: "Price (Rs.)")),
      ])),
      actions: [
        TextButton(onPressed: () async { await dialogScanner.stop(); dialogScanner.dispose(); Navigator.pop(ctx); _safeRestart(); }, child: const Text("Cancel")),
        ElevatedButton(onPressed: () async {
          await Supabase.instance.client.from('items').insert({'barcode': b.text, 'name': n.text, 'price': double.tryParse(p.text) ?? 0.0});
          await dialogScanner.stop(); dialogScanner.dispose(); Navigator.pop(ctx); _safeRestart();
        }, child: const Text("Save")),
      ],
    ));
  }
}
