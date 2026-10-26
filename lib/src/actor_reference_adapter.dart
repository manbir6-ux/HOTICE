import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'state.dart';
import 'video_models.dart';

/// A reusable HOTICE actor identity is a private *source* for adapter assets.
/// 3D mesh reconstruction is not implemented; a GLB can eventually be attached
/// after a separately validated reconstruction/import worker exists.
enum ActorReferenceDelivery {
  textOnly,
  individualImages,
  contactSheet,
}

class ActorImageSource {
  const ActorImageSource({
    required this.sceneName,
    required this.actorName,
    required this.path,
    required this.angle,
  });
  final String sceneName;
  final String actorName;
  final String path;
  final String angle;
}

class ActorReferencePlan {
  const ActorReferencePlan({
    required this.delivery,
    required this.sources,
    required this.imageSlots,
    required this.notes,
    required this.selectedModelId,
  });

  final ActorReferenceDelivery delivery;
  final List<ActorImageSource> sources;
  final int imageSlots;
  final List<String> notes;
  final String selectedModelId;

  /// Number of actual image attachments a properly prepared plan consumes.
  int get imageCount => switch (delivery) {
        ActorReferenceDelivery.textOnly => 0,
        ActorReferenceDelivery.contactSheet => sources.isEmpty ? 0 : 1,
        ActorReferenceDelivery.individualImages => sources.length,
      };

  bool get requiresMontage =>
      delivery == ActorReferenceDelivery.contactSheet && sources.isNotEmpty;
}

class ActorReferenceAdapter {
  /// Prepares deterministic media *choices* without network requests or key
  /// exposure. Limits here are illustrative until a signed server catalog
  /// verifies each real provider model version.
  static ActorReferencePlan plan({
    required VideoModelProfile model,
    required List<SceneActor> cast,
    required List<StudioAvatar> library,
    int otherImageAttachments = 0,
    int otherVideoAttachments = 0,
  }) {
    if (otherImageAttachments < 0 || otherVideoAttachments < 0) {
      throw StateError('Invalid attachment counts.');
    }
    final maxImage = model.maximumFor(VideoAttachment.image);
    final maxVideo = model.maximumFor(VideoAttachment.video);
    final available = maxImage - otherImageAttachments;
    if (available < 0 || otherVideoAttachments > maxVideo) {
      throw StateError('Other attachments exceed the model capability limit.');
    }
    if (cast.length > model.maxActors) {
      throw StateError('Too many actors for this model profile.');
    }
    final names = <String>{};
    final all = <List<ActorImageSource>>[];
    final notes = <String>[];
    for (final actor in cast) {
      if (actor.sceneName.trim().isEmpty ||
          !names.add(actor.sceneName.trim().toLowerCase())) {
        throw StateError('Every Actor role needs a unique name.');
      }
      final matches = library.where((item) =>
          item.name.toLowerCase() == actor.avatarName.toLowerCase());
      if (matches.length != 1) {
        throw StateError('Scene Actor is missing from the current workspace.');
      }
      final preset = matches.single;
      final paths = preset.capturePaths.where((p) => p.trim().isNotEmpty).toList();
      if (paths.isEmpty) {
        notes.add('${actor.sceneName}: no captured photos; text description only.');
        continue;
      }
      all.add([
        for (var i = 0; i < paths.length; i++)
          ActorImageSource(
            sceneName: actor.sceneName,
            actorName: preset.name,
            path: paths[i],
            angle: i == 0
                ? 'front'
                : i == 1 ? 'left'
                : i == 2 ? 'right'
                : i == 3 ? 'left-profile'
                : i == 4 ? 'right-profile'
                : i == 5 ? 'chin-up'
                : i == 6 ? 'chin-down'
                : 'angle-${i + 1}',
          ),
      ]);
    }
    if (all.isEmpty || available == 0) {
      if (available == 0 && all.isNotEmpty) {
        notes.add('All image slots are used; only Actor text notes can be included.');
      }
      return ActorReferencePlan(
        delivery: ActorReferenceDelivery.textOnly,
        sources: const [],
        imageSlots: available,
        notes: notes,
        selectedModelId: model.id,
      );
    }

    if (all.length > available) {
      // Preserve EVERY photographed actor by combining one canonical portrait
      // per actor into a single reference sheet. The sheet still needs
      // provider compatibility verification; small faces may reduce quality.
      notes.add('One composite image is required for ${all.length} Actors '
          'because only $available image reference slot(s) remain.');
      return ActorReferencePlan(
        delivery: ActorReferenceDelivery.contactSheet,
        sources: [for (final actor in all) actor.first],
        imageSlots: available,
        notes: notes,
        selectedModelId: model.id,
      );
    }

    // Fair allocation: first the front view of each Actor, then another
    // angle of each Actor while spare image slots remain.
    final chosen = <ActorImageSource>[
      for (final actor in all) actor.first,
    ];
    for (var view = 1; chosen.length < available; view++) {
      var appended = false;
      for (final actor in all) {
        if (view < actor.length && chosen.length < available) {
          chosen.add(actor[view]);
          appended = true;
        }
      }
      if (!appended) break;
    }
    return ActorReferencePlan(
      delivery: ActorReferenceDelivery.individualImages,
      sources: List.unmodifiable(chosen),
      imageSlots: available,
      notes: notes,
      selectedModelId: model.id,
    );
  }
}

/// Produces an actual *single JPEG* from actor portraits so that a model with
/// only one free image slot can still receive multiple characters as a visual
/// contact sheet. Never distorts individual portraits (contain+letterbox).
/// This is not a 3D reconstruction and never uploads data.
class ActorContactSheet {
  static img.Image compose({
    required List<img.Image> portraits,
    int cellSize = 480,
  }) {
    if (portraits.isEmpty || portraits.length > 8 ||
        cellSize < 64 || cellSize > 1024) {
      throw ArgumentError('Contact sheet requires 1–8 portraits and valid size.');
    }
    final cols = portraits.length == 1 ? 1 : 2;
    final rows = (portraits.length + cols - 1) ~/ cols;
    final sheet = img.Image(width: cols * cellSize, height: rows * cellSize);
    img.fill(sheet, color: img.ColorRgb8(23, 30, 44));
    for (var i = 0; i < portraits.length; i++) {
      final portrait = portraits[i];
      if (portrait.width <= 0 || portrait.height <= 0) {
        throw ArgumentError('Invalid portrait dimensions.');
      }
      final ratio = (cellSize - 32) / portrait.width;
      final verticalRatio = (cellSize - 32) / portrait.height;
      final scale = ratio < verticalRatio ? ratio : verticalRatio;
      final resized = img.copyResize(portrait,
          width: (portrait.width * scale).round().clamp(1, cellSize - 16),
          height: (portrait.height * scale).round().clamp(1, cellSize - 16));
      final x = (i % cols) * cellSize + (cellSize - resized.width) ~/ 2;
      final y = (i ~/ cols) * cellSize + (cellSize - resized.height) ~/ 2;
      img.compositeImage(sheet, resized, dstX: x, dstY: y);
    }
    return sheet;
  }

  static Future<String> saveToTemporaryFile(ActorReferencePlan plan) async {
    if (!plan.requiresMontage) {
      throw StateError('Only contact-sheet plans can be rendered.');
    }
    final portraits = <img.Image>[];
    for (final ref in plan.sources) {
      final file = File(ref.path);
      if (!await file.exists()) {
        throw StateError('Actor capture is missing: please recapture this Actor.');
      }
      final byteCount = await file.length();
      if (byteCount < 1 || byteCount > 16 * 1024 * 1024) {
        throw StateError('Actor photo is too large for safe local processing.');
      }
      final decoded = img.decodeImage(await file.readAsBytes());
      if (decoded == null) throw StateError('Could not decode Actor photo.');
      if (decoded.width > 6000 || decoded.height > 6000) {
        throw StateError('Actor image dimensions exceed safe processing limits.');
      }
      portraits.add(decoded);
    }
    final rendered = compose(portraits: portraits);
    final folder = Directory(
        '${(await getTemporaryDirectory()).path}/hotice_actor_reference_sheets');
    await folder.create(recursive: true);
    final output = File(
        '${folder.path}/sheet_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await output.writeAsBytes(img.encodeJpg(rendered, quality: 90), flush: true);
    return output.path;
  }
}
