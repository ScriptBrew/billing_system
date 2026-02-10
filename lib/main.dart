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
        await loginScanner.dispose();
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
      backgroundColor: const Color(0xFF2D3E50),
      body: Center(
        child: Container(
          width: 400, padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.shopping_basket, size: 50, color: Color(0xFF2D3E50)),
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
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _handleAuth, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D3E50)), child: const Text("LOGIN", style: TextStyle(color: Colors.white)))),
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
      await mainController!.dispose();
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
    if (res != null) {
      setState(() {
        int i = cart.indexWhere((it) => it['barcode'] == code);
        if (i != -1) cart[i]['qty']++; else cart.add({...res, 'qty': 1});
      });
      searchCtrl.clear();
    }
  }

  // --- PDF GENERATION LOGIC ---
  Future<void> _processBill(bool saveToLocal) async {
    // 1. Pause Camera to prevent hardware conflicts while PDF is generating
    if (mainController != null) await mainController!.stop();

    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => pw.Padding(
        padding: const pw.EdgeInsets.all(30),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Center(child: pw.Text("SUPERMARKET INVOICE", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 15),
          pw.Text("Customer: ${nameCtrl.text}"),
          pw.Text("Mobile: ${phoneCtrl.text}"),
          pw.Text("Date: ${DateTime.now().toString().substring(0,16)}"),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['Item', 'Qty', 'Price', 'Total'],
            data: cart.map((i) => [i['name'], i['qty'], "Rs. ${i['price']}", "Rs. ${i['price'] * i['qty']}"]).toList(),
          ),
          pw.Divider(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
            pw.Text("GRAND TOTAL: Rs. ${cart.fold(0.0, (sum, i) => sum + (i['price'] * i['qty']))}", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 50),
          pw.Center(child: pw.Text("THANK YOU FOR SHOPPING WITH US!", style: pw.TextStyle(fontStyle: pw.FontStyle.italic))),
        ]),
      ),
    ));

    if (saveToLocal) {
      // "Save Bill" - Automatically triggers the Save As / Download dialog
      await Printing.sharePdf(bytes: await pdf.save(), filename: 'invoice_${nameCtrl.text}.pdf');
    } else {
      // "Generate Bill" - Opens the standard Print Preview
      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    }

    // 2. Restart Camera after PDF process is closed
    _safeRestart();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D3E50),
        title: const Text("POS System", style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(onPressed: _showAddDialog, icon: const Icon(Icons.add_circle, color: Colors.white)),
          IconButton(onPressed: () async {
            if (mainController != null) { await mainController!.stop(); await mainController!.dispose(); }
            if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthScreen()));
          }, icon: const Icon(Icons.logout, color: Colors.white)),
        ],
      ),
      body: Row(children: [
        Container(width: 350, color: Colors.grey[100], padding: const EdgeInsets.all(16),
          child: Column(children: [
            Container(height: 200, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
              child: mainController == null ? const Center(child: CircularProgressIndicator()) : MobileScanner(key: scannerKey, controller: mainController, onDetect: (cap) { if (cap.barcodes.isNotEmpty) _onDetect(cap.barcodes.first.rawValue!); })),
            const SizedBox(height: 20),
            TextField(controller: searchCtrl, decoration: const InputDecoration(labelText: "Barcode Search", border: OutlineInputBorder()), onSubmitted: _onDetect),
            const SizedBox(height: 10),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Customer Name", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: "Mobile Number", border: OutlineInputBorder())),
            const Spacer(),
            TextButton.icon(onPressed: () => setState(() { cart.clear(); nameCtrl.clear(); phoneCtrl.clear(); }), icon: const Icon(Icons.refresh), label: const Text("Clear")),
          ])),
        const VerticalDivider(),
        Expanded(child: Column(children: [
          Expanded(child: ListView.builder(
            itemCount: cart.length,
            itemBuilder: (ctx, i) => ListTile(
              title: Text(cart[i]['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("Rs. ${cart[i]['price']} x ${cart[i]['qty']}"),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                 IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => setState(() => cart[i]['qty'] > 1 ? cart[i]['qty']-- : cart.removeAt(i))),
                 Text("${cart[i]['qty']}"),
                 IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), onPressed: () => setState(() => cart[i]['qty']++)),
                 const SizedBox(width: 10),
                 Text("Rs. ${cart[i]['price'] * cart[i]['qty']}"),
              ]),
            ),
          )),
          Container(padding: const EdgeInsets.all(20), color: Colors.grey[200], child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Total: Rs. ${cart.fold(0.0, (sum, i) => sum + (i['price'] * i['qty']))}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Row(children: [
                ElevatedButton(onPressed: () => _processBill(true), child: const Text("SAVE BILL")),
                const SizedBox(width: 10),
                ElevatedButton(onPressed: () => _processBill(false), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D3E50)), child: const Text("GENERATE BILL", style: TextStyle(color: Colors.white))),
              ])
            ],
          ))
        ])),
      ]),
    );
  }

  void _showAddDialog() async {
    if (mainController != null) { await mainController!.stop(); await mainController!.dispose(); }
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
        TextButton(onPressed: () async { await dialogScanner.stop(); await dialogScanner.dispose(); Navigator.pop(ctx); _safeRestart(); }, child: const Text("Cancel")),
        ElevatedButton(onPressed: () async {
          await Supabase.instance.client.from('items').insert({'barcode': b.text, 'name': n.text, 'price': double.tryParse(p.text) ?? 0.0});
          await dialogScanner.stop(); await dialogScanner.dispose(); Navigator.pop(ctx); _safeRestart();
        }, child: const Text("Save")),
      ],
    ));
  }
}
