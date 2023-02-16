library blurhash_video;

import 'dart:io';
import 'dart:math';
import 'dart:collection';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:image/image.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';

/// Blurhash algorithm applied to video files using ffmpeg
class BlurhashVideo {
  /// Generate sequence of blurhashes from video file [path]
  /// * [workingDirectory] used for storing temporary image files, `getTemporaryDirectory()` used by default
  /// * [fps] used to specify how many hashes per second will be proceed, default to video fps
  /// * [duration] allows to cut video to specified lenght before processing, positive in seconds
  /// * [resolution] is widest side of thumbnail created from video, range from 32 to 64 pixels is enough because blurhash store just a bit of data after processing
  /// * [quality] is quality of PNG thumbnails, values in range `[0-100]`
  static Future<List<String>> generateBlurHashes(
      {required String path,
      Directory? workingDirectory,
      int? fps,
      int? duration,
      int resolution = 64,
      int quality = 100}) async {
    SplayTreeMap<int, String> hashes = SplayTreeMap<int, String>();

    // temporary directory to save images
    Directory temp;
    if (workingDirectory != null) {
      temp = workingDirectory;
    } else {
      temp = await getTemporaryDirectory();
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final destination = "${temp.path}/blurhash_video_temp_$timestamp";
    final directory = Directory(destination);
    await directory.create();

    // setup options
    final time = duration == null ? "" : "-t $duration";
    final frames = fps == null ? "" : "fps=$fps,";
    final size =
        "scale=w='if(gte(iw,ih),min($resolution,iw),-2)':h='if(lt(iw,ih),min($resolution,ih),-2)'";
    // compression_level - size/speed tradeoff, 100 is smallest file and is default, 0 - bigger file while faster
    final q = "-quality $quality -compression_level 50 -pix_fmt rgb24";

    // run ffmpeg command
    final command =
        "-hide_banner -i \"$path\" $time -vf \"$frames$size\" $q \"$destination/%d.png\"";
    final session = await FFmpegKit.execute(command);

    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      // remove temp directory and files
      await directory.delete(recursive: true);
      // produce ffmpeg output as exception
      throw "ffmpeg error: ${await session.getOutput()}";
    }

    // loop generated images
    int? numCompX, numCompY;
    await for (final file in directory.list()) {
      // skip system files & directories if any
      if (file is! File || !file.path.endsWith(".png")) continue;

      // extract id from 10.png format
      final id = basename(file.path).split(".").first;
      final index = int.parse(id);

      // read image
      final bytes = await file.readAsBytes();
      var image = decodePng(bytes);
      if (image == null) continue;

      // calculate components depending on resolution and rotation/orientation
      if (numCompX == null || numCompY == null) {
        final x = sqrt(16.0 * image.width / image.height);
        final y = x * image.height / image.width;
        numCompX = min(x.toInt() + 1, 9);
        numCompY = min(y.toInt() + 1, 9);
      }

      // generate hash
      final hash =
          BlurHash.encode(image, numCompX: numCompX, numCompY: numCompY);
      hashes[index] = hash.hash;
    }

    // clean up
    await directory.delete(recursive: true);

    return hashes.values.toList();
  }

  /// Delete all temporary directories and files created by this package
  /// May be used for clearing after application crashed
  /// * [workingDirectory] should be the same directory used for running [generateBlurHashes] function
  ///
  /// **Warning**: will delete all directories in [workingDirectory] starting with `blurhash_video_temp`
  static Future<void> cleanUp({
    Directory? workingDirectory,
  }) async {
    Directory temp;
    if (workingDirectory != null) {
      temp = workingDirectory;
    } else {
      temp = await getTemporaryDirectory();
    }

    // lookup directories in format "${temp.path}/blurhash_video_$timestamp"
    await for (final entry in temp.list()) {
      // filter files and wrong directories
      if (entry is! Directory ||
          !basename(entry.path).startsWith("blurhash_video_temp_")) continue;

      // delete the directory and all files in it
      await entry.delete(recursive: true);
    }
  }
}
