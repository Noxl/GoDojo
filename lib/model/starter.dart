import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/storage.dart';
import 'library.dart';

const kStarterFolder = 'assets/starter/';

/// The SGF files shipped in [kStarterFolder].
Future<List<String>> _starterAssets() async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  return manifest
      .listAssets()
      .where(
        (a) => a.startsWith(kStarterFolder) && a.toLowerCase().endsWith('.sgf'),
      )
      .toList();
}

/// Writes [asset] in [dir] unless a file of that name is already there.
Future<bool> _writeStarter(String asset, String dir) async {
  final rel = Uri.decodeComponent(asset.substring(kStarterFolder.length));
  final dest = p.joinAll([dir, ...rel.split('/')]);
  if (await storage.exists(dest)) return false;
  await storage.write(dest, await rootBundle.loadString(asset));
  return true;
}

/// A new account: the starter files are added to the library in [dir] (the
/// sync then sends them to the account), so there is something to train
/// from the start. Returns the number added.
Future<int> addStarterFiles(String dir) async {
  try {
    var added = 0;
    for (final a in await _starterAssets()) {
      if (await _writeStarter(a, dir)) added++;
    }
    return added;
  } catch (e) {
    debugPrint('Starter files not added: $e');
    return 0;
  }
}

/// Adds to the library the SGF files shipped in [kStarterFolder] (web
/// version only, for a visitor to try it). Each file is added once:
/// deleting it from the library does not bring it back. Returns the number
/// added.
Future<int> importStarterPack(Library lib) async {
  if (!storage.inBrowser || lib.directory == null) return 0;
  try {
    final assets = await _starterAssets();
    if (assets.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    final done = {...?prefs.getStringList('starterImported')};
    var added = 0;
    for (final a in assets) {
      if (done.contains(a)) continue;
      if (await _writeStarter(a, lib.directory!)) added++;
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
