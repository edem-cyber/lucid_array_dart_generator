import 'package:swagger_parser/src/parser/model/universal_collections.dart';
import 'package:swagger_parser/src/parser/model/universal_type.dart';

/// Provides helpers for mapping [UniversalType] metadata to Dart constructs.
class TypeResolver {
  TypeResolver({
    required Set<String> modelNames,
    required Set<String> enumNames,
    Map<String, UniversalType>? aliasSources,
  }) : _modelNames = {...modelNames},
       _enumNames = {...enumNames},
       _aliasSources = aliasSources ?? {};

  final Set<String> _modelNames;
  final Set<String> _enumNames;
  final Map<String, UniversalType> _aliasSources;
  final Map<String, String> _aliasCache = {};

  /// Returns true when [type] should be treated as nullable.
  bool isNullable(UniversalType type) =>
      type.nullable || !type.isRequired || type.referencedNullable;

  /// Resolves the base Dart type without applying collection wrappers.
  String baseDartType(UniversalType type) =>
      _resolveBase(type.type, format: type.format, expandingAlias: null);

  /// Resolves the Dart type used for the provided [UniversalType].
  String dartType(UniversalType type) {
    final hasCollection = type.wrappingCollections.isNotEmpty;
    final base = _resolveBase(
      type.type,
      format: type.format,
      expandingAlias: null,
    );
    final withCollections = _wrapCollections(base, type.wrappingCollections);
    if (!hasCollection && isNullable(type)) {
      return '$withCollections?';
    }
    return withCollections;
  }

  /// Resolves the target type of a typedef-style component.
  String aliasTarget(String aliasName) {
    if (_aliasCache.containsKey(aliasName)) {
      return _aliasCache[aliasName]!;
    }
    final source = _aliasSources[aliasName];
    if (source == null) {
      throw ArgumentError.value(
        aliasName,
        'aliasName',
        'Alias was not registered with the resolver.',
      );
    }
    final target = _dartTypeInternal(source, expandingAlias: aliasName);
    _aliasCache[aliasName] = target;
    return target;
  }

  bool isCustomModel(String typeName) => _modelNames.contains(typeName);

  bool isEnum(String typeName) => _enumNames.contains(typeName);

  bool isAlias(String typeName) => _aliasSources.containsKey(typeName);

  /// Returns `true` when [typeName] is a generated enum.
  bool isEnumTypeName(String typeName) => _enumNames.contains(typeName);

  /// Returns a string expression that converts [reference] into a query value.
  String queryParameterEncodeExpression(
    UniversalType type,
    String reference, {
    bool forceNonNullable = false,
  }) {
    final targetRef =
        forceNonNullable && isNullable(type) ? '$reference!' : reference;
    final base = _resolveBase(
      type.type,
      format: type.format,
      expandingAlias: null,
    );
    if (isEnumTypeName(base)) {
      return '$targetRef.value';
    }
    switch (base) {
      case 'DateTime':
        return '$targetRef.toIso8601String()';
      case 'String':
        return targetRef;
      case 'bool':
      case 'int':
      case 'double':
        return '$targetRef.toString()';
      default:
        return '$targetRef.toString()';
    }
  }

  String _dartTypeInternal(UniversalType type, {String? expandingAlias}) {
    final hasCollection = type.wrappingCollections.isNotEmpty;
    final base = _resolveBase(
      type.type,
      format: type.format,
      expandingAlias: expandingAlias,
    );
    final withCollections = _wrapCollections(base, type.wrappingCollections);
    if (!hasCollection && isNullable(type)) {
      return '$withCollections?';
    }
    return withCollections;
  }

  String _wrapCollections(String base, List<UniversalCollections> wrappers) {
    var result = base;
    for (final wrapper in wrappers) {
      final itemSuffix =
          wrapper.itemIsNullable && !result.endsWith('?') ? '?' : '';
      final prefix = wrapper.collectionPrefix;
      final suffix = wrapper.collectionSuffixQuestionMark;
      result = '$prefix$result$itemSuffix>$suffix';
    }
    return result;
  }

  String _resolveBase(
    String rawType, {
    String? format,
    String? expandingAlias,
  }) {
    if (_aliasSources.containsKey(rawType) && rawType != expandingAlias) {
      return aliasTarget(rawType);
    }
    if (_modelNames.contains(rawType) || _enumNames.contains(rawType)) {
      return rawType;
    }
    final lower = rawType.toLowerCase();
    switch (lower) {
      case 'string':
        if (format == 'date' || format == 'date-time') {
          return 'DateTime';
        }
        return 'String';
      case 'integer':
      case 'int':
        return 'int';
      case 'number':
      case 'float':
      case 'double':
        return 'double';
      case 'boolean':
      case 'bool':
        return 'bool';
      case 'object':
        return 'Map<String, dynamic>';
      case 'array':
        return 'List<dynamic>';
      default:
        return rawType;
    }
  }
}
