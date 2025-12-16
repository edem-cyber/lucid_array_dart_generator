String toSnakeCase(String value) {
  final buffer = StringBuffer();
  String? previous;
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (_isSeparator(char)) {
      if (previous != '_') {
        buffer.write('_');
      }
      previous = '_';
      continue;
    }
    if (previous != null &&
        previous != '_' &&
        _isLower(previous) &&
        _isUpper(char)) {
      buffer.write('_');
    }
    buffer.write(char.toLowerCase());
    previous = char;
  }
  final result = buffer.toString().replaceAll(RegExp('_+'), '_');
  return result.startsWith('_') ? result.substring(1) : result;
}

String toCamelCase(String value) {
  final words = _wordsFrom(value).toList();
  if (words.isEmpty) {
    return value;
  }
  final first = words.first.toLowerCase();
  final rest = words.skip(1).map(_capitalize).join();
  return '$first$rest';
}

String toPascalCase(String value) => _wordsFrom(value).map(_capitalize).join();

Iterable<String> _wordsFrom(String value) sync* {
  final normalized = toSnakeCase(value);
  for (final part in normalized.split('_')) {
    if (part.isNotEmpty) {
      yield part;
    }
  }
}

String _capitalize(String value) =>
    value.isEmpty
        ? value
        : value[0].toUpperCase() + value.substring(1).toLowerCase();

bool _isSeparator(String char) =>
    char == '_' || char == '-' || char == ' ' || char == '.';

bool _isUpper(String char) =>
    char.toUpperCase() == char && char.toLowerCase() != char;

bool _isLower(String char) =>
    char.toLowerCase() == char && char.toUpperCase() != char;
