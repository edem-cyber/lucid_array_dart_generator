import 'dart:io';

import 'package:swagger_parser/src/parser/config/parser_config.dart';
import 'package:swagger_parser/src/parser/parser/open_api_parser.dart';

import 'generator_options.dart';
import 'generated_file.dart';
import 'model_generator.dart';
import 'schema_loader.dart';
import 'service_generator.dart';

/// Summary of a generator run.
class GenerationSummary {
  GenerationSummary({
    required this.modelFilesWritten,
    required this.serviceFilesWritten,
    required this.warnings,
    required this.outputDirectories,
  });

  final List<String> modelFilesWritten;
  final List<String> serviceFilesWritten;
  final List<String> warnings;
  final Map<String, String> outputDirectories;
}

/// Coordinates schema parsing and file generation.
class SwaggerCodeGenerator {
  SwaggerCodeGenerator(this.options);

  final GeneratorOptions options;

  Future<GenerationSummary> generate() async {
    _log('Resolving schema...');
    final schema =
        await SchemaLoader(
          options.schemaPathOrUrl,
          workingDirectory: options.workingDirectory,
        ).load();

    _log('Parsing OpenAPI document (${schema.sourceLabel})');
    final parserConfig = ParserConfig(
      schema.contents,
      isJson: schema.isJson,
      name: options.schemaName,
      defaultContentType: options.defaultContentType,
      includeTags: options.includeTags,
      excludeTags: options.excludeTags,
      inferRequiredFromNullable: options.inferRequiredFromNullable,
    );
    final parser = OpenApiParser(parserConfig);
    final restClients = parser.parseRestClients();
    final dataClasses = parser.parseDataClasses();

    _log('Generating models...');
    final modelGenerator = ModelGenerator(
      outputDirectory: options.resolvedModelsDirectory,
    );
    final modelResult = modelGenerator.generate(dataClasses);

    _log('Generating services...');
    final serviceGenerator = ServiceGenerator(
      outputDirectory: options.resolvedServicesDirectory,
      apiServicePath: options.resolvedApiServicePath,
      symbolToFile: modelResult.symbolToFile,
      resolver: modelResult.resolver,
    );
    final serviceResult = serviceGenerator.generate(restClients);

    _log('Writing files to disk...');
    final writtenModelFiles = await _writeFiles(
      modelResult.files,
      options.overwriteExisting,
    );
    final writtenServiceFiles = await _writeFiles(
      serviceResult.files,
      options.overwriteExisting,
    );

    final warnings = <String>[...serviceResult.warnings];

    if (options.formatOutput) {
      await _formatFiles([...writtenModelFiles, ...writtenServiceFiles]);
    }

    return GenerationSummary(
      modelFilesWritten: writtenModelFiles,
      serviceFilesWritten: writtenServiceFiles,
      warnings: warnings,
      outputDirectories: {
        'models': options.resolvedModelsDirectory,
        'services': options.resolvedServicesDirectory,
      },
    );
  }

  Future<List<String>> _writeFiles(
    List<GeneratedFile> files,
    bool overwrite,
  ) async {
    final written = <String>[];
    for (final file in files) {
      final target = File(file.path);
      if (target.existsSync() && !overwrite) {
        _log('Skipping existing file ${target.path}', isVerbose: true);
        continue;
      }
      await target.parent.create(recursive: true);
      await target.writeAsString(file.content);
      written.add(target.path);
      _log('Wrote ${target.path}', isVerbose: true);
    }
    return written;
  }

  Future<void> _formatFiles(List<String> files) async {
    if (files.isEmpty) {
      return;
    }
    await Process.run('dart', ['format', ...files], runInShell: true);
  }

  void _log(String message, {bool isVerbose = false}) {
    if (!isVerbose || options.verbose) {
      stdout.writeln('[swagger_gen] $message');
    }
  }
}
