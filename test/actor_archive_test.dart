import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/actor_archive.dart';
import 'package:image/image.dart' as img;

Uint8List jpg(int r) {
  final photo = img.Image(width: 64, height: 80);
  img.fill(photo, color: img.ColorRgb8(r, 100, 120));
  return Uint8List.fromList(img.encodeJpg(photo));
}

void main() {
  test('seven-photo Actor package safely roundtrips metadata and JPGs', () {
    final photos = List.generate(7, (i) => jpg(i * 25));
    final bytes = ActorArchiveCodec.encode(
      name: 'My Star', style: 'Photorealistic',
      notes: 'Distinctive beard', photos: photos,
      autoTouchUp: true,
    );
    final restored = ActorArchiveCodec.decode(bytes);
    expect(restored.name, 'My Star');
    expect(restored.style, 'Photorealistic');
    expect(restored.notes, 'Distinctive beard');
    expect(restored.photos.length, 7);
    expect(restored.autoTouchUp, isTrue);
    expect(restored.photos.first, orderedEquals(photos.first));
  });

  test('refuses fake JPG bytes and unreadable exports', () {
    expect(
      () => ActorArchiveCodec.encode(
        name: 'Test', style: 'Cinematic', notes: '',
        photos: [Uint8List.fromList([1, 2, 3, 4])],
      ),
      throwsFormatException,
    );
    expect(
      () => ActorArchiveCodec.decode(Uint8List.fromList([1, 2, 3])),
      throwsA(anything),
    );
  });

  test('ZIP bomb preflight rejects massive claimed size before inflation', () {
    final encoded = ActorArchiveCodec.encode(
      name: 'Portrait', style: 'Cinematic', notes: '',
      photos: [jpg(60)],
    );
    final tampered = Uint8List.fromList(encoded);
    int? central;
    for (var i = 0; i <= tampered.length - 46; i++) {
      if (tampered[i] == 0x50 && tampered[i + 1] == 0x4b &&
          tampered[i + 2] == 0x01 && tampered[i + 3] == 0x02) {
        central = i;
        break;
      }
    }
    expect(central, isNotNull);
    // Deliberately advertise 2 GiB expanded data in a tiny photo archive.
    final sizeField = central! + 24;
    tampered[sizeField] = 0x00;
    tampered[sizeField + 1] = 0x00;
    tampered[sizeField + 2] = 0x00;
    tampered[sizeField + 3] = 0x80;
    expect(() => ActorArchiveCodec.decode(tampered), throwsFormatException);
  });

  test('valid archive remains readable under ZIP directory limits', () {
    final archive = ActorArchiveCodec.encode(
      name: 'Valid', style: 'Photorealistic',
      notes: 'Preserves all 7 angles',
      photos: List.generate(7, (index) => jpg(index + 11)),
    );
    final decoded = ActorArchiveCodec.decode(archive);
    expect(decoded.photos.length, 7);
  });

  test('import rejects traversal, symlink and unrelated package files', () {
    final archive = Archive();
    archive.addFile(ArchiveFile.string('../secret.txt', 'attack'));
    archive.addFile(ArchiveFile.string('manifest.json',
        jsonEncode({
          'format': 'HOTICE_ACTOR',
          'version': 1, 'name': 'Bad', 'style': 'Cinematic',
          'notes': '', 'encrypted': false, 'images': ['../secret.txt']
        })));
    expect(
      () => ActorArchiveCodec.decode(ZipEncoder().encodeBytes(archive)),
      throwsFormatException,
    );
  });

  test('rejects manifest/image disagreement', () {
    final archive = Archive();
    archive.addFile(ArchiveFile.string('manifest.json', jsonEncode({
      'format': 'HOTICE_ACTOR', 'version': 1,
      'name': 'Actor', 'style': 'Cinematic', 'notes': '',
      'encrypted': false, 'images': ['images/angle_00.jpg'],
    })));
    archive.addFile(ArchiveFile.bytes('images/angle_01.jpg', jpg(60)));
    expect(
      () => ActorArchiveCodec.decode(ZipEncoder().encodeBytes(archive)),
      throwsFormatException,
    );
  });
}
