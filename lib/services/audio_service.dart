import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();

  // Stream de amplitude em tempo real (atualiza a cada 80ms).
  Stream<Amplitude> get amplitudeStream =>
      _recorder.onAmplitudeChanged(const Duration(milliseconds: 80));

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<String> start({String? filename}) async {
    if (!await _recorder.hasPermission()) {
      throw Exception('Permissão de microfone negada.');
    }
    final dir = await getTemporaryDirectory();
    final name = filename ?? 'rec_${DateTime.now().millisecondsSinceEpoch}';
    final path = '${dir.path}/$name.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    return path;
  }

  Future<String?> stop() => _recorder.stop();

  Future<bool> isRecording() => _recorder.isRecording();

  void dispose() => _recorder.dispose();
}
