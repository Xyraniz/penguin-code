import 'dart:convert';
import 'dart:io';
import 'dart:math';

class CheckpointException implements Exception {
  const CheckpointException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CheckpointFileChange {
  const CheckpointFileChange({
    required this.path,
    required this.beforeExists,
    required this.afterExists,
  });

  final String path;
  final bool beforeExists;
  final bool afterExists;
}

class FileCheckpoint {
  const FileCheckpoint({
    required this.id,
    required this.chatId,
    required this.toolName,
    required this.rootPath,
    required this.createdAt,
    required this.complete,
    required this.files,
    required this.singleFileScope,
  });

  final String id;
  final String chatId;
  final String toolName;
  final String rootPath;
  final DateTime createdAt;
  final bool complete;
  final List<CheckpointFileChange> files;
  final bool singleFileScope;
}

class CheckpointCapture {
  const CheckpointCapture._({
    required this.id,
    required this.rootPath,
    required this.singleFileScope,
  });

  final String id;
  final String rootPath;
  final bool singleFileScope;
}

class CheckpointRestoreResult {
  const CheckpointRestoreResult({
    required this.restored,
    required this.keptUserChanges,
    required this.recoveryCheckpointId,
  });

  final int restored;
  final int keptUserChanges;
  final String? recoveryCheckpointId;
}

class CheckpointRepository {
  CheckpointRepository({required Directory dataRoot})
      : _directory = Directory(_join(dataRoot.path, 'Checkpoints'));

  static const maxSnapshots = 40;
  static const maxFiles = 10000;
  static const maxFileBytes = 50 * 1024 * 1024;
  static const maxSnapshotBytes = 250 * 1024 * 1024;
  static const _ignoredDirectories = {
    '.git',
    '.hg',
    '.svn',
    '.dart_tool',
    '.gradle',
    '.next',
    '.turbo',
    '.venv',
    'build',
    'node_modules',
    'vendor',
    'venv',
  };

  final Directory _directory;

  Future<CheckpointCapture> beginDirectory({
    required String rootPath,
    required String chatId,
    required String toolName,
  }) async =>
      _begin(
        rootPath: rootPath,
        chatId: chatId,
        toolName: toolName,
      );

  Future<CheckpointCapture> beginFile({
    required String filePath,
    required String chatId,
    required String toolName,
  }) async {
    final file = File(filePath);
    final resolved = await file.resolveSymbolicLinks();
    final directory = Directory(_parent(resolved));
    return _begin(
      rootPath: directory.path,
      chatId: chatId,
      toolName: toolName,
      onlyPaths: {_basename(resolved)},
    );
  }

  Future<CheckpointCapture> _begin({
    required String rootPath,
    required String chatId,
    required String toolName,
    Set<String>? onlyPaths,
  }) async {
    final root = Directory(rootPath);
    if (!await root.exists()) {
      throw const CheckpointException(
        'The working folder is unavailable, so its checkpoint could not be created.',
      );
    }
    final resolvedRoot = await root.resolveSymbolicLinks();
    if (_isFilesystemRoot(resolvedRoot)) {
      throw const CheckpointException(
        'Checkpoints are unavailable for a drive or filesystem root. Choose a project folder.',
      );
    }
    await _ensureStore();
    final id = _newId();
    final snapshotDirectory = _snapshotDirectory(id);
    await snapshotDirectory.create();
    final before = Directory(_join(snapshotDirectory.path, 'before'));
    await before.create();
    try {
      final entries = await _scan(resolvedRoot, onlyPaths: onlyPaths);
      var totalBytes = 0;
      final beforeExists = <String>[];
      for (final entry in entries) {
        final length = await File(entry.absolutePath).length();
        if (length > maxFileBytes) {
          throw CheckpointException(
            'Checkpoint stopped before changing files: ${entry.relativePath} exceeds the 50 MiB per-file limit.',
          );
        }
        totalBytes += length;
        if (totalBytes > maxSnapshotBytes) {
          throw const CheckpointException(
            'Checkpoint stopped before changing files: the working folder exceeds the 250 MiB snapshot limit.',
          );
        }
        await _copyFile(entry.absolutePath, before.path, entry.relativePath);
        beforeExists.add(entry.relativePath);
      }
      final metadata = {
        'schemaVersion': 1,
        'id': id,
        'chatId': chatId,
        'toolName': toolName,
        'rootPath': resolvedRoot,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'complete': false,
        'singleFileScope': onlyPaths != null,
        'trackedPaths': onlyPaths?.toList(growable: false),
        'beforeExists': beforeExists,
        'afterExists': <String, bool>{},
      };
      await _writeMetadata(snapshotDirectory, metadata);
      await _prune();
      return CheckpointCapture._(
        id: id,
        rootPath: resolvedRoot,
        singleFileScope: onlyPaths != null,
      );
    } catch (_) {
      if (await snapshotDirectory.exists()) {
        await snapshotDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<FileCheckpoint?> finish(CheckpointCapture capture) async {
    final directory = _snapshotDirectory(capture.id);
    final metadata = await _readMetadata(directory);
    final trackedPaths = metadata['trackedPaths'];
    final onlyPaths =
        trackedPaths is List ? trackedPaths.whereType<String>().toSet() : null;
    final current = await _scan(capture.rootPath, onlyPaths: onlyPaths);
    final currentByPath = {
      for (final entry in current) entry.relativePath: entry,
    };
    final beforeExists =
        (metadata['beforeExists'] as List).whereType<String>().toSet();
    final beforeDirectory = Directory(_join(directory.path, 'before'));
    final afterDirectory = Directory(_join(directory.path, 'after'));
    await afterDirectory.create();
    final currentPaths = currentByPath.keys.toSet();
    final allPaths = {...beforeExists, ...currentPaths}.toList()..sort();
    final afterExists = <String, bool>{};
    final changes = <CheckpointFileChange>[];
    for (final path in allPaths) {
      final beforePresent = beforeExists.contains(path);
      final currentEntry = currentByPath[path];
      final afterPresent = currentEntry != null;
      var changed = beforePresent != afterPresent;
      if (beforePresent && afterPresent) {
        changed = !await _sameFileBytes(
          _backupFile(beforeDirectory, path),
          File(currentEntry.absolutePath),
        );
      }
      if (!changed) continue;
      afterExists[path] = afterPresent;
      if (afterPresent) {
        await _copyFile(
          currentEntry.absolutePath,
          afterDirectory.path,
          path,
        );
      }
      changes.add(CheckpointFileChange(
        path: path,
        beforeExists: beforePresent,
        afterExists: afterPresent,
      ));
    }
    if (changes.isEmpty) {
      await directory.delete(recursive: true);
      return null;
    }
    metadata
      ..['complete'] = true
      ..['afterExists'] = afterExists
      ..['changedPaths'] = changes.map((change) => change.path).toList();
    await _writeMetadata(directory, metadata);
    return _checkpointFromMetadata(metadata, changes);
  }

  Future<List<FileCheckpoint>> list() async {
    await _ensureStore();
    final result = <FileCheckpoint>[];
    await for (final entity in _directory.list(followLinks: false)) {
      if (await FileSystemEntity.type(entity.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }
      try {
        final snapshotDirectory = Directory(entity.path);
        final metadata = await _readMetadata(snapshotDirectory);
        final paths =
            (metadata['changedPaths'] as List? ?? const []).whereType<String>();
        final beforeExists = (metadata['beforeExists'] as List? ?? const [])
            .whereType<String>()
            .toSet();
        final afterExists = metadata['afterExists'] is Map
            ? (metadata['afterExists'] as Map).cast<String, bool>()
            : const <String, bool>{};
        result.add(_checkpointFromMetadata(
          metadata,
          paths
              .map((path) => CheckpointFileChange(
                    path: path,
                    beforeExists: beforeExists.contains(path),
                    afterExists: afterExists[path] ?? false,
                  ))
              .toList(growable: false),
        ));
      } on Object {
        continue;
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<CheckpointRestoreResult> restore(String id) async {
    final directory = _snapshotDirectory(id);
    final metadata = await _readMetadata(directory);
    final rootPath = metadata['rootPath'];
    if (rootPath is! String || !await Directory(rootPath).exists()) {
      throw const CheckpointException(
        'The working folder for this checkpoint no longer exists.',
      );
    }
    final resolvedRoot = await Directory(rootPath).resolveSymbolicLinks();
    if (_normalize(resolvedRoot) != _normalize(rootPath)) {
      throw const CheckpointException(
        'The working folder changed its symbolic-link target. Restore was stopped.',
      );
    }
    final complete = metadata['complete'] == true;
    final beforeDirectory = Directory(_join(directory.path, 'before'));
    final afterDirectory = Directory(_join(directory.path, 'after'));
    final beforeExists = (metadata['beforeExists'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    final afterExists = metadata['afterExists'] is Map
        ? (metadata['afterExists'] as Map).cast<String, bool>()
        : const <String, bool>{};
    final candidatePaths = <String>{
      ...(metadata['changedPaths'] as List? ?? const []).whereType<String>(),
    };
    if (!complete) {
      final trackedPaths = metadata['trackedPaths'];
      final onlyPaths = trackedPaths is List
          ? trackedPaths.whereType<String>().toSet()
          : null;
      final current = await _scan(resolvedRoot, onlyPaths: onlyPaths);
      final currentByPath = {
        for (final file in current) file.relativePath: file,
      };
      final currentPaths = currentByPath.keys.toSet();
      for (final path in {...beforeExists, ...currentPaths}) {
        final wasPresent = beforeExists.contains(path);
        final isPresent = currentPaths.contains(path);
        if (wasPresent != isPresent ||
            wasPresent &&
                !await _sameFileBytes(
                  _backupFile(beforeDirectory, path),
                  File(currentByPath[path]!.absolutePath),
                )) {
          candidatePaths.add(path);
        }
      }
    }
    if (candidatePaths.isEmpty) {
      throw const CheckpointException(
        'This checkpoint has no file changes to restore.',
      );
    }

    final trackedPaths = metadata['trackedPaths'];
    final onlyPaths =
        trackedPaths is List ? trackedPaths.whereType<String>().toSet() : null;
    final recovery = await _begin(
      rootPath: resolvedRoot,
      chatId: '${metadata['chatId'] ?? ''}',
      toolName: 'restore_checkpoint',
      onlyPaths: onlyPaths,
    );
    var restored = 0;
    var kept = 0;
    for (final relativePath in candidatePaths) {
      if (!_isSafeRelativePath(relativePath)) {
        kept++;
        continue;
      }
      final target = _join(resolvedRoot, relativePath);
      final currentType =
          await FileSystemEntity.type(target, followLinks: false);
      if (currentType == FileSystemEntityType.link ||
          currentType == FileSystemEntityType.directory) {
        kept++;
        continue;
      }
      if (complete) {
        final afterPresent = afterExists[relativePath] == true;
        if (afterPresent) {
          final afterFile = _backupFile(afterDirectory, relativePath);
          if (!await _sameFileBytes(afterFile, File(target))) {
            kept++;
            continue;
          }
        } else if (currentType != FileSystemEntityType.notFound) {
          kept++;
          continue;
        }
      }
      final wasPresent = beforeExists.contains(relativePath);
      if (wasPresent) {
        await _assertSafeParents(resolvedRoot, relativePath);
        await _copyBackupToTarget(
          _backupFile(beforeDirectory, relativePath),
          target,
        );
      } else if (currentType == FileSystemEntityType.file) {
        await File(target).delete();
        await _removeEmptyParents(resolvedRoot, _parent(target));
      }
      restored++;
    }
    final inverse = await finish(recovery);
    return CheckpointRestoreResult(
      restored: restored,
      keptUserChanges: kept,
      recoveryCheckpointId: inverse?.id,
    );
  }

  Future<void> delete(String id) async {
    final directory = _snapshotDirectory(id);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<({String? before, String? after})> preview(
    String checkpointId,
    String relativePath,
  ) async {
    if (!_isSafeRelativePath(relativePath)) {
      throw const CheckpointException('The checkpoint file path is invalid.');
    }
    final directory = _snapshotDirectory(checkpointId);
    final metadata = await _readMetadata(directory);
    final beforePresent = (metadata['beforeExists'] as List? ?? const [])
        .whereType<String>()
        .contains(relativePath);
    final afterExists = metadata['afterExists'] is Map
        ? (metadata['afterExists'] as Map)[relativePath] == true
        : false;
    return (
      before: beforePresent
          ? await _readPreview(_backupFile(
              Directory(_join(directory.path, 'before')), relativePath))
          : null,
      after: afterExists
          ? await _readPreview(_backupFile(
              Directory(_join(directory.path, 'after')), relativePath))
          : null,
    );
  }

  Future<String?> _readPreview(File file) async {
    if (!await file.exists() || await file.length() > 64 * 1024) return null;
    try {
      return await file.readAsString();
    } on FileSystemException {
      return null;
    } on FormatException {
      return '[Binary file]';
    }
  }

  Future<List<_ScannedFile>> _scan(
    String rootPath, {
    Set<String>? onlyPaths,
  }) async {
    final root = Directory(rootPath);
    final files = <_ScannedFile>[];
    if (onlyPaths != null) {
      for (final path in onlyPaths) {
        if (!_isSafeRelativePath(path)) continue;
        final absolute = _join(rootPath, path);
        if (await FileSystemEntity.type(absolute, followLinks: false) ==
            FileSystemEntityType.file) {
          files.add(_ScannedFile(path, absolute));
        }
      }
      return files;
    }
    final pending = <Directory>[root];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      await for (final entity in current.list(followLinks: false)) {
        final type =
            await FileSystemEntity.type(entity.path, followLinks: false);
        if (type == FileSystemEntityType.link) continue;
        final relative = _relative(rootPath, entity.path);
        if (type == FileSystemEntityType.directory) {
          if (_ignoredDirectories
                  .contains(_basename(entity.path).toLowerCase()) ||
              _isUnderStore(entity.path)) {
            continue;
          }
          pending.add(Directory(entity.path));
        } else if (type == FileSystemEntityType.file) {
          files.add(_ScannedFile(relative, entity.path));
          if (files.length > maxFiles) {
            throw const CheckpointException(
              'Checkpoint stopped before changing files: the working folder contains more than 10,000 files.',
            );
          }
        }
      }
    }
    files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return files;
  }

  Future<void> _ensureStore() async {
    final parent = _directory.parent;
    if (await FileSystemEntity.type(parent.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const CheckpointException('The checkpoint folder is unavailable.');
    }
    if (await FileSystemEntity.type(_directory.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const CheckpointException('The checkpoint folder is unavailable.');
    }
    await _directory.create(recursive: true);
  }

  Future<void> _prune() async {
    final snapshots = await list();
    for (final stale in snapshots.skip(maxSnapshots)) {
      if (stale.complete) await delete(stale.id);
    }
  }

  Future<Map<String, dynamic>> _readMetadata(Directory directory) async {
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const CheckpointException('The checkpoint is unavailable.');
    }
    final file = File(_join(directory.path, 'metadata.json'));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const CheckpointException('The checkpoint is incomplete.');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
      throw const CheckpointException('The checkpoint is invalid.');
    }
    return decoded;
  }

  Future<void> _writeMetadata(
    Directory directory,
    Map<String, Object?> metadata,
  ) async {
    final file = File(_join(directory.path, 'metadata.json'));
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(metadata), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  FileCheckpoint _checkpointFromMetadata(
    Map<String, dynamic> metadata,
    List<CheckpointFileChange> changes,
  ) =>
      FileCheckpoint(
        id: metadata['id'] as String,
        chatId: metadata['chatId'] as String? ?? '',
        toolName: metadata['toolName'] as String? ?? 'unknown',
        rootPath: metadata['rootPath'] as String,
        createdAt: DateTime.tryParse(metadata['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        complete: metadata['complete'] == true,
        files: List.unmodifiable(changes),
        singleFileScope: metadata['singleFileScope'] == true,
      );

  Directory _snapshotDirectory(String id) {
    if (!RegExp(r'^[a-zA-Z0-9-]{8,80}$').hasMatch(id)) {
      throw const CheckpointException('The checkpoint ID is invalid.');
    }
    return Directory(_join(_directory.path, id));
  }

  File _backupFile(Directory directory, String relativePath) =>
      File(_join(directory.path, relativePath));

  Future<void> _copyFile(
    String sourcePath,
    String destinationRoot,
    String relativePath,
  ) async {
    if (!_isSafeRelativePath(relativePath)) {
      throw const CheckpointException('The checkpoint file path is invalid.');
    }
    final source = File(sourcePath);
    final target = File(_join(destinationRoot, relativePath));
    await target.parent.create(recursive: true);
    await target.writeAsBytes(await source.readAsBytes(), flush: true);
  }

  Future<void> _copyBackupToTarget(File source, String targetPath) async {
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const CheckpointException('The saved checkpoint file is missing.');
    }
    final target = File(targetPath);
    await target.parent.create(recursive: true);
    await target.writeAsBytes(await source.readAsBytes(), flush: true);
  }

  Future<bool> _sameFileBytes(File first, File second) async {
    if (!await first.exists() || !await second.exists()) return false;
    if (await first.length() != await second.length()) return false;
    final firstBytes = await first.readAsBytes();
    final secondBytes = await second.readAsBytes();
    if (firstBytes.length != secondBytes.length) return false;
    for (var index = 0; index < firstBytes.length; index++) {
      if (firstBytes[index] != secondBytes[index]) return false;
    }
    return true;
  }

  Future<void> _assertSafeParents(String rootPath, String relativePath) async {
    var current = rootPath;
    final parts = relativePath.split('/');
    for (final part in parts.take(parts.length - 1)) {
      current = _join(current, part);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link ||
          type == FileSystemEntityType.file) {
        throw const CheckpointException(
          'A checkpoint restore path was replaced by a symbolic link or file.',
        );
      }
    }
  }

  Future<void> _removeEmptyParents(
      String rootPath, String directoryPath) async {
    var current = directoryPath;
    while (_isDescendant(rootPath, current)) {
      final directory = Directory(current);
      if (await FileSystemEntity.type(current, followLinks: false) !=
          FileSystemEntityType.directory) {
        return;
      }
      if (await directory.list(followLinks: false).isEmpty) {
        await directory.delete();
        current = _parent(current);
      } else {
        return;
      }
    }
  }

  bool _isUnderStore(String path) =>
      _normalize(_directory.path) == _normalize(path) ||
      _isDescendant(_directory.path, path);

  bool _isFilesystemRoot(String path) {
    final normalized = _normalize(path);
    if (Platform.isWindows)
      return RegExp(r'^[a-z]:/?$', caseSensitive: false).hasMatch(normalized);
    return normalized == '/';
  }

  bool _isSafeRelativePath(String path) =>
      path.isNotEmpty &&
      !_isAbsolutePath(path) &&
      path.split('/').every((part) =>
          part.isNotEmpty &&
          part != '.' &&
          part != '..' &&
          !part.contains(':'));

  bool _isAbsolutePath(String path) =>
      path.startsWith('/') || RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path);

  bool _isDescendant(String rootPath, String candidatePath) {
    final root = _normalize(rootPath).replaceFirst(RegExp(r'/$'), '');
    final candidate = _normalize(candidatePath);
    return candidate.startsWith('$root/');
  }

  String _relative(String rootPath, String filePath) {
    final root = _normalize(rootPath).replaceFirst(RegExp(r'/$'), '');
    return _normalize(filePath).substring(root.length + 1);
  }

  String _normalize(String path) => path
      .replaceAll(r'\', '/')
      .replaceAll(RegExp(r'/+'), '/')
      .replaceFirst(RegExp(r'/$'), '');

  static String _join(String root, String child) {
    final normalized =
        child.replaceAll(RegExp(r'[\\/]'), Platform.pathSeparator);
    final base = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    return '$base$normalized';
  }

  String _parent(String path) {
    final normalized =
        path.replaceAll(r'\', '/').replaceFirst(RegExp(r'/$'), '');
    final separator = normalized.lastIndexOf('/');
    if (separator < 0) return '.';
    if (separator == 2 && RegExp(r'^[a-zA-Z]:').hasMatch(normalized)) {
      return normalized.substring(0, 3).replaceAll('/', Platform.pathSeparator);
    }
    return normalized
        .substring(0, separator)
        .replaceAll('/', Platform.pathSeparator);
  }

  String _basename(String path) => path.replaceAll(r'\', '/').split('/').last;

  String _newId() {
    final random = Random.secure();
    return '${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 32).toRadixString(16)}';
  }
}

class _ScannedFile {
  const _ScannedFile(this.relativePath, this.absolutePath);

  final String relativePath;
  final String absolutePath;
}
