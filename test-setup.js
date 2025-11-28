// Enable source map support for better stack traces
require('source-map-support').install({
  hookRequire: true,
  environment: 'node',
  handleUncaughtExceptions: false
});

// Register CoffeeScript with source maps enabled
require('coffeescript').register({
  sourceMap: true
});
