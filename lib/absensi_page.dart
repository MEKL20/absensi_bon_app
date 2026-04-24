import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class AbsensiPage extends StatefulWidget {
  final String namaLogin;

  AbsensiPage({required this.namaLogin});

  @override
  _AbsensiPageState createState() => _AbsensiPageState();
}

class _AbsensiPageState extends State<AbsensiPage> {
  String? namaLogin;
  File? _image;
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    namaLogin = widget.namaLogin;
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

  Future<void> kirimAbsen() async {
    if (namaLogin == null || _image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nama dan foto wajib diisi!')),
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
            '&isBon=false'
            '&foto=${Uri.encodeComponent(imageUrl)}',
      );

      final response = await http.get(fullUrl);

      if (response.statusCode == 200 && response.body == 'ABSEN OK') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Absensi berhasil dikirim!'), backgroundColor: Colors.green),
        );
        setState(() {
          _image = null;
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Absensi Karyawan'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text('Selfie', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
              onPressed: (namaLogin != null && _image != null && !_isLoading)
                  ? kirimAbsen
                  : null,
              child: Text('Kirim Absen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
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