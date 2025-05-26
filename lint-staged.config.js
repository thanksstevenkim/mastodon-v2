module.exports = {
  '*.{js,jsx,ts,tsx}': ['prettier --write', 'eslint --fix --max-warnings=0'],
  '*.{css,scss}': ['prettier --write', 'stylelint --fix --max-warnings=0'],
  '*.{json,yml,md}': ['prettier --write'],
};
