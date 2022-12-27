## About
[Blurhash](https://github.com/woltapp/blurhash/) algorithm applied to sequence of images extracted from video file

Compressed list of hashes for 7 seconds video file with 16 frames per second has size of 5KB (bzip, 15KB uncompressed)

## Preview
[Video preview](https://user-images.githubusercontent.com/21260939/209480508-4a372ae0-c4d5-4d92-82e8-305bea7838e4.mp4)

## Getting started

Include latest version from [pub.dev](https://pub.dev/packages/blurhash_video) to `pubspec.yaml`

## Usage

```dart
// generate sorted list of blurhashes from video 
final hashes = await BlurhashVideo.generateBlurHashes(
  path: path, // video file location 
  fps: 24, // video fps is used by default
  duration: 7, // in seconds
);
```
