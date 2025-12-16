import 'package:path/path.dart' as p;
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

class ServiceGenerationResult {
  ServiceGenerationResult({required this.files, required this.warnings});

  final List<GeneratedFile> files;
  final List<String> warnings;
}

class ServiceGenerator {
  ServiceGenerator({
    required this.outputDirectory,
    required this.apiServicePath,
    required this.symbolToFile,
    required this.resolver,
  }) : _jsonBuilder = JsonExpressionBuilder(resolver);

  final String outputDirectory;
  final String apiServicePath;
  final Map<String, String> symbolToFile;
  final TypeResolver resolver;

  final JsonExpressionBuilder _jsonBuilder;

  ServiceGenerationResult generate(List<UniversalRestClient> clients) {
    final files = <GeneratedFile>[];
    final warnings = <String>[];

    for (final client in clients) {
      final result = _buildServiceFile(client, warnings);
      if (result == null) {
        warnings.add(
          'Skipped ${client.name} because it does not contain supported requests.',
        );
        continue;
      }
      files.add(result);
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

    final docLines = <String>[
      '${request.requestType.name.toUpperCase()} ${request.route}',
      ..._splitDescription(request.description),
      ...request.parameters
          .where((param) => param.description?.trim().isNotEmpty ?? false)
          .map(
            (param) =>
                '[${param.name ?? param.parameterType.name}] - ${param.description!.trim()}',
          ),
    ].where((line) => line.isNotEmpty).toList();
    final docLinesOrdered = <String>[];
    final seenDocLines = <String>{};
    for (final line in docLines) {
      if (seenDocLines.add(line)) {
        docLinesOrdered.add(line);
      }
    }
    for (final line in docLinesOrdered) {
      buffer.writeln('  /// $line');
    }

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

    final namedParams = <String>['Map<String, String>? queryParams'];
    if (bodyParamSpec != null) {
      final requiredKeyword = bodyParamSpec.isRequired ? 'required ' : '';
      namedParams.add(
        '$requiredKeyword${bodyParamSpec.type} ${bodyParamSpec.name}',
      );
    }

    final positionalSection =
        positionalParams.isEmpty ? '' : '$positionalParams';
    final namedSection =
        namedParams.isEmpty ? '' : '{${namedParams.join(', ')}}';
    final comma =
        positionalSection.isNotEmpty && namedSection.isNotEmpty ? ', ' : '';

    buffer..writeln(
      '  Future<ApiResponse<${responseSpec.displayType}>> $methodName('
      '$positionalSection$comma$namedSection) async {',
    );

    final endpoint = _interpolateRoute(request.route, pathParameters);
    buffer.writeln("    final endpoint = '$endpoint';");

    buffer
      ..writeln('    return _api.$httpMethod(')
      ..writeln('      endpoint,');
    if (bodyParamSpec != null && _methodSupportsBody(httpMethod)) {
      buffer.writeln('      body: ${bodyParamSpec.invocationArgument},');
    }
    buffer
      ..writeln('      queryParams: queryParams,')
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
}

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
    final dartName = toCamelCase(param.name!);
    final dartType = resolver.dartType(param.type);
    return _MethodParameter(
      originalName: param.name!,
      dartName: dartName,
      type: dartType,
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
    final parameterName = toCamelCase(name);
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
    final expression = builder.decode(
      type,
      'json',
      defaultCollections: type.wrappingCollections.isNotEmpty,
    );

    final imports = <String>{};
    if (resolver.isCustomModel(type.type) || resolver.isEnum(type.type)) {
      imports.add(type.type);
    }

    return _ResponseSpec(
      displayType: displayType,
      fromJson: '(json) => $expression',
      imports: imports,
    );
  }
}
