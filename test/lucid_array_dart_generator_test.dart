import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:lucid_array_dart_generator/lucid_array_dart_generator.dart';

void main() {
  test('resolves output directories relative to base path', () {
    final tempDir = Directory.systemTemp.createTempSync();
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final options = GeneratorOptions(
      schemaPathOrUrl: 'schema.yaml',
      workingDirectory: tempDir,
      outputDirectory: 'generated',
      modelsSubdirectory: 'models',
      servicesSubdirectory: 'services',
    );

    expect(
      options.resolvedModelsDirectory,
      p.join(tempDir.path, 'generated', 'models'),
    );
    expect(
      options.resolvedServicesDirectory,
      p.join(tempDir.path, 'generated', 'services'),
    );
  });
}
