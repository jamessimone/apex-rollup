// we use path.resolve to combat cross-platform
// path delimiter incompatibilities ("/" versus "\\", for instance)
const path = require('path');

const resolvePath = fileName => path.resolve(__dirname + '/' + fileName);
const resolvePaths = paths => paths.map(fileName => resolvePath(fileName));

const EXTRA_CODE_COVERAGE_PATHS = resolvePaths([
  'extra-tests/classes/RollupTestUtils.cls',
  'extra-tests/classes/RollupTests.cls',
  'extra-tests/classes/RollupEvaluatorTests.cls',
  'extra-tests/classes/RollupRelationshipFieldFinderTests.cls',
  'extra-tests/classes/RollupLoggerTests.cls',
  'extra-tests/classes/RollupQueryBuilderTests.cls',
  'extra-tests/classes/RollupRecursionItemTests.cls',
  'extra-tests/classes/RollupParentResetProcessorTests.cls'
]);
const CUSTOM_LOGGER_PATHS = resolvePaths([
  'plugins/CustomObjectRollupLogger/classes/RollupCustomObjectLogger.cls',
  'plugins/CustomObjectRollupLogger/classes/RollupLogBatchPurger.cls',
  'plugins/CustomObjectRollupLogger/classes/RollupLogControl.cls',
  'plugins/CustomObjectRollupLogger/classes/RollupLogEventHandler.cls',
  'plugins/CustomObjectRollupLogger/classes/RollupPurgerSchedulable.cls',
  'plugins/CustomObjectRollupLogger/tests/RollupCustomObjectLoggerTests.cls',
  'plugins/CustomObjectRollupLogger/tests/RollupLogBatchPurgerTests.cls'
]);
const NEBULA_LOGGER_ADAPTER_PATHS = resolvePaths([
  'plugins/NebulaLogger/classes/RollupNebulaLoggerAdapter.cls',
  'plugins/NebulaLogger/tests/RollupNebulaLoggerAdapterTest.cls'
]);
const CALLBACK_PATHS = resolvePaths(['plugins/RollupCallback/classes/RollupDispatch.cls', 'plugins/RollupCallback/tests/RollupDispatchTests.cls']);

let shouldRunSfdxScanner = false;
let shouldRunExtraCodeCoveragePackageCreation = false;
let shouldRunNebulaLoggerPackageCreation = false;
let shouldRunCustomLoggerPackageCreation = false;
let shouldRunCallbackPackageCreation = false;

module.exports = {
  '**/lwc/*.js': filenames => `eslint ${filenames.join(' ')} --fix`,
  '*.{cls,cmp,component,css,html,js,json,md,page,trigger,yaml,yml}': filenames => {
    const commands = filenames.map(filename => {
      if (!shouldRunSfdxScanner && (filename.endsWith('.cls') || filename.endsWith('.trigger'))) {
        shouldRunSfdxScanner = true;
      }

      const resolvedPath = path.resolve(filename);
      if (EXTRA_CODE_COVERAGE_PATHS.includes(resolvedPath)) {
        shouldRunExtraCodeCoveragePackageCreation = true;
      }
      if (NEBULA_LOGGER_ADAPTER_PATHS.includes(resolvedPath)) {
        shouldRunNebulaLoggerPackageCreation = true;
      }
      if (CUSTOM_LOGGER_PATHS.includes(resolvedPath)) {
        shouldRunCustomLoggerPackageCreation = true;
      }
      if (CALLBACK_PATHS.includes(resolvedPath)) {
        shouldRunCallbackPackageCreation = true;
      }
      return `prettier --write '${filename}'`;
    });

    if (shouldRunSfdxScanner) {
      commands.push('npm run scan');
    }
    if (shouldRunExtraCodeCoveragePackageCreation) {
      commands.push('npm run create:package:code-coverage');
    }
    if (shouldRunNebulaLoggerPackageCreation) {
      commands.push('npm run create:package:nebula:adapter');
    }
    if (shouldRunCustomLoggerPackageCreation) {
      commands.push('npm run create:package:logger');
    }
    if (shouldRunCallbackPackageCreation) {
      commands.push('npm run create:package:callback');
    }
    return commands;
  }
};
