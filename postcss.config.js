const postcssPresetEnv = require('postcss-preset-env');

/** @type {import('postcss-load-config').Config} */
const config = ({ env }) => ({
  plugins: [
    postcssPresetEnv({
      features: {
        'logical-properties-and-values': false
      }
    }),
    env === 'production' ? require('cssnano')({
      parser: require('postcss-safe-parser'),
    }) : '',
  ],
});

module.exports = config;
