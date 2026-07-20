import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

Future<String> uploadHunterImage(File file, String hunterId) async {
  final dir = await getTemporaryDirectory();
  final targetPath = join(dir.path, "${DateTime.now().millisecondsSinceEpoch}.jpg");

  final compressedFile = await FlutterImageCompress.compressAndGetFile(
    file.path,
    targetPath,
    quality: 70,
    minWidth: 1080,
    minHeight: 1080,
    format: CompressFormat.jpeg,
  );

  if (compressedFile == null) throw Exception("Compression failed");

  final fileName = "hunters/$hunterId/${DateTime.now().millisecondsSinceEpoch}.jpg";
  final ref = FirebaseStorage.instance.ref().child(fileName);
  
  final uploadTask = await ref.putFile(File(compressedFile.path));
  return await uploadTask.ref.getDownloadURL();
}