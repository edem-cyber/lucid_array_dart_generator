import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:swagger_parser/src/parser/config/parser_config.dart';
import 'package:swagger_parser/src/parser/parser/open_api_parser.dart';

import 'generator_options.dart';
import 'generated_file.dart';
import 'model_generator.dart';
import 'schema_loader.dart';
import 'service_generator.dart';
import 'utils/string_utils.dart';

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

    final namespace = _namespaceFolder(_effectiveSchemaName());
    final modelsDirectory = p.join(
      options.resolvedModelsDirectory,
      '${namespace}Models',
    );
    final servicesDirectory = p.join(
      options.resolvedServicesDirectory,
      '${namespace}Service',
    );

    _log('Generating models...');
    final modelGenerator = ModelGenerator(
      outputDirectory: modelsDirectory,
    );
    final modelResult = modelGenerator.generate(dataClasses);

    _log('Generating services...');
    final helpersPath = p.join(
      servicesDirectory,
      'service_helpers.dart',
    );
    final serviceGenerator = ServiceGenerator(
      outputDirectory: servicesDirectory,
      apiServicePath: options.resolvedApiServicePath,
      helpersImportPath: helpersPath,
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
        'models': modelsDirectory,
        'services': servicesDirectory,
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

  String _namespaceFolder(String schemaName) {
    final raw = schemaName.trim();
    final base =
        raw.isEmpty ? 'api' : sanitizeIdentifier(toCamelCase(raw));
    return base.isEmpty ? 'api' : base;
  }

  String _effectiveSchemaName() {
    final configured = options.schemaName?.trim();
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }

    final uri = Uri.tryParse(options.schemaPathOrUrl);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      for (final segment in uri.pathSegments.reversed) {
        final cleaned = segment.replaceAll('.json', '').trim();
        final lower = cleaned.toLowerCase();
        if (cleaned.isNotEmpty && lower != 'swagger' && lower != 'docs') {
          return cleaned;
        }
      }
    }

    final fileName = options.schemaPathOrUrl.split('/').last;
    if (fileName.isNotEmpty) {
      final base = fileName.replaceAll('.json', '');
      if (base.isNotEmpty) {
        return base;
      }
    }

    return 'api';
  }
}
