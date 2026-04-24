import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

class BonPage extends StatefulWidget {
  final String namaLogin;

  BonPage({required this.namaLogin});

  @override
  _BonPageState createState() => _BonPageState();
}

class _BonPageState extends State<BonPage> {
  final TextEditingController _bonController = TextEditingController();
  final TextEditingController _ketController = TextEditingController();

  String? namaLogin;
  File? _image;
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    namaLogin = widget.namaLogin;

    _bonController.addListener(() => setState(() {}));
    _ketController.addListener(() => setState(() {}));
  }

  Future pickImage() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 50,
      preferredCameraDevice: CameraDevice.front,
    );

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
    }
  }

  Future<void> deleteImgurImage(String deleteHash) async {
    final uri = Uri.parse('https://api.imgur.com/3/image/$deleteHash');
    http.MultipartRequest('DELETE', uri)
      ..headers['Authorization'] = 'Client-ID 60b33d4ed1b07fe'; //secret id nya adfec42b48c8444b78337f62b9a90c7720424208
  }

  Future<void> kirimBon() async {
    if (namaLogin == null || _bonController.text.isEmpty || _image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Harap isi nama, jumlah bon dan foto!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uri = Uri.parse('https://api.imgur.com/3/image');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Client-ID 60b33d4ed1b07fe' //secret id nya adfec42b48c8444b78337f62b9a90c7720424208
        ..files.add(await http.MultipartFile.fromPath('image', _image!.path));

      final result = await request.send();
      final responseStr = await result.stream.bytesToString();
      final imageData = jsonDecode(responseStr);
      final imageUrl = imageData['data']['link'];

      final tanggal = DateTime.now().toIso8601String().split('T')[0];
      final jam = TimeOfDay.now().format(context);

      final scriptUrl = 'https://script.google.com/macros/s/AKfycbwdmqpsbZgr_Xf-00mqS3V57muT2PH7tnNabPYQ52IqWKtKH8CiQl8QkO3vsTRs2b__LA/exec';
      final fullUrl = Uri.parse(
        '$scriptUrl?nama=${Uri.encodeComponent(namaLogin!)}'
            '&tanggal=$tanggal'
            '&jam=$jam'
            '&isBon=true'
            '&foto=${Uri.encodeComponent(imageUrl)}'
            '&jumlah=${Uri.encodeComponent(_bonController.text)}'
            '&keterangan=${Uri.encodeComponent(_ketController.text)}',
      );

      final response = await http.get(fullUrl);
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bon berhasil dicatat!'), backgroundColor: Colors.green),
        );
        setState(() {
          _image = null;
          namaLogin = null;
          _bonController.clear();
          _ketController.clear();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${response.body}'), backgroundColor: Colors.red),
        );
      }
      deleteImgurImage(imageData['data']['deletehash']);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Terjadi error: $e'), backgroundColor: Colors.red),
      );
    }

    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _bonController.dispose();
    _ketController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bon Karyawan'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _bonController,
              decoration: InputDecoration(
                labelText: 'Jumlah Bon (Rp)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.money),
                prefixText: 'Rp ',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            SizedBox(height: 16),
            TextField(
              controller: _ketController,
              decoration: InputDecoration(
                labelText: 'Keterangan (opsional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 3,
            ),
            SizedBox(height: 16),
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    SizedBox(height: 16),
                    _image != null
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_image!, height: 200, fit: BoxFit.cover),
                    )
                        : Container(
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(child: Text('Belum ada foto')),
                    ),
                    SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: pickImage,
                      icon: Icon(Icons.camera_alt),
                      label: Text('Ambil Foto'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, 45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: (namaLogin != null &&
                  _bonController.text.isNotEmpty &&
                  _image != null &&
                  !_isLoading)
                  ? kirimBon
                  : null,
              child: Text('Catat Bon'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                minimumSize: Size(double.infinity, 50),
              ),
            )
          ],
        ),
      ),
    );
  }
}