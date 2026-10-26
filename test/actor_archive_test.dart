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

  test('rejects ZIP bombs based on central directory before decompression', () {
    final zipped = ActorArchiveCodec.encode(
      name: 'Actor', style: 'Cinematic', notes: '',
      photos: [jpg(70)],
    );
    final forged = Uint8List.fromList(zipped);
    final data = ByteData.sublistView(forged);
    var central = -1;
    for (var i = 0; i < forged.length - 46; i++) {
      if (data.getUint32(i, Endian.little) == 0x02014b50) {
        central = i;
        break;
      }
    }
    expect(central, greaterThanOrEqualTo(0));
    // Advertise 2 GB uncompressed JPEG in a tiny ZIP.
    data.setUint32(central + 24, 0x7FFFFFFF, Endian.little);
    expect(() => ActorArchiveCodec.decode(forged),
        throwsFormatException);
  });

  test('refuses encrypted-entry flags before any ZIP extraction', () {
    final zipped = ActorArchiveCodec.encode(
      name: 'Actor', style: 'Cinematic', notes: '',
      photos: [jpg(70)],
    );
    final forged = Uint8List.fromList(zipped);
    final data = ByteData.sublistView(forged);
    for (var i = 0; i < forged.length - 46; i++) {
      if (data.getUint32(i, Endian.little) == 0x02014b50) {
        data.setUint16(i + 8, 1, Endian.little);
        break;
      }
    }
    expect(() => ActorArchiveCodec.decode(forged), throwsFormatException);
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
