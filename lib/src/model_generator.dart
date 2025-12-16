import 'dart:collection';

import 'package:path/path.dart' as p;
import 'package:swagger_parser/src/parser/model/universal_data_class.dart';
import 'package:swagger_parser/src/parser/model/universal_type.dart';

import 'generated_file.dart';
import 'json_expression_builder.dart';
import 'type_resolver.dart';
import 'utils/string_utils.dart';

const _generatedHeader = '''
// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: public_member_api_docs
''';

class ModelGenerationResult {
  const ModelGenerationResult({
    required this.files,
    required this.symbolToFile,
    required this.resolver,
  });

  final List<GeneratedFile> files;
  final Map<String, String> symbolToFile;
  final TypeResolver resolver;
}

class ModelGenerator {
  const ModelGenerator({required this.outputDirectory});

  final String outputDirectory;

  ModelGenerationResult generate(List<UniversalDataClass> dataClasses) {
    final components = <UniversalComponentClass>[];
    final aliasComponents = <UniversalComponentClass>[];
    final enums = <UniversalEnumClass>[];

    for (final dataClass in dataClasses) {
      if (dataClass is UniversalComponentClass) {
        if (dataClass.typeDef) {
          aliasComponents.add(dataClass);
        } else {
          components.add(dataClass);
        }
      } else if (dataClass is UniversalEnumClass) {
        enums.add(dataClass);
      }
    }

    final aliasSources = <String, UniversalType>{};
    for (final alias in aliasComponents) {
      if (alias.parameters.isEmpty) {
        continue;
      }
      aliasSources[alias.name] = alias.parameters.first;
    }

    final symbolToFile = <String, String>{};
    for (final symbol in [
      ...components.map((c) => c.name),
      ...aliasComponents.map((c) => c.name),
      ...enums.map((e) => e.name),
    ]) {
      symbolToFile[symbol] = p.join(
        outputDirectory,
        '${toSnakeCase(symbol)}.dart',
      );
    }

    final resolver = TypeResolver(
      modelNames: {
        ...components.map((c) => c.name),
        ...aliasComponents.map((c) => c.name),
      },
      enumNames: enums.map((e) => e.name).toSet(),
      aliasSources: aliasSources,
    );

    final files = <GeneratedFile>[];

    for (final alias in aliasComponents) {
      files.add(_buildAliasFile(alias, resolver, symbolToFile));
    }

    for (final enumClass in enums) {
      files.add(_buildEnumFile(enumClass));
    }

    for (final component in components) {
      files.add(_buildModelFile(component, resolver, symbolToFile));
    }

    return ModelGenerationResult(
      files: files,
      symbolToFile: symbolToFile,
      resolver: resolver,
    );
  }

  GeneratedFile _buildAliasFile(
    UniversalComponentClass component,
    TypeResolver resolver,
    Map<String, String> symbolToFile,
  ) {
    final target = resolver.aliasTarget(component.name);
    final buffer =
        StringBuffer()
          ..writeln(_generatedHeader)
          ..writeln('typedef ${component.name} = $target;');

    return GeneratedFile(
      path: symbolToFile[component.name]!,
      content: buffer.toString(),
    );
  }

  GeneratedFile _buildEnumFile(UniversalEnumClass enumClass) {
    final buffer = StringBuffer()..writeln(_generatedHeader);
    if (enumClass.description != null) {
      buffer.writeln('/// ${enumClass.description}');
    }
    buffer.writeln('enum ${enumClass.name} {');
    final sortedItems = enumClass.items.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final item in sortedItems) {
      if (item.description != null) {
        buffer.writeln('  /// ${item.description}');
      }
      buffer.writeln("  ${toCamelCase(item.name)}('${item.jsonKey}'),");
    }
    buffer
      ..writeln('  ;')
      ..writeln()
      ..writeln('  const ${enumClass.name}(this.value);')
      ..writeln('  final String value;')
      ..writeln()
      ..writeln('  static ${enumClass.name}? fromJson(String? value) {')
      ..writeln('    if (value == null) {')
      ..writeln('      return null;')
      ..writeln('    }')
      ..writeln('    for (final item in ${enumClass.name}.values) {')
      ..writeln('      if (item.value == value) {')
      ..writeln('        return item;')
      ..writeln('      }')
      ..writeln('    }')
      ..writeln('    return null;')
      ..writeln('  }')
      ..writeln()
      ..writeln('  String toJson() => value;')
      ..writeln('}');

    return GeneratedFile(
      path: p.join(outputDirectory, '${toSnakeCase(enumClass.name)}.dart'),
      content: buffer.toString(),
    );
  }

  GeneratedFile _buildModelFile(
    UniversalComponentClass component,
    TypeResolver resolver,
    Map<String, String> symbolToFile,
  ) {
    final filePath = symbolToFile[component.name]!;
    final imports = _resolveImports(component.imports, filePath, symbolToFile);

    final jsonBuilder = JsonExpressionBuilder(resolver);
    final fields =
        component.parameters.toList()..sort((a, b) => a.compareTo(b));
    final fieldSpecs =
        fields
            .map(
              (field) => _FieldSpec.fromUniversal(field, resolver, jsonBuilder),
            )
            .toList();

    final buffer = StringBuffer()..writeln(_generatedHeader);
    for (final import in imports) {
      buffer.writeln("import '$import';");
    }
    if (imports.isNotEmpty) {
      buffer.writeln();
    }
    if (component.description != null) {
      buffer.writeln('/// ${component.description}');
    }
    buffer.writeln('class ${component.name} {');
    buffer.writeln('  const ${component.name}({');
    for (final field in fieldSpecs) {
      final modifier = field.isRequired ? 'required ' : '';
      buffer.writeln('    ${modifier}this.${field.name},');
    }
    buffer
      ..writeln('  });')
      ..writeln();

    for (final field in fieldSpecs) {
      if (field.description != null) {
        buffer.writeln('  /// ${field.description}');
      }
      buffer.writeln('  final ${field.dartType} ${field.name};');
    }
    buffer.writeln();

    buffer.writeln(
      '  factory ${component.name}.fromJson(Map<String, dynamic> json) {',
    );
    buffer.writeln('    return ${component.name}(');
    for (final field in fieldSpecs) {
      buffer.writeln('      ${field.name}: ${field.decodeExpression('json')},');
    }
    buffer
      ..writeln('    );')
      ..writeln('  }')
      ..writeln();

    buffer.writeln('  Map<String, dynamic> toJson() {');
    buffer.writeln('    final data = <String, dynamic>{};');
    for (final field in fieldSpecs) {
      buffer.write(field.encodeExpression('data'));
    }
    buffer
      ..writeln('    return data;')
      ..writeln('  }');
    buffer.writeln('}');

    return GeneratedFile(path: filePath, content: buffer.toString());
  }

  Iterable<String> _resolveImports(
    Set<String> imports,
    String fromPath,
    Map<String, String> symbolToFile,
  ) sync* {
    final directory = p.dirname(fromPath);
    final sorted = imports.toList()..sort();
    for (final symbol in sorted) {
      if (!symbolToFile.containsKey(symbol)) {
        continue;
      }
      final target = symbolToFile[symbol]!;
      if (target == fromPath) {
        continue;
      }
      final relative = p.relative(target, from: directory);
      yield relative.replaceAll('\\', '/');
    }
  }
}

class _FieldSpec {
  _FieldSpec({
    required this.original,
    required this.name,
    required this.jsonKey,
    required this.dartType,
    required this.isRequired,
    required this.description,
    required this.resolver,
    required this.jsonBuilder,
  });

  factory _FieldSpec.fromUniversal(
    UniversalType type,
    TypeResolver resolver,
    JsonExpressionBuilder jsonBuilder,
  ) {
    final fieldName = type.name ?? toCamelCase(type.jsonKey ?? 'value');
    return _FieldSpec(
      original: type,
      name: _sanitizeName(fieldName),
      jsonKey: type.jsonKey ?? fieldName,
      dartType: resolver.dartType(type),
      isRequired: !resolver.isNullable(type),
      description: type.description,
      resolver: resolver,
      jsonBuilder: jsonBuilder,
    );
  }

  final UniversalType original;
  final String name;
  final String jsonKey;
  final String dartType;
  final bool isRequired;
  final String? description;
  final TypeResolver resolver;
  final JsonExpressionBuilder jsonBuilder;

  static String _sanitizeName(String value) {
    const reserved = {
      'class',
      'enum',
      'switch',
      'default',
      'operator',
      'final',
    };
    return reserved.contains(value) ? '${value}Value' : value;
  }

  String decodeExpression(String jsonVar) => jsonBuilder.decode(
    original,
    "$jsonVar['$jsonKey']",
    defaultCollections: isRequired,
  );

  String encodeExpression(String targetMap) {
    final valueExpression = jsonBuilder.encodeValue(original, name);
    if (!resolver.isNullable(original)) {
      return "    $targetMap['$jsonKey'] = $valueExpression;\n";
    }

    final tempName = '_${name}Value';
    final sanitizedTemp =
        tempName.replaceAll(RegExp('[^a-zA-Z0-9_]'), '_');
    final guardedExpression = jsonBuilder.encodeValue(
      original,
      sanitizedTemp,
    );

    return '''
    final $sanitizedTemp = $name;
    if ($sanitizedTemp != null) {
      $targetMap['$jsonKey'] = $guardedExpression;
    }
''';
  }
}
