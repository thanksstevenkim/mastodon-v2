module.exports = {
  extends: ['stylelint-config-standard-scss', 'stylelint-config-prettier-scss'],
  ignoreFiles: [
    'app/javascript/styles/mastodon/reset.scss',
    'coverage/**/*',
    'node_modules/**/*',
    'public/assets/**/*',
    'public/packs/**/*',
    'public/packs-test/**/*',
    'vendor/**/*',
  ],
  reportDescriptionlessDisables: true,
  reportInvalidScopeDisables: true,
  reportNeedlessDisables: true,
  rules: {
    'at-rule-empty-line-before': null,
    'color-function-notation': null,
    'color-hex-length': null,
    'declaration-block-no-redundant-longhand-properties': null,
    'no-descending-specificity': null,
    'no-duplicate-selectors': null,
    'number-max-precision': 8,
    'property-no-vendor-prefix': null,
    'selector-class-pattern': null,
    'selector-id-pattern': null,
    'value-keyword-case': null,
    'value-no-vendor-prefix': null,
    'declaration-empty-line-before': null,
    'media-feature-range-notation': 'context',
    'selector-pseudo-element-colon-notation': 'double',
    'alpha-value-notation': 'percentage',
    'rule-empty-line-before': ['always', {
      except: ['first-nested'],
      ignore: ['after-comment']
    }],
    'property-no-unknown': [true, {
      ignoreProperties: [
        'box-orient',
        '/^mso-/',
        'content-visibility',
        '-webkit-box-orient'
      ]
    }],

    'scss/dollar-variable-empty-line-before': null,
    'scss/no-global-function-names': null,
    'scss/at-extend-no-missing-placeholder': null,
  },
  overrides: [
    {
      'files': ['app/javascript/styles/mailer.scss'],
      rules: {
        'property-no-unknown': [
          true,
          {
            ignoreProperties: [
              '/^mso-/',
              'box-orient'
            ]
          },
        ],
      },
    },
  ],
};
