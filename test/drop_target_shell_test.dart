import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/ui/widgets/drop_target_shell.dart';

void main() {
  group('classifyDroppedPath — pure function', () {
    FileSystemEntityType fakeExists(FileSystemEntityType t) => t;

    test('.mp3 classifies as audioFile', () {
      expect(
        classifyDroppedPath(
          '/tmp/song.mp3',
          existsOverride: (_) => FileSystemEntityType.file,
        ),
        DropType.audioFile,
      );
    });

    test('.WAV (uppercase) classifies as audioFile (case-insensitive ext)', () {
      expect(
        classifyDroppedPath(
          '/tmp/song.WAV',
          existsOverride: (_) => FileSystemEntityType.file,
        ),
        DropType.audioFile,
      );
    });

    test('directory classifies as directory regardless of name', () {
      expect(
        classifyDroppedPath(
          '/tmp/MyMusic',
          existsOverride: (_) => FileSystemEntityType.directory,
        ),
        DropType.directory,
      );
    });

    test('.txt classifies as unsupported', () {
      expect(
        classifyDroppedPath(
          '/tmp/notes.txt',
          existsOverride: (_) => FileSystemEntityType.file,
        ),
        DropType.unsupported,
      );
    });

    test('file with no extension classifies as unsupported', () {
      expect(
        classifyDroppedPath(
          '/tmp/Makefile',
          existsOverride: (_) => FileSystemEntityType.file,
        ),
        DropType.unsupported,
      );
    });

    test('missing path classifies as unsupported', () {
      expect(
        classifyDroppedPath(
          '/nope/does-not-exist.mp3',
          existsOverride: (_) => FileSystemEntityType.notFound,
        ),
        DropType.unsupported,
      );
    });
  });

  group('kSupportedAudioExtensions', () {
    test('covers the canonical DJ formats', () {
      expect(kSupportedAudioExtensions, contains('.mp3'));
      expect(kSupportedAudioExtensions, contains('.wav'));
      expect(kSupportedAudioExtensions, contains('.flac'));
      expect(kSupportedAudioExtensions, contains('.aiff'));
      expect(kSupportedAudioExtensions, contains('.m4a'));
    });

    test('does NOT contain video or document formats', () {
      expect(kSupportedAudioExtensions, isNot(contains('.mp4')));
      expect(kSupportedAudioExtensions, isNot(contains('.pdf')));
      expect(kSupportedAudioExtensions, isNot(contains('.txt')));
    });
  });
}
