import 'package:flutter/material.dart';

import '../sgf/sgf_node.dart';

/// SGF move annotations (exclusive): TE, BM, DO, IT.
enum MoveQuality {
  none('None', '', null),
  // Every move in the tree is good unless marked otherwise, so "good" is
  // not shown anywhere (it is still read from TE in existing files).
  good('Good move', '!', null),
  bad('Bad move', '?', Color(0xFFD03030)),
  interesting('Interesting', '!?', Color(0xFF2F74D0));

  const MoveQuality(this.label, this.symbol, this.color);
  final String label;
  final String symbol;
  final Color? color;

  static MoveQuality of(SgfNode n) {
    if (n.has('TE')) return good;
    // Doubtful (DO) is not offered any more: old marks count as bad.
    if (n.has('BM') || n.has('DO')) return bad;
    if (n.has('IT')) return interesting;
    return none;
  }

  void applyTo(SgfNode n) {
    for (final id in const ['TE', 'BM', 'DO', 'IT']) {
      n.remove(id);
    }
    switch (this) {
      case good:
        n.set('TE', '1');
      case bad:
        n.set('BM', '1');
      case interesting:
        n.set('IT', '');
      case none:
        break;
    }
  }
}

/// SGF position judgements (exclusive): GB, GW, DM, UC.
enum PositionJudgement {
  none('None', null),
  goodForBlack('Good for Black', 'GB'),
  goodForWhite('Good for White', 'GW'),
  even('Even', 'DM'),
  unclear('Unclear', 'UC');

  const PositionJudgement(this.label, this.sgfId);
  final String label;
  final String? sgfId;

  static PositionJudgement of(SgfNode n) {
    for (final j in values) {
      if (j.sgfId != null && n.has(j.sgfId!)) return j;
    }
    return none;
  }

  void applyTo(SgfNode n) {
    for (final j in values) {
      if (j.sgfId != null) n.remove(j.sgfId!);
    }
    if (sgfId != null) n.set(sgfId!, '1');
  }
}

/// Board markup shapes stored on a node.
enum MarkupShape {
  triangle('TR'),
  square('SQ'),
  circle('CR'),
  cross('MA');

  const MarkupShape(this.sgfId);
  final String sgfId;
}
