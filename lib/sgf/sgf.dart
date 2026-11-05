import 'sgf_node.dart';

class SgfParseException implements Exception {
  SgfParseException(this.message, this.offset);
  final String message;
  final int offset;
  @override
  String toString() => 'SGF parse error at $offset: $message';
}

/// Properties whose values are lists of points and may use the compressed
/// "aa:cc" rectangle notation.
const _pointListProps = {
  'AB',
  'AW',
  'AE',
  'TR',
  'SQ',
  'CR',
  'MA',
  'SL',
  'DD',
  'TB',
  'TW',
  'VW',
};

/// Parses SGF text and returns the root node of every game tree it contains.
List<SgfNode> parseSgfCollection(String text) {
  final p = _Parser(text);
  final roots = <SgfNode>[];
  p.skipWs();
  while (!p.atEnd) {
    if (p.peek == '(') {
      roots.add(p.parseTree(null));
    } else {
      p.pos++; // tolerate junk between game trees
    }
    p.skipWs();
  }
  if (roots.isEmpty) throw SgfParseException('No game tree found', 0);
  return roots;
}

/// Parses SGF text and returns the root of the first game tree.
SgfNode parseSgf(String text) => parseSgfCollection(text).first;

class _Parser {
  _Parser(this.s);
  final String s;
  int pos = 0;

  bool get atEnd => pos >= s.length;
  String get peek => s[pos];

  void skipWs() {
    while (!atEnd && peek.trim().isEmpty) {
      pos++;
    }
  }

  void expect(String c) {
    skipWs();
    if (atEnd || peek != c) {
      throw SgfParseException('Expected "$c"', pos);
    }
    pos++;
  }

  /// Parses "( sequence gametree* )" and attaches it under [parent].
  SgfNode parseTree(SgfNode? parent) {
    expect('(');
    SgfNode? first;
    SgfNode? last = parent;
    skipWs();
    while (!atEnd && peek == ';') {
      pos++;
      final node = parseNode();
      if (last != null) last.addChild(node);
      first ??= node;
      last = node;
      skipWs();
    }
    if (first == null) {
      // "()" or a tree without nodes: create an empty node to stay valid.
      first = SgfNode();
      parent?.addChild(first);
      last = first;
    }
    while (!atEnd && peek == '(') {
      parseTree(last);
      skipWs();
    }
    if (!atEnd && peek == ')') {
      pos++;
    } // else: tolerate a truncated file
    return first;
  }

  SgfNode parseNode() {
    final node = SgfNode();
    skipWs();
    while (!atEnd && _isIdentChar(peek)) {
      final start = pos;
      while (!atEnd && _isIdentChar(peek)) {
        pos++;
      }
      // FF[3] allowed lowercase letters in identifiers ("AddBlack" -> "AB").
      final id = s.substring(start, pos).replaceAll(RegExp('[a-z]'), '');
      final values = <String>[];
      skipWs();
      while (!atEnd && peek == '[') {
        pos++;
        values.add(parseValue());
        skipWs();
      }
      if (id.isEmpty) continue;
      final expanded = _pointListProps.contains(id)
          ? values.expand(_expandRect).toList()
          : values;
      (node.props[id] ??= []).addAll(expanded);
    }
    return node;
  }

  String parseValue() {
    final buf = StringBuffer();
    while (!atEnd) {
      final c = s[pos++];
      if (c == '\\') {
        if (atEnd) break;
        final next = s[pos++];
        // Escaped line break = soft line break, removed.
        if (next == '\n' || next == '\r') {
          if (!atEnd && (s[pos] == '\n' || s[pos] == '\r') && s[pos] != next) {
            pos++;
          }
          continue;
        }
        buf.write(next);
      } else if (c == ']') {
        return buf.toString();
      } else {
        buf.write(c);
      }
    }
    return buf.toString();
  }

  static bool _isIdentChar(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 65 && u <= 90) || (u >= 97 && u <= 122);
  }

  static Iterable<String> _expandRect(String v) sync* {
    if (v.length == 5 && v[2] == ':') {
      const l = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
      final x1 = l.indexOf(v[0]), y1 = l.indexOf(v[1]);
      final x2 = l.indexOf(v[3]), y2 = l.indexOf(v[4]);
      if (x1 >= 0 && y1 >= 0 && x2 >= 0 && y2 >= 0) {
        for (var x = x1 < x2 ? x1 : x2; x <= (x1 < x2 ? x2 : x1); x++) {
          for (var y = y1 < y2 ? y1 : y2; y <= (y1 < y2 ? y2 : y1); y++) {
            yield '${l[x]}${l[y]}';
          }
        }
        return;
      }
    }
    yield v;
  }
}

// ------------------------------------------------------------------ writer

/// Serializes a game tree to SGF text.
String writeSgf(SgfNode root) {
  final buf = StringBuffer();
  _writeTree(root, buf);
  buf.writeln();
  return buf.toString();
}

void _writeTree(SgfNode start, StringBuffer buf) {
  buf.write('(');
  var node = start;
  while (true) {
    _writeNode(node, buf);
    if (node.children.length == 1) {
      node = node.children.first;
      continue;
    }
    for (final c in node.children) {
      buf.writeln();
      _writeTree(c, buf);
    }
    break;
  }
  buf.write(')');
}

void _writeNode(SgfNode node, StringBuffer buf) {
  buf.write(';');
  for (final e in node.props.entries) {
    buf.write(e.key);
    final values = e.value.isEmpty ? const [''] : e.value;
    for (final v in values) {
      buf
        ..write('[')
        ..write(v.replaceAll('\\', '\\\\').replaceAll(']', '\\]'))
        ..write(']');
    }
  }
  if (node.isRoot || node.has('C')) buf.writeln();
}
