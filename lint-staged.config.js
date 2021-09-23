module.exports = {
  '**/lwc/*.js': filenames => `eslint ${filenames.join(' ')} --fix`,
  '*.{cls,cmp,component,css,html,js,json,md,page,trigger,yaml,yml}': filenames => filenames.map(filename => `prettier --write '${filename}'`),
  '*.{cls,trigger}': () => 'sfdx scanner:run --pmdconfig config/pmd-ruleset.xml --engine pmd --severity-threshold 3 --target .'
};
