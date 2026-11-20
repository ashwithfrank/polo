import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// The writing systems Polo can read.
enum OcrScript {
  latin('English and Latin letters'),
  devanagari('Hindi, Marathi, Sanskrit');

  const OcrScript(this.label);
  final String label;

  TextRecognitionScript get mlkit => switch (this) {
        OcrScript.latin => TextRecognitionScript.latin,
        OcrScript.devanagari => TextRecognitionScript.devanagiri,
      };
}

/// Reads the text in a picture. The recognition models are part of the app and
/// run on the phone, so nothing is uploaded.
class OcrService {
  OcrService._();

  /// The writing system picked last time, kept until Polo closes.
  static OcrScript last = OcrScript.latin;

  /// The text found in the picture at [path], or an empty string.
  static Future<String> read(String path, {OcrScript? script}) async {
    final recognizer = TextRecognizer(script: (script ?? last).mlkit);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(path));
      return result.text.trim();
    } finally {
      await recognizer.close();
    }
  }
}
