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
        loginScanner.dispose(); // Release for Home
        _checkLocation(res['id']);
      } else {
        throw "Invalid Credentials";
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _checkLocation(String userId) async {
    final res = await Supabase.instance.client.from('profiles').select().eq('id', userId).maybeSingle();
    if (res == null || res['location'] == null) {
      _showLocSetup(userId);
    } else {
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BillingHome(staffId: userId, location: res['location'])));
    }
  }

  void _showLocSetup(String userId) {
    final c = TextEditingController();
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      title: const Text("Set Billing Location"),
      content: TextField(controller: c, decoration: const InputDecoration(labelText: "Store Counter")),
      actions: [ElevatedButton(onPressed: () async {
        await Supabase.instance.client.from('profiles').upsert({'id': userId, 'location': c.text});
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BillingHome(staffId: userId, location: c.text)));
      }, child: const Text("Save"))],
    ));
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
            const Text("SUPERMARKET LOGIN", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Container(height: 120, width: double.infinity, color: Colors.black, child: MobileScanner(
              controller: loginScanner, 
              onDetect: (cap) {
                final code = cap.barcodes.first.rawValue ?? "";
                if (code.contains(":")) {
                  userCtrl.text = code.split(":")[0];
                  passCtrl.text = code.split(":")[1];
                  _handleAuth();
                }
              })),
            const SizedBox(height: 15),
            TextField(controller: userCtrl, decoration: const InputDecoration(labelText: "Username")),
            TextField(controller: passCtrl, decoration: const InputDecoration(labelText: "Password"), obscureText: true),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _handleAuth, child: const Text("LOGIN")),
          ]),
        ),
      ),
    );
  }
}

class BillingHome extends StatefulWidget {
  final String staffId;
  final String location;
  const BillingHome({super.key, required this.staffId, required this.location});
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
    mainController = MobileScannerController(detectionTimeoutMs: 1500); // Prevent scan freeze
  }

  Future<void> _safeRestart() async {
    if (mainController != null) {
      await mainController!.stop();
      mainController!.dispose();
    }
    await Future.delayed(const Duration(milliseconds: 2000)); // Crucial for Chrome
    if (mounted) {
      setState(() { 
        mainController = MobileScannerController(detectionTimeoutMs: 1500);
        scannerKey = UniqueKey(); 
      });
    }
  }

  void _onDetect(String code) async {
    final res = await Supabase.instance.client.from('items').select().eq('barcode', code).maybeSingle();
    if (res != null) {
      setState(() {
        int i = cart.indexWhere((it) => it['barcode'] == code);
        if (i != -1) cart[i]['qty']++; else cart.add({...res, 'qty': 1});
      });
      searchCtrl.clear();
    }
  }

  Future<void> _generateBill(bool saveOnly) async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => pw.Padding(
        padding: const pw.EdgeInsets.all(30),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Center(child: pw.Text("SUPERMARKET INVOICE", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 20),
          pw.Text("Loc: ${widget.location} | Cust: ${nameCtrl.text} | Ph: ${phoneCtrl.text}"),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['Item', 'Qty', 'Price', 'Subtotal'],
            data: cart.map((i) => [i['name'], i['qty'], "Rs. ${i['price']}", "Rs. ${i['price'] * i['qty']}"]).toList(),
          ),
          pw.Divider(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
            pw.Text("TOTAL: Rs. ${cart.fold(0.0, (sum, i) => sum + (i['price'] * i['qty']))}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
          ]),
          pw.SizedBox(height: 40),
          pw.Center(child: pw.Text("THANK YOU FOR SHOPPING WITH US!")),
        ]),
      ),
    ));
    if (saveOnly) await Printing.sharePdf(bytes: await pdf.save(), filename: 'Bill.pdf');
    else await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("POS System"), actions: [
        ElevatedButton.icon(onPressed: _showAddDialog, icon: const Icon(Icons.add), label: const Text("ADD ITEM")),
        IconButton(onPressed: () async {
          if (mainController != null) { await mainController!.stop(); mainController!.dispose(); }
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthScreen()));
        }, icon: const Icon(Icons.logout)),
        const SizedBox(width: 15),
      ]),
      body: Row(children: [
        SizedBox(width: 380, child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          Container(height: 250, decoration: BoxDecoration(border: Border.all(color: Colors.blue)),
            child: mainController == null ? const Center(child: CircularProgressIndicator()) : MobileScanner(
              key: scannerKey, 
              controller: mainController, 
              onDetect: (cap) { if (cap.barcodes.isNotEmpty) _onDetect(cap.barcodes.first.rawValue!); })),
          const SizedBox(height: 20),
          TextField(controller: searchCtrl, decoration: const InputDecoration(labelText: "Barcode Search", border: OutlineInputBorder()), onSubmitted: _onDetect),
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Customer Name")),
          TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: "Mobile Number")),
          TextButton.icon(onPressed: () => setState(() { cart.clear(); nameCtrl.clear(); phoneCtrl.clear(); }), icon: const Icon(Icons.refresh), label: const Text("Clear")),
        ]))),
        const VerticalDivider(),
        Expanded(child: Column(children: [
          Expanded(child: ListView.builder(itemCount: cart.length, itemBuilder: (ctx, i) => ListTile(
            title: Text(cart[i]['name']), subtitle: Text("Rs. ${cart[i]['price']} x ${cart[i]['qty']}"),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.remove_circle), onPressed: () => setState(() => cart[i]['qty'] > 1 ? cart[i]['qty']-- : cart.removeAt(i))),
              Text("${cart[i]['qty']}"),
              IconButton(icon: const Icon(Icons.add_circle), onPressed: () => setState(() => cart[i]['qty']++)),
            ]),
          ))),
          Container(padding: const EdgeInsets.all(25), child: Column(children: [
            Text("TOTAL: Rs. ${cart.fold(0.0, (sum, i) => sum + (i['price'] * i['qty'])).toStringAsFixed(2)}", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              ElevatedButton(onPressed: () => _generateBill(true), child: const Text("SAVE BILL")),
              ElevatedButton(onPressed: () => _generateBill(false), child: const Text("GENERATE BILL")),
            ])
          ]))
        ]))
      ]),
    );
  }

  void _showAddDialog() async {
    if (mainController != null) { await mainController!.stop(); } 
    final b = TextEditingController(); final n = TextEditingController(); final p = TextEditingController();
    final dialogScanner = MobileScannerController(detectionTimeoutMs: 1500);
    
    if (!mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      title: const Text("New Product"),
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
