import 'dart:io';

import 'package:path/path.dart' as p;

/// User configurable options that steer the Swagger → Dart generator.
class GeneratorOptions {
  /// Creates a new set of generator options.
  GeneratorOptions({
    required this.schemaPathOrUrl,
    this.outputDirectory = 'lib/services/generated',
    this.modelsSubdirectory = 'models',
    this.servicesSubdirectory = 'services',
    this.apiServiceImportPath = 'lib/services/api_service.dart',
    this.formatOutput = true,
    this.verbose = false,
    this.defaultContentType = 'application/json',
    this.inferRequiredFromNullable = false,
    this.includeTags = const [],
    this.excludeTags = const [],
    this.schemaName,
    this.overwriteExisting = true,
    Directory? workingDirectory,
  }) : workingDirectory = workingDirectory ?? Directory.current.absolute;

  /// Path or URL to the swagger/openapi document.
  final String schemaPathOrUrl;

  /// Base output directory (relative to [workingDirectory] if not absolute).
  final String outputDirectory;

  /// Sub-directory (inside [outputDirectory]) that will host generated models.
  final String modelsSubdirectory;

  /// Sub-directory (inside [outputDirectory]) that will host generated services.
  final String servicesSubdirectory;

  /// Import path the generated services should use for `ApiService`.
  ///
  /// Defaults to the requisition-mobile location.
  final String apiServiceImportPath;

  /// Whether to run `dart format` on generated files.
  final bool formatOutput;

  /// Whether to emit verbose logging to stdout.
  final bool verbose;

  /// Fallback OpenAPI content type.
  final String defaultContentType;

  /// Mirror parser flag: infer required properties from nullability when the
  /// schema omits a `required` array.
  final bool inferRequiredFromNullable;

  /// Optional include filters for tags.
  final List<String> includeTags;

  /// Optional exclude filters for tags.
  final List<String> excludeTags;

  /// Optional explicit schema name (used for folder naming hints).
  final String? schemaName;

  /// Whether existing files may be overwritten.
  final bool overwriteExisting;

  /// Base working directory (defaults to [Directory.current]).
  final Directory workingDirectory;

  /// Absolute path to the base output directory.
  String get resolvedOutputDirectory => _resolvePath(outputDirectory);

  /// Absolute path to the models output directory.
  String get resolvedModelsDirectory =>
      p.join(resolvedOutputDirectory, modelsSubdirectory);

  /// Absolute path to the services output directory.
  String get resolvedServicesDirectory =>
      p.join(resolvedOutputDirectory, servicesSubdirectory);

  /// Absolute path to the ApiService file, used for relative imports.
  String get resolvedApiServicePath => _resolvePath(apiServiceImportPath);

  /// Resolves any path relative to [workingDirectory].
  String _resolvePath(String value) => p.normalize(
    p.isAbsolute(value) ? value : p.join(workingDirectory.path, value),
  );
}
