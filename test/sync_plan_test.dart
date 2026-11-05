import 'package:flutter_test/flutter_test.dart';
import 'package:go_dojo/cloud/cloud_sync.dart';

void main() {
  SyncPlan plan({
    Map<String, (int, bool)> remote = const {},
    Map<String, int> local = const {},
    Map<String, Map<String, Object?>> state = const {},
  }) => SyncPlan.of(remote: remote, local: local, state: state);

  test('first sync: files of both sides go to the other', () {
    final p = plan(remote: {'a.sgf': (10, false)}, local: {'b.sgf': 20});
    expect(p.download, {'a.sgf'});
    expect(p.upload, {'b.sgf'});
  });

  test('first sync, same name on both sides: a conflict (both kept)', () {
    final p = plan(remote: {'a.sgf': (10, false)}, local: {'a.sgf': 20});
    expect(p.conflicts, {'a.sgf'});
  });

  test('a change on one side goes to the other', () {
    const synced = {
      'a.sgf': {'r': 10, 'l': 20},
    };
    expect(
      plan(
        remote: {'a.sgf': (10, false)},
        local: {'a.sgf': 25},
        state: synced,
      ).upload,
      {'a.sgf'},
    );
    expect(
      plan(
        remote: {'a.sgf': (15, false)},
        local: {'a.sgf': 20},
        state: synced,
      ).download,
      {'a.sgf'},
    );
    final same = plan(
      remote: {'a.sgf': (10, false)},
      local: {'a.sgf': 20},
      state: synced,
    );
    expect(same.unchanged.keys, ['a.sgf']);
    expect(same.upload, isEmpty);
    expect(same.download, isEmpty);
  });

  test('changed on both sides since the last sync: a conflict', () {
    final p = plan(
      remote: {'a.sgf': (15, false)},
      local: {'a.sgf': 25},
      state: {
        'a.sgf': {'r': 10, 'l': 20},
      },
    );
    expect(p.conflicts, {'a.sgf'});
  });

  test('deleted on one side: deleted on the other', () {
    const synced = {
      'a.sgf': {'r': 10, 'l': 20},
    };
    expect(plan(remote: {'a.sgf': (10, false)}, state: synced).deleteThere, {
      'a.sgf',
    });
    expect(
      plan(
        remote: {'a.sgf': (15, true)},
        local: {'a.sgf': 20},
        state: synced,
      ).deleteHere,
      {'a.sgf'},
    );
  });

  test('deleted on one side but edited on the other: the edit wins', () {
    const synced = {
      'a.sgf': {'r': 10, 'l': 20},
    };
    // Deleted in the cloud, edited here: sent back.
    expect(
      plan(
        remote: {'a.sgf': (15, true)},
        local: {'a.sgf': 25},
        state: synced,
      ).upload,
      {'a.sgf'},
    );
    // Deleted here, edited in the cloud: brought back.
    expect(plan(remote: {'a.sgf': (15, false)}, state: synced).download, {
      'a.sgf',
    });
  });

  test('a file created again after being deleted everywhere is sent', () {
    final p = plan(remote: {'a.sgf': (15, true)}, local: {'a.sgf': 30});
    expect(p.upload, {'a.sgf'});
  });

  test('deleted on both sides: nothing to do', () {
    final p = plan(
      remote: {'a.sgf': (15, true)},
      state: {
        'a.sgf': {'r': 10, 'l': 20},
      },
    );
    expect([
      p.upload,
      p.download,
      p.deleteHere,
      p.deleteThere,
      p.conflicts,
    ], everyElement(isEmpty));
  });
}
