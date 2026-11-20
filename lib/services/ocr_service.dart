import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Reads the text in a picture. The recognition model is part of the app and
/// runs on the phone, so nothing is uploaded.
class OcrService {
  OcrService._();

  /// The text found in the picture at [path], or an empty string.
  static Future<String> read(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(path));
      return result.text.trim();
    } finally {
      await recognizer.close();
    }
  }
}