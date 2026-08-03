import 'dart:io';

import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/file_operation.dart';
import 'package:yust_ui/src/util/offline/file_operation_handler.dart';
import 'package:yust_ui/src/util/offline/sync_queue.dart';

/// Records every op it is handed; an optional [onExecute] runs first so a test
/// can enqueue more work mid-pass or force a failure.
class _RecordingExecutor implements FileOperationExecutor {
  _RecordingExecutor({this.onExecute});

  final Future<void> Function(FileOperation<YustFile> op)? onExecute;
  final List<String> executed = [];

  @override
  Set<FileOperationType> get handledTypes => {
    FileOperationType.upload,
    FileOperationType.download,
  };

  @override
  Future<void> execute(FileOperation<YustFile> op) async {
    await onExecute?.call(op);
    executed.add(op.fileKey);
  }
}

FileOperation<YustFile> _op(String hash) => FileOperation<YustFile>(
  type: FileOperationType.upload,
  file: YustFile(name: '$hash.pdf', hash: hash, setCreatedAtToNow: false),
);

void main() {
  late Directory root;
  late SyncQueue queue;

  setUp(() {
    root = Directory.systemTemp.createTempSync('file_op_handler_test');
    queue = SyncQueue(directoryProvider: () async => root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  FileOperationHandler handlerWith(FileOperationExecutor executor) =>
      FileOperationHandler(
        executors: [executor],
        queue: queue,
        onlineStream: const Stream<bool>.empty(),
        delay: (_) async {},
      );

  test('applies every pending op and empties the queue', () async {
    final executor = _RecordingExecutor();
    final handler = handlerWith(executor);
    addTearDown(handler.dispose);

    await handler.enqueueAll([_op('h1'), _op('h2')]);

    expect(executor.executed, ['h1', 'h2']);
    expect(await queue.pending(), isEmpty);
  });

  test(
    'an op enqueued mid-pass is applied in the same run, not deferred',
    () async {
      // The first op enqueues a second while the pass is in flight. That inner
      // enqueue's own process call hits the in-progress guard and returns, so
      // only the loop re-reading the queue can pick the new op up.
      late FileOperationHandler handler;
      var injected = false;
      final executor = _RecordingExecutor(
        onExecute: (op) async {
          if (op.fileKey == 'h1' && !injected) {
            injected = true;
            await handler.enqueue(_op('h2'));
          }
        },
      );
      handler = handlerWith(executor);
      addTearDown(handler.dispose);

      await handler.enqueue(_op('h1'));

      expect(executor.executed, ['h1', 'h2']);
      expect(await queue.pending(), isEmpty);
    },
  );

  test('a failing op stays queued and blocks the ones behind it', () async {
    final executor = _RecordingExecutor(
      onExecute: (op) async {
        if (op.fileKey == 'h1') throw StateError('boom');
      },
    );
    final handler = handlerWith(executor);
    addTearDown(handler.dispose);

    await handler.enqueueAll([_op('h1'), _op('h2')]);

    // Stops at the head; nothing applied, both still pending for a later retry.
    expect(executor.executed, isEmpty);
    expect((await queue.pending()).map((op) => op.fileKey), ['h1', 'h2']);
  });
}
