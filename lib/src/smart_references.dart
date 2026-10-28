import 'video_models.dart';

/// Reference metadata only. This object does not copy, encrypt, or upload
/// media; its localPath may point to a temporary picker cache file.
enum ReferenceRole { avatar, location, object, style }
enum ReferenceFormat { image, glb }
enum FaceView {
  front('Front'),
  left45('Left 45°'),
  left90('Left profile'),
  right45('Right 45°'),
  right90('Right profile'),
  up('Looking up'),
  down('Looking down');

  const FaceView(this.label);
  final String label;
}

class AvatarReference {
  const AvatarReference({
    required this.id,
    required this.ownerName,
    required this.role,
    required this.format,
    required this.mimeType,
    required this.localPath,
    this.view,
    this.isScanVerified = false,
    this.ownedTemporaryFile = false,
  });

  final String id;
  /// Avatar name or, for scene media, the owning project ID.
  final String ownerName;
  final ReferenceRole role;
  final ReferenceFormat format;
  final String mimeType;
  final String localPath;
  final FaceView? view;
  /// Must be true only after a real capture/reconstruction quality gate.
  final bool isScanVerified;
  /// Only HOTICE-generated temporary captures may be safely deleted by us.
  final bool ownedTemporaryFile;

  AvatarReference withOwner(String next) => AvatarReference(
        id: id,
        ownerName: next,
        role: role,
        format: format,
        mimeType: mimeType,
        localPath: localPath,
        view: view,
        isScanVerified: isScanVerified,
        ownedTemporaryFile: ownedTemporaryFile,
      );
}

/// A versioned identity catalog, not a claimed biometric scan or 3D model.
class AvatarAssetPack {
  AvatarAssetPack({
    required this.avatarName,
    required this.version,
    required Iterable<AvatarReference> assets,
    required this.consented,
  }) : assets = List<AvatarReference>.unmodifiable(assets);

  final String avatarName;
  final int version;
  final List<AvatarReference> assets;
  final bool consented;
}

/// Actual provider rules must come from a separately verified server catalog.
/// Demo rules are deliberately unverified and MUST NOT enable rendering.
class ReferenceModelCapability {
  ReferenceModelCapability({
    required this.modelId,
    required this.verified,
    required this.maxImages,
    required this.maxMeshes,
    required Iterable<String> supportedMimeTypes,
  }) : supportedMimeTypes = Set<String>.unmodifiable(
          supportedMimeTypes.map((s) => s.toLowerCase()),
        ) {
    if (maxImages < 0 || maxMeshes < 0) {
      throw ArgumentError('Reference limits cannot be negative.');
    }
  }

  final String modelId;
  final bool verified;
  final int maxImages;
  final int maxMeshes;
  final Set<String> supportedMimeTypes;

  bool accepts(AvatarReference asset) {
    if (!supportedMimeTypes.contains(asset.mimeType.toLowerCase())) return false;
    return asset.format == ReferenceFormat.image
        ? maxImages > 0
        : maxMeshes > 0;
  }

  /// Four slots here are purely an offline UI simulation, NEVER vendor limits.
  factory ReferenceModelCapability.demo(VideoModelProfile profile) =>
      ReferenceModelCapability(
        modelId: profile.id,
        verified: false,
        maxImages: profile.attachments.contains(VideoAttachment.image) ? 4 : 0,
        maxMeshes: 0,
        supportedMimeTypes: profile.attachments.contains(VideoAttachment.image)
            ? const ['image/jpeg', 'image/png', 'image/webp']
            : const [],
      );
}

class ReferenceSelection {
  ReferenceSelection({
    required Iterable<AvatarReference> selected,
    required Iterable<String> warnings,
    required Iterable<String> errors,
    required this.providerVerified,
  })  : selected = List<AvatarReference>.unmodifiable(selected),
        warnings = List<String>.unmodifiable(warnings),
        errors = List<String>.unmodifiable(errors);

  final List<AvatarReference> selected;
  final List<String> warnings;
  final List<String> errors;
  final bool providerVerified;

  bool get canSubmit => providerVerified && errors.isEmpty;
  int get imageCount =>
      selected.where((e) => e.format == ReferenceFormat.image).length;
  int get meshCount =>
      selected.where((e) => e.format == ReferenceFormat.glb).length;
}

/// Pure deterministic planner: no AI calls, filesystem access or API secrets.
/// A backend must revalidate owner access, upload existence and model rules.
class SmartReferencePlanner {
  static FaceView inferView(String prompt) {
    final text = prompt.toLowerCase();
    final left = RegExp(r'\b(left|ਖੱਬੇ)\b').hasMatch(text);
    final right = RegExp(r'\b(right|ਸੱਜੇ)\b').hasMatch(text);
    final degrees = RegExp(r'(\d{1,3})\s*(?:°|degrees?)')
        .firstMatch(text);
    final angle = degrees == null ? null : int.tryParse(degrees.group(1)!);
    final side = RegExp(r'\b(side|profile)\b').hasMatch(text) ||
        (angle != null && angle >= 60);
    final threeQuarter = RegExp(r'\b(three.quarter|3/4)\b').hasMatch(text) ||
        (angle != null && angle >= 25 && angle < 60);
    if (left && !right) {
      return side ? FaceView.left90 : FaceView.left45;
    }
    if (right && !left) {
      return side ? FaceView.right90 : FaceView.right45;
    }
    if (text.contains('looking up')) return FaceView.up;
    if (text.contains('looking down')) return FaceView.down;
    if (side) return FaceView.left90;
    return threeQuarter ? FaceView.left45 : FaceView.front;
  }

  static int _viewScore(FaceView? view, FaceView wanted) {
    if (view == wanted) return 100;
    if (view == FaceView.front) return 40;
    if ((wanted == FaceView.left90 && view == FaceView.left45) ||
        (wanted == FaceView.right90 && view == FaceView.right45) ||
        (wanted == FaceView.left45 && view == FaceView.left90) ||
        (wanted == FaceView.right45 && view == FaceView.right90)) {
      return 75;
    }
    if (view == null) return 10;
    return 15;
  }

  static ReferenceSelection plan({
    required AvatarAssetPack? avatarPack,
    required Iterable<AvatarReference> sceneAssets,
    required ReferenceModelCapability model,
    required String scenePrompt,
    FaceView? preferredView,
    bool autoSelect = true,
    Iterable<String> selectedIds = const [],
    Iterable<String> lockedIds = const [],
  }) {
    final warnings = <String>[];
    final errors = <String>[];
    final chosen = <AvatarReference>[];
    final all = <AvatarReference>[];
    final ids = <String>{};
    if (avatarPack != null) {
      if (!avatarPack.consented && avatarPack.assets.isNotEmpty) {
        errors.add('Avatar references require explicit consent.');
      } else {
        for (final asset in avatarPack.assets) {
          if (asset.ownerName != avatarPack.avatarName ||
              asset.role != ReferenceRole.avatar) {
            errors.add('Avatar pack contains an invalid owner or role.');
          } else {
            all.add(asset);
          }
        }
      }
    }
    for (final asset in sceneAssets) {
      if (asset.role == ReferenceRole.avatar) {
        errors.add('Scene references cannot impersonate avatar identity.');
      } else {
        all.add(asset);
      }
    }
    for (final asset in all) {
      if (asset.id.trim().isEmpty || !ids.add(asset.id)) {
        errors.add('Reference IDs must be present and unique.');
      }
    }
    if (errors.isNotEmpty) {
      return ReferenceSelection(
        selected: const [], warnings: warnings, errors: errors,
        providerVerified: model.verified,
      );
    }
    final byId = {for (final a in all) a.id: a};
    final pinned = lockedIds.toSet();
    final explicit = selectedIds.toSet()..addAll(pinned);
    int images = 0;
    int meshes = 0;

    bool append(AvatarReference item, {bool locked = false}) {
      if (chosen.any((e) => e.id == item.id)) return true;
      if (!model.accepts(item)) {
        if (locked) errors.add('Locked reference is incompatible: ${item.id}');
        return false;
      }
      final isImage = item.format == ReferenceFormat.image;
      if (isImage ? images >= model.maxImages : meshes >= model.maxMeshes) {
        if (locked) errors.add('Locked references exceed model limits.');
        return false;
      }
      chosen.add(item);
      if (isImage) { images++; } else { meshes++; }
      return true;
    }

    for (final id in pinned) {
      final asset = byId[id];
      if (asset == null) {
        errors.add('Locked reference is missing: $id');
      } else {
        append(asset, locked: true);
      }
    }
    // Manual selections are not silently replaced by automatic suggestions.
    if (!autoSelect) {
      for (final id in explicit.difference(pinned)) {
        final asset = byId[id];
        if (asset == null) {
          errors.add('Selected reference is missing: $id');
        } else if (!append(asset, locked: true)) {
          // append has already reported the precise conflict.
        }
      }
    } else {
      final wanted = preferredView ?? inferView(scenePrompt);
      final avatarAssets = all.where((a) => a.role == ReferenceRole.avatar);
      final meshAssets = avatarAssets
          .where((a) => a.format == ReferenceFormat.glb).toList();
      // A prompt saying only 'side profile' does not establish left/right.
      // Prefer an available side image to the front rather than assuming a side.
      final unspecifiedSide = preferredView == null &&
          !RegExp(r'\b(left|right)\b').hasMatch(scenePrompt.toLowerCase()) &&
          RegExp(r'\b(side|profile)\b').hasMatch(scenePrompt.toLowerCase());
      int score(FaceView? view) => unspecifiedSide &&
              (view == FaceView.left90 || view == FaceView.right90)
          ? 100 : _viewScore(view, wanted);
      final imagesByView = avatarAssets
          .where((a) => a.format == ReferenceFormat.image).toList()
        ..sort((a, b) => score(b.view).compareTo(score(a.view)));
      // Use actual native mesh only when supplied AND the provider accepts it.
      for (final mesh in meshAssets) {
        if (append(mesh)) break;
      }
      // Reserve slots for location/props. Avoid wasting four on face photos.
      final supporting = all.where((a) => a.role != ReferenceRole.avatar).toList()
        ..sort((a, b) => a.role.index.compareTo(b.role.index));
      final avatarImageBudget = (model.maxImages - supporting.length)
          .clamp(0, 2);
      var chosenAvatarImages = chosen
          .where((a) => a.role == ReferenceRole.avatar &&
              a.format == ReferenceFormat.image).length;
      for (final asset in imagesByView) {
        if (chosenAvatarImages >= avatarImageBudget) break;
        if (append(asset)) chosenAvatarImages++;
      }
      for (final asset in supporting) {
        if (!append(asset)) {
          warnings.add('Could not include ${asset.role.name} reference: ${asset.id}');
        }
      }
    }

    if (!model.verified) {
      warnings.add('Offline capability preview only; no provider is verified.');
    }
    if (avatarPack == null || avatarPack.assets.isEmpty) {
      warnings.add('No captured avatar reference assets are available.');
    } else if (!avatarPack.assets.any((a) => a.isScanVerified)) {
      warnings.add('Imported photos are not a verified 3D face scan.');
    }
    return ReferenceSelection(
      selected: chosen, warnings: warnings, errors: errors,
      providerVerified: model.verified,
    );
  }
}
