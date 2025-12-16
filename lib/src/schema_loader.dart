import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Result of loading a schema file or URL.
class SchemaDocument {
  const SchemaDocument({
    required this.contents,
    required this.isJson,
    required this.sourceLabel,
  });

  /// Raw schema contents.
  final String contents;

  /// Whether the source should be interpreted as JSON.
  final bool isJson;

  /// Human readable description of the source (path, URL, etc.).
  final String sourceLabel;
}

/// Loads OpenAPI documents from either local files or remote URLs.
class SchemaLoader {
  SchemaLoader(this.location, {Directory? workingDirectory})
    : workingDirectory = workingDirectory ?? Directory.current;

  /// Schema path or URL.
  final String location;
  final Directory workingDirectory;

  /// Loads the schema and infers whether it is JSON or YAML.
  Future<SchemaDocument> load() async {
    final uri = Uri.tryParse(location);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      return _loadFromNetwork(uri);
    }

    final resolvedPath =
        p.isAbsolute(location)
            ? location
            : p.join(workingDirectory.path, location);
    final file = File(resolvedPath);
    if (!file.existsSync()) {
      throw ArgumentError.value(
        location,
        'location',
        'Schema file does not exist.',
      );
    }
    final contents = await file.readAsString();
    return SchemaDocument(
      contents: contents,
      isJson: _looksLikeJson(file.path, contents),
      sourceLabel: file.path,
    );
  }

  Future<SchemaDocument> _loadFromNetwork(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Failed to download schema (${response.statusCode}).',
          uri: uri,
        );
      }
      return SchemaDocument(
        contents: body,
        isJson: _looksLikeJson(uri.path, body),
        sourceLabel: uri.toString(),
      );
    } finally {
      client.close();
    }
  }

  bool _looksLikeJson(String path, String contents) {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.json') {
      return true;
    }
    if (ext == '.yaml' || ext == '.yml') {
      return false;
    }
    final trimmed = contents.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }
}
