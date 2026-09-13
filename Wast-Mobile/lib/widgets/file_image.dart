import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Reads the bytes of a picked [file]. On Flutter Web, `image_picker`
/// produces a `File` wrapping a `blob:` URL — `dart:io`'s `File` is a
/// non-functional stub there, so `file.readAsBytes()` throws
/// `Unsupported operation: _Namespace` rather than the actual bytes.
/// Fetching the blob: URL over HTTP (which the browser resolves locally)
/// is the only working way to get bytes back out of it on web.
Future<Uint8List> readFileBytes(File file) async {
  if (kIsWeb) {
    final res = await http.get(Uri.parse(file.path));
    return res.bodyBytes;
  }
  return file.readAsBytes();
}

/// Displays a picked [File] as an image. `Image.file` throws on Flutter
/// Web ("Image.file is not supported... Consider using Image.memory"),
/// so this reads the bytes and uses `Image.memory` there instead, while
/// staying `Image.file` (cheaper, no full read) on every other platform.
class FileImageView extends StatelessWidget {
  final File file;
  final BoxFit fit;
  final double? width;
  final double? height;

  const FileImageView(this.file, {super.key, this.fit = BoxFit.cover, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return Image.file(file, fit: fit, width: width, height: height);
    }
    return FutureBuilder<Uint8List>(
      future: readFileBytes(file),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SizedBox(
            width: width,
            height: height,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return Image.memory(snapshot.data!, fit: fit, width: width, height: height);
      },
    );
  }
}

/// A CircleAvatar that shows a picked [file] (via [FileImageView], so it
/// works on web too) when present, falling back to [child] (e.g. initials)
/// otherwise — same shape as `CircleAvatar(backgroundImage: FileImage(...))`
/// without that constructor's web crash.
class FileCircleAvatar extends StatelessWidget {
  final File? file;
  final double radius;
  final Color? backgroundColor;
  final Widget? child;

  const FileCircleAvatar({super.key, required this.file, required this.radius, this.backgroundColor, this.child});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: file != null
          ? ClipOval(
              child: FileImageView(file!, width: radius * 2, height: radius * 2, fit: BoxFit.cover),
            )
          : child,
    );
  }
}
