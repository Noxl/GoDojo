import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/storage.dart';
import 'library.dart';

const kStarterFolder = 'assets/starter/';

/// Adds to the library the SGF files shipped in [kStarterFolder] (web
/// version only). Each file is added once: deleting it from the library
/// does not bring it back. Returns the number added.
Future<int> importStarterPack(Library lib) async {
  if (!storage.inBrowser || lib.directory == null) return 0;
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest
        .listAssets()
        .where(
          (a) =>
              a.startsWith(kStarterFolder) && a.toLowerCase().endsWith('.sgf'),
        )
        .toList();
    if (assets.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    final done = {...?prefs.getStringList('starterImported')};
    var added = 0;
    for (final a in assets) {
      if (done.contains(a)) continue;
      final rel = Uri.decodeComponent(a.substring(kStarterFolder.length));
      final dest = p.joinAll([lib.directory!, ...rel.split('/')]);
      if (!await storage.exists(dest)) {
        await storage.write(dest, await rootBundle.loadString(a));
        added++;
      }
      done.add(a);
    }
    await prefs.setStringList('starterImported', done.toList());
    if (added > 0) await lib.refresh();
    return added;
  } catch (e) {
    debugPrint('Starter pack not loaded: $e');
    return 0;
  }
}
