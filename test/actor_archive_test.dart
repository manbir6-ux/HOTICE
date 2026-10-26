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
    );
    final restored = ActorArchiveCodec.decode(bytes);
    expect(restored.name, 'My Star');
    expect(restored.style, 'Photorealistic');
    expect(restored.notes, 'Distinctive beard');
    expect(restored.photos.length, 7);
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
      throwsA(isA<Exception>()),
    );
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
