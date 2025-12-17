import 'package:swagger_parser/src/parser/model/universal_type.dart';

import 'type_resolver.dart';

/// Builds Dart expressions for encoding/decoding JSON structures.
class JsonExpressionBuilder {
  const JsonExpressionBuilder(this.resolver);

  final TypeResolver resolver;

  /// Expression that converts [accessExpression] into a Dart value.
  String decode(
    UniversalType type,
    String accessExpression, {
    bool defaultCollections = false,
  }) {
    if (type.wrappingCollections.isNotEmpty) {
      return _decodeCollection(
        type,
        accessExpression,
        defaultCollections: defaultCollections,
      );
    }
    final baseType = resolver.baseDartType(type);
    final nullable = resolver.isNullable(type);
    switch (baseType) {
      case 'DateTime':
        return nullable
            ? "$accessExpression == null ? null : DateTime.parse($accessExpression as String)"
            : "DateTime.parse($accessExpression as String)";
      case 'double':
        return nullable
            ? '($accessExpression as num?)?.toDouble()'
            : '($accessExpression as num).toDouble()';
      default:
        if (resolver.isEnum(baseType)) {
          final expression =
              '$baseType.fromJson($accessExpression as String?)';
          return nullable ? expression : '$expression!';
        }
        if (resolver.isCustomModel(baseType)) {
          final expression =
              '$baseType.fromJson(Map<String, dynamic>.from($accessExpression as Map))';
          return nullable
              ? "$accessExpression == null ? null : $expression"
              : expression;
        }
        if (baseType.startsWith('Map<')) {
          final mapExpr =
              'Map<String, dynamic>.from(($accessExpression as Map?) ?? const <String, dynamic>{})';
          return nullable
              ? "$accessExpression == null ? null : $mapExpr"
              : mapExpr;
        }
        final castType = baseType;
        return '$accessExpression as $castType${nullable ? '?' : ''}';
    }
  }

  /// Expression that encodes [reference] into a JSON-safe value.
  String encodeValue(UniversalType type, String reference) {
    if (type.wrappingCollections.isNotEmpty) {
      final wrapper = type.wrappingCollections.first;
      final next = type.copyWith(
        wrappingCollections: type.wrappingCollections.sublist(1),
        nullable: false,
        isRequired: true,
      );
      final target =
          '$reference${wrapper.collectionSuffixQuestionMark == '?' ? '?' : ''}';

      if (wrapper.collectionPrefix.startsWith('List')) {
        final child = encodeValue(next, 'item');
        return '$target.map((item) => $child).toList()';
      }
      final child = encodeValue(next, 'value');
      return '$target.map((key, value) => MapEntry(key, $child))';
    }

    final baseType = resolver.baseDartType(type);
    if (baseType == 'DateTime') {
      return '$reference.toIso8601String()';
    }
    if (resolver.isEnum(baseType)) {
      return '$reference.value';
    }
    if (resolver.isCustomModel(baseType)) {
      return '$reference.toJson()';
    }
    return reference;
  }

  String _decodeCollection(
    UniversalType type,
    String accessExpression, {
    required bool defaultCollections,
  }) {
    final wrapper = type.wrappingCollections.first;
    final next = type.copyWith(
      wrappingCollections: type.wrappingCollections.sublist(1),
      nullable: false,
      isRequired: true,
    );
    if (wrapper.collectionPrefix.startsWith('List')) {
      final listExpr =
          '($accessExpression as List<dynamic>?)?.map((value) => ${decode(next, 'value', defaultCollections: true)}).toList()';
      if (wrapper.collectionSuffixQuestionMark == '?') {
        return listExpr;
      }
      return defaultCollections ? '$listExpr ?? const []' : listExpr;
    } else {
      final childExpression = decode(next, 'value', defaultCollections: true);
      final mapExpr =
          '($accessExpression as Map<String, dynamic>?)?.map((key, value) => MapEntry(key, $childExpression))';
      if (wrapper.collectionSuffixQuestionMark == '?') {
        return mapExpr;
      }
      return defaultCollections ? '$mapExpr ?? const {}' : mapExpr;
    }
  }
}
