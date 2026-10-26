import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'state.dart';

/// A deliberately unencrypted portable ZIP for *explicit* user-controlled
/// offline backups. It is sensitive face photo data, NOT a cloud transfer.
/// Nothing is exported until the user has accepted an in-app privacy warning.
class ActorArchiveImport {
  const ActorArchiveImport(this.name, this.style, this.notes, this.photos,
      {this.autoTouchUp = false});
  final String name;
  final String style;
  final String notes;
  final List<Uint8List> photos;
  final bool autoTouchUp;
}

class ActorArchiveCodec {
  static const maxPhotoBytes = 12 * 1024 * 1024;
  static const maxArchiveBytes = 75 * 1024 * 1024;
  static const maxTotalDecodedBytes = 72 * 1024 * 1024;
  static const maxPhotos = 12;

  static void _validatePhoto(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxPhotoBytes ||
        bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      throw const FormatException('Expected a valid JPG face photo.');
    }
    final decoded = img.decodeJpg(bytes);
    if (decoded == null || decoded.width < 32 || decoded.height < 32 ||
        decoded.width > 6500 || decoded.height > 6500 ||
        decoded.width * decoded.height > 18000000) {
      throw const FormatException('Actor photo has invalid dimensions or encoding.');
    }
  }

  static Uint8List encode({
    required String name,
    required String style,
    required String notes,
    required List<Uint8List> photos,
    bool autoTouchUp = false,
  }) {
    if (name.trim().isEmpty || name.length > 60 || notes.length > 350 ||
        style.isEmpty || style.length > 50 ||
        photos.isEmpty || photos.length > maxPhotos) {
      throw const FormatException('Invalid Actor profile for export.');
    }
    final size = photos.fold<int>(0, (total, photo) => total + photo.length);
    if (size > maxTotalDecodedBytes) {
      throw const FormatException('Too many photo bytes for an Actor package.');
    }
    final archive = Archive();
    final images = <String>[];
    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      _validatePhoto(photo);
      final filename = 'images/angle_${i.toString().padLeft(2, '0')}.jpg';
      images.add(filename);
      archive.addFile(ArchiveFile.bytes(filename, photo));
    }
    final manifest = jsonEncode({
      'format': 'HOTICE_ACTOR',
      'version': 1,
      'name': name.trim(),
      'style': style,
      'notes': notes,
      'images': images,
      'encrypted': false,
      'autoTouchUp': autoTouchUp,
    });
    archive.addFile(ArchiveFile.string('manifest.json', manifest));
    final zip = ZipEncoder().encodeBytes(archive);
    if (zip.length > maxArchiveBytes) {
      throw const FormatException('Actor export archive is too large.');
    }
    return zip;
  }

  /// Read the ZIP central directory *before* asking archive package to
  /// inflate any entry. A small uploaded ZIP can claim gigabytes of expanded
  /// content: checking entries only after decoding is too late for memory.
  ///
  /// Only ordinary single-disk ZIP32/stored-or-deflated HOTICE archives are
  /// supported. ZIP64, encrypted archives and incompatible extensions fail
  /// closed. This preflight complements the archive library's CRC verification.
  static void _preflightZip(Uint8List zip) {
    if (zip.length < 22) {
      throw const FormatException('Actor ZIP has no end-of-directory record.');
    }
    final bytes = ByteData.sublistView(zip);
    int u16(int at) => bytes.getUint16(at, Endian.little);
    int u32(int at) => bytes.getUint32(at, Endian.little);

    // EOCD lives within the last 65,557 bytes (maximum ZIP comment).
    var end = -1;
    final minOffset = zip.length - 65557 > 0 ? zip.length - 65557 : 0;
    for (var at = zip.length - 22; at >= minOffset; at--) {
      if (u32(at) == 0x06054b50 &&
          at + 22 + u16(at + 20) == zip.length) {
        end = at;
        break;
      }
    }
    if (end < 0 || u16(end + 4) != 0 || u16(end + 6) != 0 ||
        u16(end + 8) != u16(end + 10)) {
      throw const FormatException('Unsupported multi-disk or malformed Actor ZIP.');
    }
    final count = u16(end + 10);
    final directoryBytes = u32(end + 12);
    final directoryStart = u32(end + 16);
    if (count < 2 || count > maxPhotos + 1 ||
        directoryBytes == 0 ||
        directoryStart > end ||
        directoryBytes > end - directoryStart) {
      throw const FormatException('Actor ZIP directory is unsafe.');
    }
    var cursor = directoryStart;
    var expandedTotal = 0;
    final seen = <String>{};
    for (var i = 0; i < count; i++) {
      if (cursor > end - 46 || u32(cursor) != 0x02014b50) {
        throw const FormatException('Malformed Actor ZIP central header.');
      }
      final flags = u16(cursor + 8);
      final method = u16(cursor + 10);
      final packed = u32(cursor + 20);
      final unpacked = u32(cursor + 24);
      final nameLength = u16(cursor + 28);
      final extraLength = u16(cursor + 30);
      final commentLength = u16(cursor + 32);
      final start = cursor + 46;
      final next = start + nameLength + extraLength + commentLength;
      if ((flags & 1) != 0 ||
          (method != 0 && method != 8) ||
          packed == 0xffffffff || unpacked == 0xffffffff ||
          nameLength == 0 || next > directoryStart + directoryBytes ||
          next > end || u32(cursor + 42) >= directoryStart) {
        throw const FormatException('Unsupported or unsafe Actor ZIP entry.');
      }
      final name = utf8.decode(zip.sublist(start, start + nameLength),
          allowMalformed: false);
      if (!seen.add(name) ||
          (name != 'manifest.json' &&
              !RegExp(r'^images/angle_[0-9]{2}[.]jpg
    if (zip.isEmpty || zip.length > maxArchiveBytes) {
      throw const FormatException('Actor ZIP file is empty or too large.');
    }
    _preflightZip(zip);
    final archive = ZipDecoder().decodeBytes(zip, verify: true);
    if (archive.length < 2 || archive.length > maxPhotos + 1) {
      throw const FormatException('Unexpected number of files in Actor ZIP.');
    }
    var total = 0;
    final entries = <String, ArchiveFile>{};
    for (final entry in archive) {
      // Check paths *before* accessing compressed contents. This parser
      // never extracts arbitrary paths or creates symlinks on disk.
      final path = entry.name;
      if (!entry.isFile || entry.isSymbolicLink ||
          path.contains('..') || path.contains('\\') ||
          path.startsWith('/') || path.contains(':') ||
          (path != 'manifest.json' &&
            !RegExp(r'^images/angle_[0-9]{2}[.]jpg$').hasMatch(path))) {
        throw const FormatException('Unsafe Actor archive file or path.');
      }
      if (entries.containsKey(path) || entry.size < 0 ||
          (path == 'manifest.json' && entry.size > 8192) ||
          (path != 'manifest.json' && entry.size > maxPhotoBytes)) {
        throw const FormatException('Duplicate or oversized Actor archive entry.');
      }
      total += entry.size;
      if (total > maxTotalDecodedBytes) {
        throw const FormatException('Expanded Actor archive exceeds safety limit.');
      }
      entries[path] = entry;
    }
    final manifestData = entries['manifest.json']?.readBytes();
    if (manifestData == null || manifestData.length > 8192) {
      throw const FormatException('Actor manifest is missing.');
    }
    final parsed = jsonDecode(utf8.decode(manifestData));
    if (parsed is! Map<String, dynamic> ||
        parsed['format'] != 'HOTICE_ACTOR' || parsed['version'] != 1 ||
        parsed['encrypted'] != false ||
        (parsed['autoTouchUp'] != null && parsed['autoTouchUp'] is! bool) ||
        parsed['name'] is! String ||
        parsed['style'] is! String ||
        parsed['notes'] is! String ||
        parsed['images'] is! List) {
      throw const FormatException('Unsupported Actor package manifest.');
    }
    final name = (parsed['name'] as String).trim();
    final style = parsed['style'] as String;
    final notes = parsed['notes'] as String;
    final listed = parsed['images'] as List;
    if (name.isEmpty || name.length > 60 || style.isEmpty ||
        style.length > 50 || notes.length > 350 ||
        listed.isEmpty || listed.length > maxPhotos ||
        entries.length != listed.length + 1) {
      throw const FormatException('Actor package metadata is invalid.');
    }
    final photos = <Uint8List>[];
    for (var i = 0; i < listed.length; i++) {
      final expected = 'images/angle_${i.toString().padLeft(2, '0')}.jpg';
      if (listed[i] != expected) {
        throw const FormatException('Actor photo order or filename is invalid.');
      }
      final data = entries[expected]?.readBytes();
      if (data == null || data.length > maxPhotoBytes) {
        throw const FormatException('Missing or oversized Actor photo.');
      }
      _validatePhoto(data);
      photos.add(data);
    }
    return ActorArchiveImport(name, style, notes, List.unmodifiable(photos),
        autoTouchUp: parsed['autoTouchUp'] == true);
  }

  static Future<Uint8List> exportActor(StudioAvatar actor) async {
    if (actor.capturePaths.isEmpty) {
      throw StateError('Only Actors with guided photos can be exported.');
    }
    final photos = <Uint8List>[];
    for (final path in actor.capturePaths) {
      final file = File(path);
      if (!await file.exists() || await file.length() > maxPhotoBytes) {
        throw StateError('An Actor photo is missing or too large.');
      }
      photos.add(await file.readAsBytes());
    }
    return encode(
      name: actor.name, style: actor.style,
      notes: actor.identityNotes, photos: photos,
      autoTouchUp: actor.autoTouchUp,
    );
  }

  static Future<List<String>> importToTemporaryFolder(
      ActorArchiveImport actor) async {
    final folder = Directory(
        '${(await getTemporaryDirectory()).path}/hotice_actor_capture');
    await folder.create(recursive: true);
    // Each import receives an unguessable basename. Track a file before
    // writing because disk-full failures can leave partial plaintext JPGs.
    final random = Random.secure();
    final token = List.generate(16, (_) =>
        random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final saved = <String>[];
    try {
      for (var i = 0; i < actor.photos.length; i++) {
        _validatePhoto(actor.photos[i]);
        final file = File('${folder.path}/import_${token}_$i.jpg');
        saved.add(file.path);
        await file.writeAsBytes(actor.photos[i], flush: true);
      }
      return saved;
    } catch (_) {
      for (final path in saved) {
        try { await File(path).delete(); } catch (_) {}
      }
      rethrow;
    }
  }
}
).hasMatch(name)) ||
          (name == 'manifest.json' && unpacked > 8192) ||
          (name != 'manifest.json' && unpacked > maxPhotoBytes) ||
          (packed == 0 && unpacked != 0) ||
          (packed > 0 && unpacked > packed * 128)) {
        throw const FormatException('Actor ZIP entry exceeds safety limits.');
      }
      expandedTotal += unpacked;
      if (expandedTotal > maxTotalDecodedBytes) {
        throw const FormatException('Actor ZIP expands beyond the safe limit.');
      }
      cursor = next;
    }
    if (cursor != directoryStart + directoryBytes ||
        seen.length != count || !seen.contains('manifest.json')) {
      throw const FormatException('Actor ZIP directory does not match manifest.');
    }
  }

  static ActorArchiveImport decode(Uint8List zip) {
    if (zip.isEmpty || zip.length > maxArchiveBytes) {
      throw const FormatException('Actor ZIP file is empty or too large.');
    }
    final archive = ZipDecoder().decodeBytes(zip, verify: true);
    if (archive.length < 2 || archive.length > maxPhotos + 1) {
      throw const FormatException('Unexpected number of files in Actor ZIP.');
    }
    var total = 0;
    final entries = <String, ArchiveFile>{};
    for (final entry in archive) {
      // Check paths *before* accessing compressed contents. This parser
      // never extracts arbitrary paths or creates symlinks on disk.
      final path = entry.name;
      if (!entry.isFile || entry.isSymbolicLink ||
          path.contains('..') || path.contains('\\') ||
          path.startsWith('/') || path.contains(':') ||
          (path != 'manifest.json' &&
            !RegExp(r'^images/angle_[0-9]{2}[.]jpg$').hasMatch(path))) {
        throw const FormatException('Unsafe Actor archive file or path.');
      }
      if (entries.containsKey(path) || entry.size < 0 ||
          (path == 'manifest.json' && entry.size > 8192) ||
          (path != 'manifest.json' && entry.size > maxPhotoBytes)) {
        throw const FormatException('Duplicate or oversized Actor archive entry.');
      }
      total += entry.size;
      if (total > maxTotalDecodedBytes) {
        throw const FormatException('Expanded Actor archive exceeds safety limit.');
      }
      entries[path] = entry;
    }
    final manifestData = entries['manifest.json']?.readBytes();
    if (manifestData == null || manifestData.length > 8192) {
      throw const FormatException('Actor manifest is missing.');
    }
    final parsed = jsonDecode(utf8.decode(manifestData));
    if (parsed is! Map<String, dynamic> ||
        parsed['format'] != 'HOTICE_ACTOR' || parsed['version'] != 1 ||
        parsed['encrypted'] != false ||
        (parsed['autoTouchUp'] != null && parsed['autoTouchUp'] is! bool) ||
        parsed['name'] is! String ||
        parsed['style'] is! String ||
        parsed['notes'] is! String ||
        parsed['images'] is! List) {
      throw const FormatException('Unsupported Actor package manifest.');
    }
    final name = (parsed['name'] as String).trim();
    final style = parsed['style'] as String;
    final notes = parsed['notes'] as String;
    final listed = parsed['images'] as List;
    if (name.isEmpty || name.length > 60 || style.isEmpty ||
        style.length > 50 || notes.length > 350 ||
        listed.isEmpty || listed.length > maxPhotos ||
        entries.length != listed.length + 1) {
      throw const FormatException('Actor package metadata is invalid.');
    }
    final photos = <Uint8List>[];
    for (var i = 0; i < listed.length; i++) {
      final expected = 'images/angle_${i.toString().padLeft(2, '0')}.jpg';
      if (listed[i] != expected) {
        throw const FormatException('Actor photo order or filename is invalid.');
      }
      final data = entries[expected]?.readBytes();
      if (data == null || data.length > maxPhotoBytes) {
        throw const FormatException('Missing or oversized Actor photo.');
      }
      _validatePhoto(data);
      photos.add(data);
    }
    return ActorArchiveImport(name, style, notes, List.unmodifiable(photos),
        autoTouchUp: parsed['autoTouchUp'] == true);
  }

  static Future<Uint8List> exportActor(StudioAvatar actor) async {
    if (actor.capturePaths.isEmpty) {
      throw StateError('Only Actors with guided photos can be exported.');
    }
    final photos = <Uint8List>[];
    for (final path in actor.capturePaths) {
      final file = File(path);
      if (!await file.exists() || await file.length() > maxPhotoBytes) {
        throw StateError('An Actor photo is missing or too large.');
      }
      photos.add(await file.readAsBytes());
    }
    return encode(
      name: actor.name, style: actor.style,
      notes: actor.identityNotes, photos: photos,
      autoTouchUp: actor.autoTouchUp,
    );
  }

  static Future<List<String>> importToTemporaryFolder(
      ActorArchiveImport actor) async {
    final folder = Directory(
        '${(await getTemporaryDirectory()).path}/hotice_actor_capture');
    await folder.create(recursive: true);
    // Each import receives an unguessable basename. Track a file before
    // writing because disk-full failures can leave partial plaintext JPGs.
    final random = Random.secure();
    final token = List.generate(16, (_) =>
        random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final saved = <String>[];
    try {
      for (var i = 0; i < actor.photos.length; i++) {
        _validatePhoto(actor.photos[i]);
        final file = File('${folder.path}/import_${token}_$i.jpg');
        saved.add(file.path);
        await file.writeAsBytes(actor.photos[i], flush: true);
      }
      return saved;
    } catch (_) {
      for (final path in saved) {
        try { await File(path).delete(); } catch (_) {}
      }
      rethrow;
    }
  }
}
