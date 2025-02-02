// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'image_provider.dart';

const String _kLegacyAssetManifestFilename = 'AssetManifest.json';
const String _kAssetManifestFilename = 'AssetManifest.bin';

/// A screen with a device-pixel ratio strictly less than this value is
/// considered a low-resolution screen (typically entry-level to mid-range
/// laptops, desktop screens up to QHD, low-end tablets such as Kindle Fire).
const double _kLowDprLimit = 2.0;

/// Fetches an image from an [AssetBundle], having determined the exact image to
/// use based on the context.
///
/// Given a main asset and a set of variants, AssetImage chooses the most
/// appropriate asset for the current context, based on the device pixel ratio
/// and size given in the configuration passed to [resolve].
///
/// To show a specific image from a bundle without any asset resolution, use an
/// [AssetBundleImageProvider].
///
/// ## Naming assets for matching with different pixel densities
///
/// Main assets are presumed to match a nominal pixel ratio of 1.0. To specify
/// assets targeting different pixel ratios, place the variant assets in
/// the application bundle under subdirectories named in the form "Nx", where
/// N is the nominal device pixel ratio for that asset.
///
/// For example, suppose an application wants to use an icon named
/// "heart.png". This icon has representations at 1.0 (the main icon), as well
/// as 2.0 and 4.0 pixel ratios (variants). The asset bundle should then
/// contain the following assets:
///
///     heart.png
///     2.0x/heart.png
///     4.0x/heart.png
///
/// On a device with a 1.0 device pixel ratio, the image chosen would be
/// heart.png; on a device with a 2.0 device pixel ratio, the image chosen
/// would be 2.0x/heart.png; on a device with a 4.0 device pixel ratio, the
/// image chosen would be 4.0x/heart.png.
///
/// On a device with a device pixel ratio that does not exactly match an
/// available asset the "best match" is chosen. Which asset is the best depends
/// on the screen. Low-resolution screens (those with device pixel ratio
/// strictly less than 2.0) use a different matching algorithm from the
/// high-resolution screen. Because in low-resolution screens the physical
/// pixels are visible to the user upscaling artifacts (e.g. blurred edges) are
/// more pronounced. Therefore, a higher resolution asset is chosen, if
/// available. For higher-resolution screens, where individual physical pixels
/// are not visible to the user, the asset variant with the pixel ratio that's
/// the closest to the screen's device pixel ratio is chosen.
///
/// For example, for a screen with device pixel ratio 1.25 the image chosen
/// would be 2.0x/heart.png, even though heart.png (i.e. 1.0) is closer. This
/// is because the screen is considered low-resolution. For a screen with
/// device pixel ratio of 2.25 the image chosen would also be 2.0x/heart.png.
/// This is because the screen is considered to be a high-resolution screen,
/// and therefore upscaling a 2.0x image to 2.25 won't result in visible
/// upscaling artifacts. However, for a screen with device-pixel ratio 3.25 the
/// image chosen would be 4.0x/heart.png because it's closer to 4.0 than it is
/// to 2.0.
///
/// Choosing a higher-resolution image than necessary may waste significantly
/// more memory if the difference between the screen device pixel ratio and
/// the device pixel ratio of the image is high. To reduce memory usage,
/// consider providing more variants of the image. In the example above adding
/// a 3.0x/heart.png variant would improve memory usage for screens with device
/// pixel ratios between 3.0 and 3.5.
///
/// [ImageConfiguration] can be used to customize the selection of the image
/// variant by setting [ImageConfiguration.devicePixelRatio] to value different
/// from the default. The default value is derived from
/// [MediaQueryData.devicePixelRatio] by [createLocalImageConfiguration].
///
/// The directory level of the asset does not matter as long as the variants are
/// at the equivalent level; that is, the following is also a valid bundle
/// structure:
///
///     icons/heart.png
///     icons/1.5x/heart.png
///     icons/2.0x/heart.png
///
/// assets/icons/3.0x/heart.png would be a valid variant of
/// assets/icons/heart.png.
///
/// ## Fetching assets
///
/// When fetching an image provided by the app itself, use the [assetName]
/// argument to name the asset to choose. For instance, consider the structure
/// above. First, the `pubspec.yaml` of the project should specify its assets in
/// the `flutter` section:
///
/// ```yaml
/// flutter:
///   assets:
///     - icons/heart.png
/// ```
///
/// Then, to fetch the image, use:
/// ```dart
/// const AssetImage('icons/heart.png')
/// ```
///
/// {@tool snippet}
///
/// The following shows the code required to write a widget that fully conforms
/// to the [AssetImage] and [Widget] protocols. (It is essentially a
/// bare-bones version of the [widgets.Image] widget made to work specifically for
/// an [AssetImage].)
///
/// ```dart
/// class MyImage extends StatefulWidget {
///   const MyImage({
///     super.key,
///     required this.assetImage,
///   });
///
///   final AssetImage assetImage;
///
///   @override
///   State<MyImage> createState() => _MyImageState();
/// }
///
/// class _MyImageState extends State<MyImage> {
///   ImageStream? _imageStream;
///   ImageInfo? _imageInfo;
///
///   @override
///   void didChangeDependencies() {
///     super.didChangeDependencies();
///     // We call _getImage here because createLocalImageConfiguration() needs to
///     // be called again if the dependencies changed, in case the changes relate
///     // to the DefaultAssetBundle, MediaQuery, etc, which that method uses.
///     _getImage();
///   }
///
///   @override
///   void didUpdateWidget(MyImage oldWidget) {
///     super.didUpdateWidget(oldWidget);
///     if (widget.assetImage != oldWidget.assetImage) {
///       _getImage();
///     }
///   }
///
///   void _getImage() {
///     final ImageStream? oldImageStream = _imageStream;
///     _imageStream = widget.assetImage.resolve(createLocalImageConfiguration(context));
///     if (_imageStream!.key != oldImageStream?.key) {
///       // If the keys are the same, then we got the same image back, and so we don't
///       // need to update the listeners. If the key changed, though, we must make sure
///       // to switch our listeners to the new image stream.
///       final ImageStreamListener listener = ImageStreamListener(_updateImage);
///       oldImageStream?.removeListener(listener);
///       _imageStream!.addListener(listener);
///     }
///   }
///
///   void _updateImage(ImageInfo imageInfo, bool synchronousCall) {
///     setState(() {
///       // Trigger a build whenever the image changes.
///       _imageInfo?.dispose();
///       _imageInfo = imageInfo;
///     });
///   }
///
///   @override
///   void dispose() {
///     _imageStream?.removeListener(ImageStreamListener(_updateImage));
///     _imageInfo?.dispose();
///     _imageInfo = null;
///     super.dispose();
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     return RawImage(
///       image: _imageInfo?.image, // this is a dart:ui Image object
///       scale: _imageInfo?.scale ?? 1.0,
///     );
///   }
/// }
/// ```
/// {@end-tool}
///
/// ## Assets in packages
///
/// To fetch an asset from a package, the [package] argument must be provided.
/// For instance, suppose the structure above is inside a package called
/// `my_icons`. Then to fetch the image, use:
///
/// ```dart
/// const AssetImage('icons/heart.png', package: 'my_icons')
/// ```
///
/// Assets used by the package itself should also be fetched using the [package]
/// argument as above.
///
/// If the desired asset is specified in the `pubspec.yaml` of the package, it
/// is bundled automatically with the app. In particular, assets used by the
/// package itself must be specified in its `pubspec.yaml`.
///
/// A package can also choose to have assets in its 'lib/' folder that are not
/// specified in its `pubspec.yaml`. In this case for those images to be
/// bundled, the app has to specify which ones to include. For instance a
/// package named `fancy_backgrounds` could have:
///
///     lib/backgrounds/background1.png
///     lib/backgrounds/background2.png
///     lib/backgrounds/background3.png
///
/// To include, say the first image, the `pubspec.yaml` of the app should specify
/// it in the `assets` section:
///
/// ```yaml
///   assets:
///     - packages/fancy_backgrounds/backgrounds/background1.png
/// ```
///
/// The `lib/` is implied, so it should not be included in the asset path.
///
/// See also:
///
///  * [Image.asset] for a shorthand of an [Image] widget backed by [AssetImage]
///    when used without a scale.
@immutable
class AssetImage extends AssetBundleImageProvider {
  /// Creates an object that fetches an image from an asset bundle.
  ///
  /// The [assetName] argument must not be null. It should name the main asset
  /// from the set of images to choose from. The [package] argument must be
  /// non-null when fetching an asset that is included in package. See the
  /// documentation for the [AssetImage] class itself for details.
  const AssetImage(
    this.assetName, {
    this.bundle,
    this.package,
  }) : assert(assetName != null);

  /// The name of the main asset from the set of images to choose from. See the
  /// documentation for the [AssetImage] class itself for details.
  final String assetName;

  /// The name used to generate the key to obtain the asset. For local assets
  /// this is [assetName], and for assets from packages the [assetName] is
  /// prefixed 'packages/<package_name>/'.
  String get keyName => package == null ? assetName : 'packages/$package/$assetName';

  /// The bundle from which the image will be obtained.
  ///
  /// If the provided [bundle] is null, the bundle provided in the
  /// [ImageConfiguration] passed to the [resolve] call will be used instead. If
  /// that is also null, the [rootBundle] is used.
  ///
  /// The image is obtained by calling [AssetBundle.load] on the given [bundle]
  /// using the key given by [keyName].
  final AssetBundle? bundle;

  /// The name of the package from which the image is included. See the
  /// documentation for the [AssetImage] class itself for details.
  final String? package;

  // We assume the main asset is designed for a device pixel ratio of 1.0
  static const double _naturalResolution = 1.0;

  @override
  Future<AssetBundleImageKey> obtainKey(ImageConfiguration configuration) {
    // This function tries to return a SynchronousFuture if possible. We do this
    // because otherwise showing an image would always take at least one frame,
    // which would be sad. (This code is called from inside build/layout/paint,
    // which all happens in one call frame; using native Futures would guarantee
    // that we resolve each future in a new call frame, and thus not in this
    // build/layout/paint sequence.)
    final AssetBundle chosenBundle = bundle ?? configuration.bundle ?? rootBundle;
    Completer<AssetBundleImageKey>? completer;
    Future<AssetBundleImageKey>? result;

    Future<_AssetManifest> loadJsonAssetManifest() {
      Future<_AssetManifest> parseJson(String data) {
        final _AssetManifest parsed = _LegacyAssetManifest.fromJsonString(data);
        return SynchronousFuture<_AssetManifest>(parsed);
      }
      return chosenBundle.loadStructuredData(_kLegacyAssetManifestFilename, parseJson);
    }

    // TODO(andrewkolos): Once google3 and google-fonts-flutter are migrated
    // away from using AssetManifest.json, remove all references to it.
    // See https://github.com/flutter/flutter/issues/114913.
    Future<_AssetManifest>? manifest;

    // Since AssetBundle load calls can be synchronous (e.g. in the case of tests),
    // it is not sufficient to only use catchError/onError or the onError parameter
    // of Future.then--we also have to use a synchronous try/catch. Once google3
    // tooling starts producing AssetManifest.bin, this block can be removed.
    try {
      manifest = chosenBundle.loadStructuredBinaryData(_kAssetManifestFilename, _AssetManifestBin.fromStandardMessageCodecMessage);
    } catch (error) {
      manifest = loadJsonAssetManifest();
    }

    manifest
      // To understand why we use this no-op `then` instead of `catchError`/`onError`,
      // see https://github.com/flutter/flutter/issues/115601
      .then((_AssetManifest manifest) => manifest,
          onError: (Object? error, StackTrace? stack) => loadJsonAssetManifest())
      .then((_AssetManifest manifest) {
        final List<_AssetVariant> candidateVariants = manifest.getVariants(keyName);
        final _AssetVariant chosenVariant = _chooseVariant(
          keyName,
          configuration,
          candidateVariants,
        );
        final AssetBundleImageKey key = AssetBundleImageKey(
          bundle: chosenBundle,
          name: chosenVariant.asset,
          scale: chosenVariant.devicePixelRatio,
        );
        if (completer != null) {
          // We already returned from this function, which means we are in the
          // asynchronous mode. Pass the value to the completer. The completer's
          // future is what we returned.
          completer.complete(key);
        } else {
          // We haven't yet returned, so we must have been called synchronously
          // just after loadStructuredData returned (which means it provided us
          // with a SynchronousFuture). Let's return a SynchronousFuture
          // ourselves.
          result = SynchronousFuture<AssetBundleImageKey>(key);
        }
      })
      .onError((Object error, StackTrace stack) {
        // We had an error. (This guarantees we weren't called synchronously.)
        // Forward the error to the caller.
        assert(completer != null);
        assert(result == null);
        completer!.completeError(error, stack);
      });

    if (result != null) {
      // The code above ran synchronously, and came up with an answer.
      // Return the SynchronousFuture that we created above.
      return result!;
    }
    // The code above hasn't yet run its "then" handler yet. Let's prepare a
    // completer for it to use when it does run.
    completer = Completer<AssetBundleImageKey>();
    return completer.future;
  }

  /// Parses the asset manifest's file contents into it's Dart representation.
  @visibleForTesting
  // Return type is set to Object?, because the specific type is private.
  static Object? parseAssetManifest(ByteData bytes) {
    return _AssetManifestBin.fromStandardMessageCodecMessage(bytes);
  }

  _AssetVariant _chooseVariant(String mainAssetKey, ImageConfiguration config, List<_AssetVariant> candidateVariants) {
    final _AssetVariant mainAsset = _AssetVariant(asset: mainAssetKey,
      devicePixelRatio: _naturalResolution);
    if (config.devicePixelRatio == null || candidateVariants.isEmpty) {
      return mainAsset;
    }
    final SplayTreeMap<double, _AssetVariant> candidatesByDevicePixelRatio =
      SplayTreeMap<double, _AssetVariant>();
    for (final _AssetVariant candidate in candidateVariants) {
      candidatesByDevicePixelRatio[candidate.devicePixelRatio] = candidate;
    }
    candidatesByDevicePixelRatio.putIfAbsent(_naturalResolution, () => mainAsset);
    // TODO(ianh): implement support for config.locale, config.textDirection,
    // config.size, config.platform (then document this over in the Image.asset
    // docs)
    return _findBestVariant(candidatesByDevicePixelRatio, config.devicePixelRatio!);
  }

  // Returns the "best" asset variant amongst the available `candidates`.
  //
  // The best variant is chosen as follows:
  // - Choose a variant whose key matches `value` exactly, if available.
  // - If `value` is less than the lowest key, choose the variant with the
  //   lowest key.
  // - If `value` is greater than the highest key, choose the variant with
  //   the highest key.
  // - If the screen has low device pixel ratio, choose the variant with the
  //   lowest key higher than `value`.
  // - If the screen has high device pixel ratio, choose the variant with the
  //   key nearest to `value`.
  _AssetVariant _findBestVariant(SplayTreeMap<double, _AssetVariant> candidatesByDpr, double value) {
    if (candidatesByDpr.containsKey(value)) {
      return candidatesByDpr[value]!;
    }
    final double? lower = candidatesByDpr.lastKeyBefore(value);
    final double? upper = candidatesByDpr.firstKeyAfter(value);
    if (lower == null) {
      return candidatesByDpr[upper]!;
    }
    if (upper == null) {
      return candidatesByDpr[lower]!;
    }

    // On screens with low device-pixel ratios the artifacts from upscaling
    // images are more visible than on screens with a higher device-pixel
    // ratios because the physical pixels are larger. Choose the higher
    // resolution image in that case instead of the nearest one.
    if (value < _kLowDprLimit || value > (lower + upper) / 2) {
      return candidatesByDpr[upper]!;
    } else {
      return candidatesByDpr[lower]!;
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is AssetImage
        && other.keyName == keyName
        && other.bundle == bundle;
  }

  @override
  int get hashCode => Object.hash(keyName, bundle);

  @override
  String toString() => '${objectRuntimeType(this, 'AssetImage')}(bundle: $bundle, name: "$keyName")';
}

/// Centralizes parsing and typecasting of the contents of the asset manifest file,
/// which is generated by the flutter tool at build time.
abstract class _AssetManifest {
  List<_AssetVariant> getVariants(String key);
}

/// Parses the binary asset manifest into a data structure that's easier to work with.
///
/// The asset manifest is a map of asset files to a list of objects containing
/// information about variants of that asset.
///
/// The entries with each variant object are:
///  - "asset": the location of this variant to load it from.
///  - "dpr": The device-pixel-ratio that the asset is best-suited for.
///
/// New fields could be added to this object schema to support new asset variation
/// features, such as themes, locale/region support, reading directions, and so on.
class _AssetManifestBin implements _AssetManifest {
  _AssetManifestBin(Map<Object?, Object?> standardMessageData): _data = standardMessageData;

  factory _AssetManifestBin.fromStandardMessageCodecMessage(ByteData message) {
    final Object? data = const StandardMessageCodec().decodeMessage(message);
    return _AssetManifestBin(data! as Map<Object?, Object?>);
  }

  final Map<Object?, Object?> _data;
  final Map<String, List<_AssetVariant>> _typeCastedData = <String, List<_AssetVariant>>{};

  @override
  List<_AssetVariant> getVariants(String key) {
    // We lazily delay typecasting to prevent a performance hiccup when parsing
    // large asset manifests.
    if (!_typeCastedData.containsKey(key)) {
      _typeCastedData[key] = ((_data[key] ?? <Object?>[]) as List<Object?>)
        .cast<Map<Object?, Object?>>()
        .map(_AssetVariant.fromManifestData)
        .toList();
    }
    return _typeCastedData[key]!;
  }
}

class _LegacyAssetManifest implements _AssetManifest {
  _LegacyAssetManifest({
    required this.manifest,
  });

  factory _LegacyAssetManifest.fromJsonString(String jsonString) {
    List<_AssetVariant> adaptLegacyVariantList(String mainAsset, List<String> variants) {
      return variants
        .map((String variant) =>
          _AssetVariant(asset: variant, devicePixelRatio: _parseScale(mainAsset, variant)))
        .toList();
    }

    if (jsonString == null) {
      return _LegacyAssetManifest(manifest: <String, List<_AssetVariant>>{});
    }
    final Map<String, Object?> parsedJson = json.decode(jsonString) as Map<String, dynamic>;
    final Iterable<String> keys = parsedJson.keys;
    final Map<String, List<String>> parsedManifest = <String, List<String>> {
      for (final String key in keys) key: List<String>.from(parsedJson[key]! as List<dynamic>),
    };
    final Map<String, List<_AssetVariant>> manifestWithParsedVariants =
      parsedManifest.map((String asset, List<String> variants) =>
        MapEntry<String, List<_AssetVariant>>(asset, adaptLegacyVariantList(asset, variants)));

    return _LegacyAssetManifest(manifest: manifestWithParsedVariants);
  }

  final Map<String, List<_AssetVariant>> manifest;

  static final RegExp _extractRatioRegExp = RegExp(r'/?(\d+(\.\d*)?)x$');
  static const double _naturalResolution = 1.0;

  @override
  List<_AssetVariant> getVariants(String key) {
    return manifest[key] ?? const <_AssetVariant>[];
  }

  static double _parseScale(String mainAsset, String variant) {
    // The legacy asset manifest includes the main asset within its variant list.
    if (mainAsset == variant) {
      return _naturalResolution;
    }

    final Uri assetUri = Uri.parse(variant);
    String directoryPath = '';
    if (assetUri.pathSegments.length > 1) {
      directoryPath = assetUri.pathSegments[assetUri.pathSegments.length - 2];
    }

    final Match? match = _extractRatioRegExp.firstMatch(directoryPath);
    if (match != null && match.groupCount > 0) {
      return double.parse(match.group(1)!);
    }

    return _naturalResolution; // i.e. default to 1.0x
  }
}

class _AssetVariant {
  _AssetVariant({
    required this.asset,
    required this.devicePixelRatio,
  });

  factory _AssetVariant.fromManifestData(Object data) {
    final Map<Object?, Object?> asStructuredData = data as Map<Object?, Object?>;
    return _AssetVariant(asset: asStructuredData['asset']! as String,
      devicePixelRatio: asStructuredData['dpr']! as double);
  }

  final double devicePixelRatio;
  final String asset;
}
