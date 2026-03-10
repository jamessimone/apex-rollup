export default [
  { ignores: ['**/*.html', '**/*.css', '**/*js-meta.xml', '**/*.json'] },
  { files: ['**/__tests__/*.js'], rules: { '@lwc/lwc/no-unexpected-wire-adapter-usages': 'off' } }
];
