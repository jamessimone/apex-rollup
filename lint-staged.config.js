const extraCodeCoveragePaths = [
  'extra-tests/classes/RollupTestUtils.cls',
  'extra-tests/classes/RollupTests.cls',
  'extra-tests/classes/RollupEvaluatorTests.cls',
  'extra-tests/classes/RollupRelationshipFieldFinderTests.cls',
  'extra-tests/classes/RollupLoggerTests.cls',
  'extra-tests/classes/RollupQueryBuilderTests.cls',
  'extra-tests/classes/RollupRecursionItemTests.cls',
  'extra-tests/classes/RollupParentResetProcessorTests.cls'
];

module.exports = {
  '**/lwc/*.js': filenames => `eslint ${filenames.join(' ')} --fix`,
  '*.{cls,cmp,component,css,html,js,json,md,page,trigger,yaml,yml}': filenames => {
    const commands = filenames.map(filename => `prettier --write '${filename}'`);
    if (filenames.filter(fileName => extraCodeCoveragePaths.includes(fileName)).length > 0) {
      commands.push('npm run create:package:code-coverage');
    }
    return commands;
  },
  '*.{cls,trigger}': () => 'npm run scan'
};
