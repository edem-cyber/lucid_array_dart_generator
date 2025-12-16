/// Simple representation of an output file produced by the generator.
class GeneratedFile {
  const GeneratedFile({required this.path, required this.content});

  /// Absolute path on disk.
  final String path;

  /// File contents.
  final String content;
}
