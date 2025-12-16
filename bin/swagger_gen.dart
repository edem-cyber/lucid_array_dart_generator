import 'dart:io';

import 'package:args/args.dart';
import 'package:lucid_array_dart_generator/lucid_array_dart_generator.dart';

void main(List<String> arguments) async {
  final parser =
      ArgParser()
        ..addOption(
          'output',
          abbr: 'o',
          help: 'Base output directory for generated files.',
          defaultsTo: 'lib/services/generated',
        )
        ..addOption(
          'models',
          abbr: 'm',
          help: 'Models subdirectory (inside --output).',
          defaultsTo: 'models',
        )
        ..addOption(
          'services',
          abbr: 's',
          help: 'Services subdirectory (inside --output).',
          defaultsTo: 'services',
        )
        ..addOption(
          'base-path',
          help: 'Base path that relative paths should resolve against.',
        )
        ..addOption(
          'api-service-path',
          help: 'Path to ApiService implementation.',
          defaultsTo: 'lib/services/api_service.dart',
        )
        ..addFlag('verbose', help: 'Enable verbose logging.', defaultsTo: false)
        ..addFlag(
          'format',
          help: 'Run dart format on generated files.',
          defaultsTo: true,
        )
        ..addFlag(
          'overwrite',
          help: 'Overwrite existing files.',
          defaultsTo: true,
        )
        ..addFlag(
          'help',
          abbr: 'h',
          help: 'Print usage information.',
          negatable: false,
        );

  late ArgResults argResults;
  try {
    argResults = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  if (argResults['help'] as bool) {
    stdout
      ..writeln('Usage: dart run swagger_gen <schema> [options]')
      ..writeln(parser.usage);
    return;
  }

  if (argResults.rest.isEmpty) {
    stderr.writeln('Error: Missing <schema> argument.');
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final schema = argResults.rest.first;
  final basePath = argResults['base-path'] as String?;

  final options = GeneratorOptions(
    schemaPathOrUrl: schema,
    outputDirectory: argResults['output'] as String,
    modelsSubdirectory: argResults['models'] as String,
    servicesSubdirectory: argResults['services'] as String,
    apiServiceImportPath: argResults['api-service-path'] as String,
    verbose: argResults['verbose'] as bool,
    formatOutput: argResults['format'] as bool,
    overwriteExisting: argResults['overwrite'] as bool,
    workingDirectory:
        basePath != null
            ? Directory(basePath).absolute
            : Directory.current.absolute,
  );

  final generator = SwaggerCodeGenerator(options);

  try {
    final summary = await generator.generate();
    stdout
      ..writeln(
        'Generated ${summary.modelFilesWritten.length} model files → ${summary.outputDirectories['models']}',
      )
      ..writeln(
        'Generated ${summary.serviceFilesWritten.length} service files → ${summary.outputDirectories['services']}',
      );
    if (summary.warnings.isNotEmpty) {
      stdout.writeln('Warnings:');
      for (final warning in summary.warnings) {
        stdout.writeln('  - $warning');
      }
    }
  } catch (error, stackTrace) {
    stderr
      ..writeln('Generation failed: $error')
      ..writeln(stackTrace);
    exitCode = 1;
  }
}
