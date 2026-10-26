import 'dart:convert';
import 'dart:io';
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


  /// Inspect the ZIP directory before inflating potentially hostile archives.
  static void _preflightZip(Uint8List zip) {
    if (zip.length < 22) throw const FormatException('Invalid ZIP footer.');
    final data = ByteData.sublistView(zip);
    const eocd = 0x06054b50;
    const central = 0x02014b50;
    final earliest = zip.length > 65557 ? zip.length - 65557 : 0;
    var footer = -1;
    for (var i = zip.length - 22; i >= earliest; i--) {
      if (data.getUint32(i, Endian.little) == eocd &&
          i + 22 + data.getUint16(i + 20, Endian.little) == zip.length) {
        footer = i;
        break;
      }
    }
    if (footer < 0) {
      throw const FormatException('ZIP central directory is missing.');
    }
    final entries = data.getUint16(footer + 10, Endian.little);
    final size = data.getUint32(footer + 12, Endian.little);
    final offset = data.getUint32(footer + 16, Endian.little);
    if (data.getUint16(footer + 4, Endian.little) != 0 ||
        data.getUint16(footer + 6, Endian.little) != 0 ||
        data.getUint16(footer + 8, Endian.little) != entries ||
        entries < 2 || entries > maxPhotos + 1 ||
        offset == 0xFFFFFFFF || size == 0xFFFFFFFF ||
        offset + size > footer) {
      throw const FormatException('Unsupported ZIP directory.');
    }
    var pointer = offset;
    var totalExpanded = 0;
    var totalCompressed = 0;
    final names = <String>{};
    for (var index = 0; index < entries; index++) {
      if (pointer + 46 > footer ||
          data.getUint32(pointer, Endian.little) != central) {
        throw const FormatException('ZIP contains malformed entries.');
      }
      final flags = data.getUint16(pointer + 8, Endian.little);
      final method = data.getUint16(pointer + 10, Endian.little);
      final compressed = data.getUint32(pointer + 20, Endian.little);
      final expanded = data.getUint32(pointer + 24, Endian.little);
      final nameLength = data.getUint16(pointer + 28, Endian.little);
      final extraLength = data.getUint16(pointer + 30, Endian.little);
      final commentLength = data.getUint16(pointer + 32, Endian.little);
      final next = pointer + 46 + nameLength + extraLength + commentLength;
      if (next > offset + size || next > footer ||
          nameLength < 1 || nameLength > 64 ||
          compressed == 0xFFFFFFFF || expanded == 0xFFFFFFFF ||
          (flags & 1) != 0 || (method != 0 && method != 8)) {
        throw const FormatException('Unsupported or encrypted ZIP entry.');
      }
      final nameBytes = zip.sublist(pointer + 46, pointer + 46 + nameLength);
      if (nameBytes.any((v) => v < 32 || v > 126)) {
        throw const FormatException('Unsupported Actor ZIP filename.');
      }
      final name = ascii.decode(nameBytes);
      if (!names.add(name) ||
          (name != 'manifest.json' &&
           !RegExp(r'^images/angle_[0-9]{2}[.]jpg$').hasMatch(name)) ||
          expanded > (name == 'manifest.json' ? 8192 : maxPhotoBytes)) {
        throw const FormatException('Actor ZIP entry is unsafe or oversized.');
      }
      totalExpanded += expanded;
      totalCompressed += compressed;
      if (totalExpanded > maxTotalDecodedBytes ||
          totalCompressed > maxArchiveBytes) {
        throw const FormatException('Actor ZIP exceeds decompression budget.');
      }
      pointer = next;
    }
    if (pointer != offset + size || !names.contains('manifest.json')) {
      throw const FormatException('Actor ZIP directory count is inconsistent.');
    }
  }

  static ActorArchiveImport decode(Uint8List zip) {
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
      ActorArchiveImport actor, {Directory? cacheRoot}) async {
    final root = cacheRoot ?? await getTemporaryDirectory();
    final folder = Directory('${root.path}/hotice_actor_capture');
    await folder.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final saved = <String>[];
    try {
      for (var i = 0; i < actor.photos.length; i++) {
        final file = File('${folder.path}/import_${stamp}_$i.jpg');
        await file.writeAsBytes(actor.photos[i], flush: true);
        saved.add(file.path);
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
