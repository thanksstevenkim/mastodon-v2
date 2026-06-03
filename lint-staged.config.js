const config = {
  '*': 'prettier --ignore-unknown --write',
  'Gemfile|*.{rb,ruby,ru,rake}':
    'bundle _2.7.2_ exec rubocop --force-exclusion -a',
  '*.{js,jsx,ts,tsx}': 'eslint --fix',
  '*.{css,scss}': 'stylelint --fix',
  '*.haml': 'bin/haml-lint -a',
  '**/*.ts?(x)': () => 'tsc -p tsconfig.json --noEmit',
};

module.exports = config;
