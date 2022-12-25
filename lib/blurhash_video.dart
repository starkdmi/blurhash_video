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
  /// [workingDirectory] used for storing temporary image files, `getTemporaryDirectory()` used by default
  /// [fps] used to specify how many hashes per second will be proceed, default to video fps
  /// [duration] allows to cut video to specified lenght before processing, positive in seconds
  /// [resolution] is widest side of thumbnail created from video, range from 32 to 64 pixels is enough because blurhash store just a bit of data after processing
  static Future<List<String>> generateBlurHashes(
      {required String path,
      String? workingDirectory,
      int? fps,
      int? duration,
      int resolution = 64}) async {
    SplayTreeMap<int, String> hashes = SplayTreeMap<int, String>();

    // temporary directory to save images
    Directory temp;
    if (workingDirectory != null) {
      temp = Directory(workingDirectory);
    } else {
      temp = await getTemporaryDirectory();
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final destination = "${temp.path}/blurhash_video_$timestamp";
    final directory = Directory(destination);
    await directory.create();

    // run ffmpeg command
    final command =
        """ -hide_banner -i "$path" ${duration == null ? "" : "-t $duration"} ${fps == null ? "" : "-vf fps=$fps"} -vf "scale='if(gt(iw,ih),$resolution,-1)':'if(gt(iw,ih),-1,$resolution)'" -lossless 1 -quality 100 -pix_fmt rgb24 "$destination/%d.png" """;
    final session = await FFmpegKit.execute(command);

    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      throw "ffmpeg error: ${await session.getOutput()}";
    }

    // loop generated images
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
      final x = sqrt(16.0 * image.width / image.height);
      final y = x * image.height / image.width;
      final numCompX = min(x.toInt() + 1, 9);
      final numCompY = min(y.toInt() + 1, 9);

      // generate hash
      final hash =
          BlurHash.encode(image, numCompX: numCompX, numCompY: numCompY);
      hashes[index] = hash.hash;
    }

    // clean up
    await directory.delete(recursive: true);

    return hashes.values.toList();
  }
}
