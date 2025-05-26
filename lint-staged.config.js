module.exports = {
  '*.{js,jsx,ts,tsx}': [
    'prettier --write',
    async (files) => {
      const execSync = require('child_process').execSync;
      console.log('Running eslint on:', files.join(', '));
      try {
        return execSync(`eslint --fix --max-warnings=0 ${files.join(' ')}`, {
          stdio: 'pipe',
          encoding: 'utf-8',
        });
      } catch (error) {
        console.error('ESLint Error:', error.stdout || error.stderr);
        throw error;
      }
    },
  ],
  '*.{css,scss}': [
    'prettier --write',
    async (files) => {
      const execSync = require('child_process').execSync;
      console.log('Running stylelint on:', files.join(', '));
      try {
        const relativePaths = files
          .map((file) => file.replace(process.cwd() + '/', ''))
          .join(' ');
        return execSync(`stylelint --fix --max-warnings=0 ${relativePaths}`, {
          stdio: 'pipe',
          encoding: 'utf-8',
        });
      } catch (error) {
        console.error('Stylelint Error:', error.stdout || error.stderr);
        throw error;
      }
    },
  ],
  '*.{json,yml,md}': ['prettier --write'],
};
