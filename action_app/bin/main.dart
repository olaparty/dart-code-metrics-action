import 'dart:io';

import 'package:action_app/analyze_command.dart';
import 'package:action_app/arguments.dart';
import 'package:action_app/git_utils.dart';
import 'package:action_app/github_workflow_utils.dart';
import 'package:action_app/package_utils.dart';
import 'package:action_app/pubspec.dart';
import 'package:action_app/services/system_process_runner.dart';
import 'package:action_app/task.dart';
import 'package:action_app/unused_files_command.dart';
import 'package:actions_toolkit_dart/core.dart';

Future<void> main(List<String> args) async {
  final workflowUtils =
      GitHubWorkflowUtils(environmentVariables: Platform.environment);

  final processRunner = SystemProcessRunner();

  try {
    final arguments = Arguments(workflowUtils);

    gitHubAuthSetup(arguments.gitHubPersonalAccessTokenKey, processRunner);

    final rootFolder = arguments.packagePath.canonicalPackagePath;
    final pubspecUtils = readPubspec(rootFolder);

    getPackageDependencies(pubspecUtils, rootFolder, processRunner);

    startGroup(name: 'Running Dart Code Metrics');

    final foldersToAnalyze =
        validateFoldersToAnalyze(arguments.folders, rootFolder);

    final foldersToScanForUnusedFiles =
        validateFoldersToAnalyze(arguments.checkUnusedFilesFolders, rootFolder);

    final packageName = arguments.projectName.isEmpty ? pubspecUtils.packageName : arguments.projectName;

    final tasks = [
      (await GitHubTask.create(
        checkRunNamePattern: arguments.analyzeReportTitlePattern,
        packageName: packageName,
        workflowUtils: workflowUtils,
        arguments: arguments,
      ))
          .run((reporter) => analyze(
                packageName,
                rootFolder,
                foldersToAnalyze,
                reporter,
                workflowUtils,
                arguments,
                filesToAnalyze: args.toSet(),
              )),
      if (arguments.checkUnusedFiles)
        (await GitHubTask.create(
          checkRunNamePattern: arguments.unusedFilesReportTitlePattern,
          packageName: packageName,
          workflowUtils: workflowUtils,
          arguments: arguments,
        ))
            .run((reporter) => unusedFiles(
                  packageName,
                  rootFolder,
                  foldersToScanForUnusedFiles,
                  reporter,
                )),
    ];

    await Future.wait(tasks);

    endGroup();
  } on Exception catch (exception, stackTrace) {
    error(message: '$exception\n$stackTrace');
  }
}
