import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/models.dart';
import 'package:penguin_code/services/project_attachment_loader.dart';

void main() {
  group('ProjectAttachmentLoader', () {
    test('reads selected text files with project-relative names', () async {
      final project = await Directory.systemTemp.createTemp('penguin-files-');
      addTearDown(() => project.delete(recursive: true));
      final sourceDirectory = Directory(
        '${project.path}${Platform.pathSeparator}lib',
      );
      await sourceDirectory.create();
      final source = File(
        '${sourceDirectory.path}${Platform.pathSeparator}main.dart',
      );
      await source.writeAsString('void main() {}');

      final files = await const ProjectAttachmentLoader().readFiles(
        projectPath: project.path,
        selectedPaths: [source.path],
      );

      expect(files, hasLength(1));
      expect(files.single.relativePath, 'lib/main.dart');
      expect(files.single.content, 'void main() {}');
      expect(files.single.sizeBytes, 14);
    });

    test('rejects files outside the selected project', () async {
      final project = await Directory.systemTemp.createTemp('penguin-files-');
      final outside = await Directory.systemTemp.createTemp(
        'penguin-outside-',
      );
      addTearDown(() => project.delete(recursive: true));
      addTearDown(() => outside.delete(recursive: true));
      final file = File('${outside.path}${Platform.pathSeparator}secret.dart');
      await file.writeAsString('const value = 1;');

      await expectLater(
        const ProjectAttachmentLoader().readFiles(
          projectPath: project.path,
          selectedPaths: [file.path],
        ),
        throwsA(
          isA<ProjectAttachmentException>().having(
            (error) => error.message,
            'message',
            contains('inside the selected project'),
          ),
        ),
      );
    });

    test('rejects credential files, unsupported extensions, and binary data',
        () async {
      final project = await Directory.systemTemp.createTemp('penguin-files-');
      addTearDown(() => project.delete(recursive: true));
      final envFile = File('${project.path}${Platform.pathSeparator}.env');
      final credentialFile =
          File('${project.path}${Platform.pathSeparator}service_token.dart');
      final tokenizerFile =
          File('${project.path}${Platform.pathSeparator}tokenizer.dart');
      final imageFile =
          File('${project.path}${Platform.pathSeparator}image.png');
      final binaryFile =
          File('${project.path}${Platform.pathSeparator}source.dart');
      await envFile.writeAsString('TOKEN=private');
      await credentialFile.writeAsString('const token = "private";');
      await tokenizerFile.writeAsString('void tokenize() {}');
      await imageFile.writeAsBytes([0, 1, 2]);
      await binaryFile.writeAsBytes([0xFF, 0xFE]);

      for (final file in [envFile, credentialFile, imageFile, binaryFile]) {
        await expectLater(
          const ProjectAttachmentLoader().readFiles(
            projectPath: project.path,
            selectedPaths: [file.path],
          ),
          throwsA(isA<ProjectAttachmentException>()),
        );
      }
      final files = await const ProjectAttachmentLoader().readFiles(
        projectPath: project.path,
        selectedPaths: [tokenizerFile.path],
      );
      expect(files.single.relativePath, 'tokenizer.dart');
    });

    test('rejects files inside generated project folders', () async {
      final project = await Directory.systemTemp.createTemp('penguin-files-');
      addTearDown(() => project.delete(recursive: true));
      final buildDirectory = Directory(
        '${project.path}${Platform.pathSeparator}build',
      );
      await buildDirectory.create();
      final generatedFile = File(
        '${buildDirectory.path}${Platform.pathSeparator}output.dart',
      );
      await generatedFile.writeAsString('const generated = true;');

      await expectLater(
        const ProjectAttachmentLoader().readFiles(
          projectPath: project.path,
          selectedPaths: [generatedFile.path],
        ),
        throwsA(isA<ProjectAttachmentException>()),
      );
    });

    test('limits each file and total attachment size', () async {
      final project = await Directory.systemTemp.createTemp('penguin-files-');
      addTearDown(() => project.delete(recursive: true));
      final large = File('${project.path}${Platform.pathSeparator}large.txt');
      await large
          .writeAsString('x' * (ProjectAttachmentLoader.maxFileBytes + 1));

      await expectLater(
        const ProjectAttachmentLoader().readFiles(
          projectPath: project.path,
          selectedPaths: [large.path],
        ),
        throwsA(
          isA<ProjectAttachmentException>().having(
            (error) => error.message,
            'message',
            contains('larger than 64 KiB'),
          ),
        ),
      );

      final paths = <String>[];
      for (var index = 0; index < 3; index++) {
        final file = File('${project.path}${Platform.pathSeparator}$index.txt');
        await file.writeAsString('x' * ProjectAttachmentLoader.maxFileBytes);
        paths.add(file.path);
      }
      await expectLater(
        const ProjectAttachmentLoader().readFiles(
          projectPath: project.path,
          selectedPaths: paths,
        ),
        throwsA(
          isA<ProjectAttachmentException>().having(
            (error) => error.message,
            'message',
            contains('128 KiB'),
          ),
        ),
      );
    });

    test('limits attachments per message and skips duplicate selections',
        () async {
      final project = await Directory.systemTemp.createTemp('penguin-files-');
      addTearDown(() => project.delete(recursive: true));
      final firstFile =
          File('${project.path}${Platform.pathSeparator}first.txt');
      final secondFile =
          File('${project.path}${Platform.pathSeparator}second.txt');
      await firstFile.writeAsString('First');
      await secondFile.writeAsString('Second');
      const existing = [
        ChatAttachment(
          relativePath: 'first.txt',
          content: 'First',
          sizeBytes: 5,
        ),
      ];
      const loader = ProjectAttachmentLoader();

      final files = await loader.readFiles(
        projectPath: project.path,
        selectedPaths: [firstFile.path, secondFile.path],
        alreadyAttached: existing,
      );
      expect(files.map((file) => file.relativePath), ['second.txt']);

      await expectLater(
        loader.readFiles(
          projectPath: project.path,
          selectedPaths: [secondFile.path],
          alreadyAttached: List.generate(
            ProjectAttachmentLoader.maxAttachments,
            (index) => ChatAttachment(
              relativePath: 'existing-$index.txt',
              content: '',
              sizeBytes: 0,
            ),
          ),
        ),
        throwsA(isA<ProjectAttachmentException>()),
      );
    });
  });
}
