import 'dart:io';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
import 'package:flutter/material.dart';
import 'package:blurhash_video/blurhash_video.dart';
import 'package:file_picker/file_picker.dart';
import 'package:blurhash_dart/blurhash_dart.dart' as dart;
import 'package:image/image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_sequence_animator/image_sequence_animator.dart';
import 'package:video_player/video_player.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Blurhash Video Demo",
      theme: ThemeData(primarySwatch: Colors.deepOrange),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Directory? _directory;
  int _count = 0;

  VideoPlayerController? _gblurController;
  VideoPlayerController? _sequenceController;

  int _hashesSize = 0;
  int _gblurSize = 0;
  int _sequenceSize = 0;

  @override
  void dispose() async {
    super.dispose();
    _gblurController?.dispose();
    _sequenceController?.dispose();
    if (_directory?.existsSync() == true) {
      await _directory?.delete(recursive: true);
    }
  }

  void _process() async {
    // reset
    if (_directory?.existsSync() == true) {
      await _directory?.delete(recursive: true);
    }
    setState(() {
      _count = 0;
      _directory = null;
    });

    final temp = await getTemporaryDirectory();
    // print(temp.path);

    // clean all previously produced cache directories
    // await BlurhashVideo.cleanUp(workingDirectory: temp);

    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.first.path;
    if (path == null) return;

    final hashes = await BlurhashVideo.generateBlurHashes(
      path: path,
      workingDirectory: temp,
      fps: 24, // video fps is used by default
      duration: 7, // in seconds
      resolution: 64, // pixels
    );

    // temporary directory for blurred images
    final dir = Directory(
        "${temp.path}/blurhash_video_demo_${DateTime.now().millisecondsSinceEpoch}");
    await dir.create();

    // make blurred image from each hash
    for (var i = 0; i < hashes.length; i++) {
      final blurHash = dart.BlurHash.decode(hashes[i]);
      final image = blurHash.toImage(64, 36);
      await File("${dir.path}/blur${i.toString().padLeft(5, "0")}.png")
          .writeAsBytes(encodePng(image));
    }

    setState(() {
      _count = hashes.length;
      _directory = dir;
    });

    // save hashes as txt file with new line for every next one
    final contents =
        hashes.fold<String>("", (content, item) => "$content$item\n");
    final hashesFile = File("${dir.path}/hashes.txt");
    await hashesFile.writeAsString(contents);
    // file can be compressed via bzip which will cut down to 1/3 of size
    final hashesSize = await hashesFile.length() ~/ 1024;
    setState(() => _hashesSize = hashesSize);

    // generate mp4 video with gaussian blur filter
    final gblurFile = File("${dir.path}/gblur.mp4");
    final gblurSession = await FFmpegKit.execute(
        "-hide_banner -i $path -s 64x36 -t 7 -vf gblur=sigma=128:steps=4 -lossless 1 -quality 100 -an ${gblurFile.path}");
    if (!ReturnCode.isSuccess(await gblurSession.getReturnCode())) {
      // print("ffmpeg error gblur: ${await gblurSession.getOutput()}");
      _gblurController?.dispose();
      _gblurController = null;
    } else {
      setState(() {
        _gblurController = VideoPlayerController.file(gblurFile)
          ..initialize().then((_) => _gblurController!.play());
      });
    }
    final gblurSize = await gblurFile.length() ~/ 1024;
    setState(() => _gblurSize = gblurSize);

    // generate mp4 video from blurred pngs
    final sequenceFile = File("${dir.path}/blurred.mp4");
    final sequenceSession = await FFmpegKit.execute(
        "-hide_banner -framerate 24 -i ${dir.path}/blur%05d.png -vf fps=24 -t 7 -pix_fmt yuv420p ${sequenceFile.path}");
    if (!ReturnCode.isSuccess(await sequenceSession.getReturnCode())) {
      // print("ffmpeg error sequence: ${await sequenceSession.getOutput()}");
      _sequenceController?.dispose();
      _sequenceController = null;
    } else {
      setState(() {
        _sequenceController = VideoPlayerController.file(sequenceFile)
          ..initialize().then((_) => _sequenceController!.play());
      });
    }
    final sequenceSize = await sequenceFile.length() ~/ 1024;
    setState(() => _sequenceSize = sequenceSize);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Blurhash Video")),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (_directory != null) ...[
            // PNG Sequence
            ...[
              Text("PNG Sequence: $_hashesSize KB"),
              SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.width * 0.5625,
                child: Transform.scale(
                  scale: MediaQuery.of(context).size.width / 64,
                  child: ImageSequenceAnimator(
                    _directory!.path,
                    "blur",
                    0,
                    5,
                    "png",
                    _count.toDouble(),
                    fps: 24,
                    isLooping: true,
                    isBoomerang: false,
                    isAutoPlay: true,
                  ),
                ),
              )
            ],

            // MP4 from image sequence
            if (_sequenceController?.value.isInitialized == true) ...[
              Text("MP4 Blurhash: $_sequenceSize KB"),
              AspectRatio(
                aspectRatio: _sequenceController!.value.aspectRatio,
                child: VideoPlayer(_sequenceController!),
              ),
            ],

            // MP4 ffmpeg blur effect
            if (_gblurController?.value.isInitialized == true) ...[
              Text("MP4 Gaussian ffmpeg: $_gblurSize KB"),
              AspectRatio(
                aspectRatio: _gblurController!.value.aspectRatio,
                child: VideoPlayer(_gblurController!),
              ),
            ]
          ] else
            const Center(
                child: Text("Select a video",
                    style:
                        TextStyle(fontWeight: FontWeight.w500, fontSize: 18))),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _process,
        tooltip: "Select File",
        child: const Icon(Icons.file_present_rounded),
      ),
    );
  }
}
