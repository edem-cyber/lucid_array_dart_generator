import 'package:path/path.dart' as p;
import 'package:swagger_parser/src/parser/model/universal_collections.dart';
import 'package:swagger_parser/src/parser/model/universal_request.dart';
import 'package:swagger_parser/src/parser/model/universal_request_type.dart';
import 'package:swagger_parser/src/parser/model/universal_rest_client.dart';
import 'package:swagger_parser/src/parser/model/universal_type.dart';

import 'generated_file.dart';
import 'json_expression_builder.dart';
import 'type_resolver.dart';
import 'utils/string_utils.dart';

const _generatedHeader = '''
// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: public_member_api_docs
''';

const _helperHeader = '''
// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: public_member_api_docs
''';

const _serviceHelpersContent = '''
$_helperHeader

T decodeJsonObject<T>(
  dynamic json,
  T Function(Map<String, dynamic>) factory,
) {
  if (json == null) {
    throw ArgumentError('Expected a JSON object but received null.');
  }
  if (json is! Map) {
    throw ArgumentError('Expected a JSON object but received \${json.runtimeType}.');
  }
  return factory(Map<String, dynamic>.from(json as Map));
}

List<T> decodeJsonList<T>(
  dynamic json,
  T Function(Map<String, dynamic>) factory,
) {
  if (json is! List) {
    return const [];
  }
  return json
      .whereType<Map>()
      .map((value) => factory(Map<String, dynamic>.from(value as Map)))
      .toList();
}
''';

class ServiceGenerationResult {
  ServiceGenerationResult({required this.files, required this.warnings});

  final List<GeneratedFile> files;
  final List<String> warnings;
}

class ServiceGenerator {
  ServiceGenerator({
    required this.outputDirectory,
    required this.apiServicePath,
    required this.helpersImportPath,
    required this.symbolToFile,
    required this.resolver,
  }) : _jsonBuilder = JsonExpressionBuilder(resolver);

  final String outputDirectory;
  final String apiServicePath;
  final String helpersImportPath;
  final Map<String, String> symbolToFile;
  final TypeResolver resolver;

  final JsonExpressionBuilder _jsonBuilder;

  ServiceGenerationResult generate(List<UniversalRestClient> clients) {
    final files = <GeneratedFile>[];
    final warnings = <String>[];

    files.add(_buildHelpersFile());
    final servicePaths = <String>[];

    for (final client in clients) {
      final result = _buildServiceFile(client, warnings);
      if (result == null) {
        warnings.add(
          'Skipped ${client.name} because it does not contain supported requests.',
        );
        continue;
      }
      servicePaths.add(result.path);
      files.add(result);
    }

    if (servicePaths.isNotEmpty) {
      files.add(_buildServicesBarrel(servicePaths));
    }

    return ServiceGenerationResult(files: files, warnings: warnings);
  }

  GeneratedFile? _buildServiceFile(
    UniversalRestClient client,
    List<String> warnings,
  ) {
    final serviceName = _resolveServiceName(client.name);
    final filePath = p.join(
      outputDirectory,
      '${toSnakeCase(serviceName)}.dart',
    );
    final imports = <String>{};
    imports.add(
      p
          .relative(helpersImportPath, from: p.dirname(filePath))
          .replaceAll('\\', '/'),
    );
    final methodsBuffer = StringBuffer();
    final methodNames = <String>{};

    imports.add(
      p
          .relative(apiServicePath, from: p.dirname(filePath))
          .replaceAll('\\', '/'),
    );

    for (final request in client.requests) {
      final method = _buildMethod(
        request,
        serviceName,
        methodNames,
        filePath,
        warnings,
      );
      if (method == null) {
        continue;
      }
      imports.addAll(method.imports);
      methodsBuffer.writeln(method.code);
    }

    if (methodsBuffer.isEmpty) {
      return null;
    }

    final buffer = StringBuffer()..writeln(_generatedHeader);

    for (final import in imports.toList()..sort()) {
      buffer.writeln("import '$import';");
    }
    buffer.writeln();
    buffer
      ..writeln('class $serviceName {')
      ..writeln('  const $serviceName();')
      ..writeln()
      ..writeln('  static final _api = ApiService.instance;')
      ..writeln();

    buffer.write(methodsBuffer.toString());
    buffer.writeln('}');

    return GeneratedFile(path: filePath, content: buffer.toString());
  }

  _ServiceMethodResult? _buildMethod(
    UniversalRequest request,
    String serviceName,
    Set<String> methodNames,
    String filePath,
    List<String> warnings,
  ) {
    if (request.isMultiPart || request.isFormUrlEncoded) {
      warnings.add(
        'Skipped ${serviceName}.${request.name} because multipart/form data is not supported yet.',
      );
      return null;
    }

    final httpMethod = _httpMethodName(request.requestType);
    if (httpMethod == null) {
      warnings.add(
        'Skipped ${serviceName}.${request.name} because ${request.requestType.name.toUpperCase()} is not supported yet.',
      );
      return null;
    }

    final methodName = _uniqueMethodName(
      methodNames,
      toCamelCase(request.name),
    );

    final pathParameters =
        request.parameters
            .where((param) => param.parameterType == HttpParameterType.path)
            .map(
              (param) => _MethodParameter.fromRequestParameter(param, resolver),
            )
            .whereType<_MethodParameter>()
            .toList();

    final queryParameters =
        request.parameters
            .where((param) => param.parameterType == HttpParameterType.query)
            .map(
              (param) => _QueryParameter.fromRequestParameter(param, resolver),
            )
            .whereType<_QueryParameter>()
            .toList();

    final bodyParameter = _findBodyParameter(request.parameters);

    final buffer = StringBuffer();
    final imports = <String>{};

    final returnType = request.returnType;
    final responseSpec = _ResponseSpec.fromType(
      returnType,
      resolver,
      _jsonBuilder,
    );
    imports.addAll(
      responseSpec.imports
          .map((symbol) => _typeImportPath(symbol, filePath))
          .where((path) => path != null)
          .cast<String>(),
    );

    if (bodyParameter != null) {
      imports.addAll(
        _collectTypeDependencies(bodyParameter.type)
            .map((symbol) => _typeImportPath(symbol, filePath))
            .where((path) => path != null)
            .cast<String>(),
      );
    }

    for (final param in pathParameters) {
      final importPath = _typeImportPath(
        param.type.replaceAll('?', ''),
        filePath,
      );
      if (importPath != null) {
        imports.add(importPath);
      }
    }
    for (final param in queryParameters) {
      final importPath = _typeImportPath(param.type.type, filePath);
      if (importPath != null) {
        imports.add(importPath);
      }
    }

    _writeDocumentation(buffer, request, bodyParameter, queryParameters);

    final positionalParams =
        pathParameters.isEmpty
            ? ''
            : pathParameters
                .map((param) => '${param.type} ${param.dartName}')
                .join(', ');

    final bodyParamSpec =
        bodyParameter == null
            ? null
            : _BodyParameterSpec.fromRequest(
              bodyParameter,
              resolver,
              _jsonBuilder,
            );

    final namedParams = <_ParameterSpec>[];
    if (bodyParamSpec != null) {
      namedParams.add(_ParameterSpec.body(bodyParamSpec));
    }
    for (final param in queryParameters) {
      namedParams.add(_ParameterSpec.query(param));
    }
    namedParams.add(
      _ParameterSpec(
        name: 'additionalQueryParams',
        type: 'Map<String, String>?',
        kind: _ParameterKind.extraQuery,
      ),
    );

    final positionalSection =
        positionalParams.isEmpty ? '' : '$positionalParams';
    final namedSection =
        namedParams.isEmpty
            ? ''
            : '{${namedParams.map((p) => p.signature).join(', ')}}';
    final comma =
        positionalSection.isNotEmpty && namedSection.isNotEmpty ? ', ' : '';

    buffer..writeln(
      '  Future<ApiResponse<${responseSpec.displayType}>> $methodName('
      '$positionalSection$comma$namedSection) async {',
    );

    final endpoint = _interpolateRoute(request.route, pathParameters);
    buffer.writeln("    final endpoint = '$endpoint';");

    if (queryParameters.isNotEmpty) {
      buffer.writeln('    final query = <String, String>{};');
      for (final param in queryParameters) {
        if (param.isRequired) {
          buffer.writeln(
            "    query['${param.originalName}'] = ${param.encode(resolver, param.dartName)};",
          );
        } else {
          final tempName = '_${param.dartName}';
          buffer.writeln('    final $tempName = ${param.dartName};');
          buffer.writeln('    if ($tempName != null) {');
          buffer.writeln(
            "      query['${param.originalName}'] = ${param.encode(resolver, tempName)};",
          );
          buffer.writeln('    }');
        }
      }
      buffer.writeln(
        '    if (additionalQueryParams != null && additionalQueryParams.isNotEmpty) {',
      );
      buffer.writeln('      query.addAll(additionalQueryParams);');
      buffer.writeln('    }');
      buffer.writeln(
        '    final resolvedQueryParams = query.isEmpty ? null : query;',
      );
    } else {
      buffer.writeln('    final resolvedQueryParams = additionalQueryParams;');
    }

    buffer
      ..writeln('    return _api.$httpMethod(')
      ..writeln('      endpoint,');
    if (bodyParamSpec != null && _methodSupportsBody(httpMethod)) {
      buffer.writeln('      body: ${bodyParamSpec.invocationArgument},');
    }
    buffer
      ..writeln('      queryParams: resolvedQueryParams,')
      ..writeln('      fromJson: ${responseSpec.fromJson},')
      ..writeln('    );');
    buffer.writeln('  }');
    buffer.writeln();

    return _ServiceMethodResult(
      code: buffer.toString(),
      imports: imports.where((element) => element.isNotEmpty).toSet(),
    );
  }

  UniversalRequestType? _findBodyParameter(
    List<UniversalRequestType> parameters,
  ) {
    for (final param in parameters) {
      if (param.parameterType == HttpParameterType.body) {
        return param;
      }
    }
    return null;
  }

  bool _methodSupportsBody(String methodName) =>
      methodName == 'post' || methodName == 'put' || methodName == 'patch';

  void _writeDocumentation(
    StringBuffer buffer,
    UniversalRequest request,
    UniversalRequestType? bodyParameter,
    List<_QueryParameter> queryParameters,
  ) {
    final seen = <String>{};

    bool writeLine(String line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        return false;
      }
      buffer.writeln('  /// $trimmed');
      return true;
    }

    writeLine('${request.requestType.name.toUpperCase()} ${request.route}');
    final description = request.description?.trim();
    if (description != null && description.isNotEmpty) {
      for (final line in _splitDescription(description)) {
        writeLine(line);
      }
    }

    final allParams =
        [
          if (bodyParameter != null) bodyParameter,
          ...request.parameters,
        ].whereType<UniversalRequestType>();

    for (final param in allParams) {
      final desc = param.description?.trim();
      if (desc == null || desc.isEmpty) {
        continue;
      }
      final name = param.name ?? param.parameterType.name;
      writeLine('[$name] - $desc');
    }

    if (queryParameters.isNotEmpty) {
      writeLine(
        'Pass `additionalQueryParams` to include extra query values not defined in the OpenAPI spec.',
      );
    }
  }

  String _interpolateRoute(
    String route,
    List<_MethodParameter> pathParameters,
  ) {
    return route.replaceAllMapped(RegExp(r'{([^}]+)}'), (match) {
      final rawName = match.group(1)!;
      final param = pathParameters.firstWhere(
        (p) => p.originalName == rawName,
        orElse:
            () => _MethodParameter(
              originalName: rawName,
              dartName: toCamelCase(rawName),
              type: 'String',
            ),
      );
      return '\${Uri.encodeComponent(${param.dartName}.toString())}';
    });
  }

  String? _httpMethodName(HttpRequestType type) {
    switch (type) {
      case HttpRequestType.get:
        return 'get';
      case HttpRequestType.post:
        return 'post';
      case HttpRequestType.put:
        return 'put';
      case HttpRequestType.delete:
        return 'delete';
      case HttpRequestType.patch:
        return 'patch';
      default:
        return null;
    }
  }

  String _resolveServiceName(String clientName) {
    var baseName = clientName.trim();
    if (baseName.toLowerCase().endsWith('client')) {
      baseName = baseName.substring(0, baseName.length - 'client'.length);
    }
    baseName = baseName.isEmpty ? 'Generated' : baseName;
    final pascalName = toPascalCase(baseName);
    if (pascalName.toLowerCase().endsWith('service')) {
      return toPascalCase(pascalName);
    }
    return '${pascalName}Service';
  }

  String _uniqueMethodName(Set<String> existing, String candidate) {
    var name = candidate.isEmpty ? 'request' : candidate;
    var index = 1;
    while (existing.contains(name)) {
      name = '$candidate$index';
      index++;
    }
    existing.add(name);
    return name;
  }

  Iterable<String> _collectTypeDependencies(UniversalType type) sync* {
    final normalized = type.type.replaceAll('?', '');
    if (symbolToFile.containsKey(normalized)) {
      yield normalized;
    }
  }

  String? _typeImportPath(String symbol, String fromFile) {
    final target = symbolToFile[symbol];
    if (target == null) {
      return null;
    }
    return p.relative(target, from: p.dirname(fromFile)).replaceAll('\\', '/');
  }

  Iterable<String> _splitDescription(String? description) sync* {
    if (description == null || description.trim().isEmpty) {
      return;
    }
    for (final line in description.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        yield trimmed;
      }
    }
  }

  GeneratedFile _buildHelpersFile() =>
      GeneratedFile(path: helpersImportPath, content: _serviceHelpersContent);

  GeneratedFile _buildServicesBarrel(List<String> servicePaths) {
    final buffer =
        StringBuffer()
          ..writeln(_generatedHeader)
          ..writeln("export 'service_helpers.dart';");
    final exports =
        servicePaths
            .map(
              (path) =>
                  p.relative(path, from: outputDirectory).replaceAll('\\', '/'),
            )
            .toList()
          ..sort();
    for (final exportPath in exports) {
      buffer.writeln("export '$exportPath';");
    }
    return GeneratedFile(
      path: p.join(outputDirectory, 'services.dart'),
      content: buffer.toString(),
    );
  }
}

class _ParameterSpec {
  _ParameterSpec({
    required this.name,
    required this.type,
    required this.kind,
    this.isRequired = false,
  });

  _ParameterSpec.body(_BodyParameterSpec spec)
    : name = spec.name,
      type = spec.type,
      kind = _ParameterKind.body,
      isRequired = spec.isRequired;

  _ParameterSpec.query(_QueryParameter spec)
    : name = spec.dartName,
      type = spec.dartType,
      kind = _ParameterKind.query,
      isRequired = spec.isRequired;

  final String name;
  final String type;
  final _ParameterKind kind;
  final bool isRequired;

  String get signature => '${isRequired ? 'required ' : ''}$type $name';
}

enum _ParameterKind { body, query, extraQuery }

class _ServiceMethodResult {
  const _ServiceMethodResult({required this.code, required this.imports});

  final String code;
  final Set<String> imports;
}

class _MethodParameter {
  const _MethodParameter({
    required this.originalName,
    required this.dartName,
    required this.type,
  });

  final String originalName;
  final String dartName;
  final String type;

  static _MethodParameter? fromRequestParameter(
    UniversalRequestType param,
    TypeResolver resolver,
  ) {
    if (param.name == null) {
      return null;
    }
    final dartName = sanitizeIdentifier(toCamelCase(param.name!));
    final dartType = resolver.dartType(param.type);
    return _MethodParameter(
      originalName: param.name!,
      dartName: dartName,
      type: dartType,
    );
  }
}

class _QueryParameter {
  const _QueryParameter({
    required this.originalName,
    required this.dartName,
    required this.dartType,
    required this.type,
    required this.isRequired,
    this.description,
  });

  final String originalName;
  final String dartName;
  final String dartType;
  final UniversalType type;
  final bool isRequired;
  final String? description;

  String encode(
    TypeResolver resolver,
    String reference, {
    bool forceNonNullable = false,
  }) {
    return resolver.queryParameterEncodeExpression(
      type,
      reference,
      forceNonNullable: forceNonNullable,
    );
  }

  static _QueryParameter? fromRequestParameter(
    UniversalRequestType param,
    TypeResolver resolver,
  ) {
    final name = param.name;
    if (name == null) {
      return null;
    }
    final dartName = sanitizeIdentifier(toCamelCase(name));
    final dartType = resolver.dartType(param.type);
    final isRequired =
        param.type.isRequired && !resolver.isNullable(param.type);
    return _QueryParameter(
      originalName: name,
      dartName: dartName,
      dartType: dartType,
      type: param.type,
      isRequired: isRequired,
      description:
          param.description?.trim().isEmpty ?? true
              ? null
              : param.description!.trim(),
    );
  }
}

class _BodyParameterSpec {
  const _BodyParameterSpec({
    required this.name,
    required this.type,
    required this.bodyExpression,
    required this.isRequired,
  });

  final String name;
  final String type;
  final String bodyExpression;
  final bool isRequired;

  String get invocationArgument =>
      isRequired ? bodyExpression : '$name == null ? null : $bodyExpression';

  static _BodyParameterSpec fromRequest(
    UniversalRequestType requestType,
    TypeResolver resolver,
    JsonExpressionBuilder builder,
  ) {
    final name = requestType.name ?? 'body';
    final parameterName = sanitizeIdentifier(toCamelCase(name));
    final dartType = resolver.dartType(requestType.type);
    final encodedValue = builder.encodeValue(requestType.type, parameterName);
    return _BodyParameterSpec(
      name: parameterName,
      type: dartType,
      bodyExpression: encodedValue,
      isRequired: requestType.type.isRequired,
    );
  }
}

class _ResponseSpec {
  _ResponseSpec({
    required this.displayType,
    required this.fromJson,
    required this.imports,
  });

  final String displayType;
  final String fromJson;
  final Set<String> imports;

  static _ResponseSpec fromType(
    UniversalType? type,
    TypeResolver resolver,
    JsonExpressionBuilder builder,
  ) {
    if (type == null) {
      return _ResponseSpec(
        displayType: 'void',
        fromJson: '(_) => null',
        imports: const {},
      );
    }

    final displayType = resolver.dartType(type);
    final imports = <String>{};
    final isListResponse =
        type.wrappingCollections.isNotEmpty &&
        _isListWrapper(type.wrappingCollections.first);

    String fromJsonExpression;
    if (isListResponse && resolver.isCustomModel(type.type)) {
      imports.add(type.type);
      fromJsonExpression =
          '(json) => decodeJsonList(json, ${type.type}.fromJson)';
    } else if (resolver.isCustomModel(type.type)) {
      imports.add(type.type);
      fromJsonExpression =
          '(json) => decodeJsonObject(json, ${type.type}.fromJson)';
    } else {
      final expression = builder.decode(
        type,
        'json',
        defaultCollections: type.wrappingCollections.isNotEmpty,
      );
      if (resolver.isCustomModel(type.type) || resolver.isEnum(type.type)) {
        imports.add(type.type);
      }
      fromJsonExpression = '(json) => $expression';
    }

    return _ResponseSpec(
      displayType: displayType,
      fromJson: fromJsonExpression,
      imports: imports,
    );
  }
}

bool _isListWrapper(UniversalCollections wrapper) {
  switch (wrapper) {
    case UniversalCollections.list:
    case UniversalCollections.listNullableItem:
    case UniversalCollections.nullableList:
    case UniversalCollections.nullableListNullableItem:
      return true;
    default:
      return false;
  }
}
