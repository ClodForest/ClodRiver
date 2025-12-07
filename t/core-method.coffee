test   = require 'node:test'
assert = require 'node:assert'
Core   = require '../lib/core'
CoreMethod = require '../lib/core-method'

test 'CoreMethod: constructor stores all parameters', ->
  core = new Core()
  $root = core.toobj '$root'

  fn = (cget, cset) -> (ctx, args) -> 42
  method = new CoreMethod 'test', fn, $root, 'source code', {disallowOverrides: true}

  assert.strictEqual method.name, 'test'
  assert.strictEqual method.fn, fn
  assert.strictEqual method.definer, $root
  assert.strictEqual method.source, 'source code'
  assert.strictEqual method.disallowOverrides, true

test 'CoreMethod: constructor defaults', ->
  core = new Core()
  $root = core.toobj '$root'

  fn = -> (ctx, args) -> 42
  method = new CoreMethod 'test', fn, $root

  assert.strictEqual method.source, null
  assert.strictEqual method.disallowOverrides, false
  assert.strictEqual method._importNames, null

test 'CoreMethod: invoke with no imports', ->
  core = new Core()
  $root = core.toobj '$root'
  obj = core.create $root

  fn = -> (ctx, args) -> 42
  method = new CoreMethod 'test', fn, $root

  core.addMethod obj, 'test', fn
  ctx = new (require '../lib/execution-context') core, obj, method

  result = method.invoke core, obj, ctx, []
  assert.strictEqual result, 42

test 'CoreMethod: invoke with BIF imports', ->
  core = new Core()
  $root = core.toobj '$root'
  obj = core.create $root

  fn = (create) -> (ctx, args) ->
    newObj = create $root
    newObj._id

  method = new CoreMethod 'test', fn, $root
  ctx = new (require '../lib/execution-context') core, obj, method

  result = method.invoke core, obj, ctx, []
  assert.strictEqual typeof result, 'number'

test 'CoreMethod: invoke with cget/cset imports', ->
  core = new Core()
  $root = core.toobj '$root'
  obj = core.create $root
  obj._state[$root._id] = {value: 10}

  fn = (cget, cset) -> (ctx, args) ->
    current = cget 'value'
    cset value: current + 5
    cget 'value'

  method = new CoreMethod 'test', fn, $root
  ctx = new (require '../lib/execution-context') core, obj, method

  result = method.invoke core, obj, ctx, []
  assert.strictEqual result, 15

test 'CoreMethod: invoke with $name imports', ->
  core = new Core()
  $root = core.toobj '$root'
  $sys = core.toobj '$sys'
  obj = core.create $root

  fn = ($sys, $root) -> (ctx, args) ->
    {sys: $sys._id, root: $root._id}

  method = new CoreMethod 'test', fn, $root
  ctx = new (require '../lib/execution-context') core, obj, method

  result = method.invoke core, obj, ctx, []
  assert.strictEqual result.sys, $sys._id
  assert.strictEqual result.root, $root._id

test 'CoreMethod: invoke with mixed imports', ->
  core = new Core()
  $root = core.toobj '$root'
  $sys = core.toobj '$sys'
  obj = core.create $root

  fn = (create, $sys, cget) -> (ctx, args) ->
    {
      hasBIF:    typeof create is 'function'
      sysId:     $sys._id
      hasGetter: typeof cget is 'function'
    }

  method = new CoreMethod 'test', fn, $root
  ctx = new (require '../lib/execution-context') core, obj, method

  result = method.invoke core, obj, ctx, []
  assert.strictEqual result.hasBIF, true
  assert.strictEqual result.sysId, $sys._id
  assert.strictEqual result.hasGetter, true

test 'CoreMethod: invoke caches import names', ->
  core = new Core()
  $root = core.toobj '$root'
  obj = core.create $root

  fn = (create, cget) -> (ctx, args) -> 42
  method = new CoreMethod 'test', fn, $root
  ctx = new (require '../lib/execution-context') core, obj, method

  assert.strictEqual method._importNames, null

  method.invoke core, obj, ctx, []
  assert.ok Array.isArray method._importNames
  assert.strictEqual method._importNames.length, 2
  assert.strictEqual method._importNames[0], 'create'
  assert.strictEqual method._importNames[1], 'cget'

  # Second call should use cached value
  method.invoke core, obj, ctx, []
  assert.strictEqual method._importNames[0], 'create'

test 'CoreMethod: canBeOverridden respects flags', ->
  core = new Core()
  $root = core.toobj '$root'

  fn = -> (ctx, args) -> 42

  # Default: not overrideable
  defaultMethod = new CoreMethod 'test', fn, $root
  assert.strictEqual defaultMethod.canBeOverridden(), false

  # Explicitly overrideable
  overrideableMethod = new CoreMethod 'test', fn, $root, null, {overrideable: true}
  assert.strictEqual overrideableMethod.canBeOverridden(), true

  # Overrideable but disallowed (disallow wins)
  disallowMethod = new CoreMethod 'test', fn, $root, null, {overrideable: true, disallowOverrides: true}
  assert.strictEqual disallowMethod.canBeOverridden(), false

test 'CoreMethod: serialize with all fields', ->
  core = new Core()
  $root = core.toobj '$root'

  fn = (create) -> (ctx, args) -> 42
  method = new CoreMethod 'test', fn, $root, 'source code', {disallowOverrides: true}

  serialized = method.serialize()

  assert.strictEqual serialized.name, 'test'
  assert.strictEqual serialized.definer, $root._id
  assert.strictEqual serialized.source, 'source code'
  assert.strictEqual serialized.disallowOverrides, true

test 'CoreMethod: serialize with defaults', ->
  core = new Core()
  $root = core.toobj '$root'

  fn = -> (ctx, args) -> 42
  method = new CoreMethod 'test', fn, $root

  serialized = method.serialize()

  assert.strictEqual serialized.name, 'test'
  assert.strictEqual serialized.definer, $root._id
  assert.ok serialized.source.includes('42')
  assert.strictEqual serialized.disallowOverrides, false

test 'CoreMethod: deserialize reconstructs method', ->
  core = new Core()
  $root = core.toobj '$root'

  data = {
    name:              'test'
    definer:           $root._id
    source:            '(create) -> (ctx, args) -> create $root'
    disallowOverrides: true
  }

  resolver = (id) -> core.objectIDs[id]
  CoffeeScript = require 'coffeescript'
  compileFn = (code) ->
    jsCode = CoffeeScript.compile code, {bare: true}
    innerFn = eval(jsCode)
    -> innerFn

  method = CoreMethod.deserialize data, resolver, compileFn

  assert.strictEqual method.name, 'test'
  assert.strictEqual method.definer, $root
  assert.strictEqual method.source, data.source
  assert.strictEqual method.disallowOverrides, true
  assert.strictEqual typeof method.fn, 'function'

test 'CoreMethod: _extractImportNames from function', ->
  core = new Core()
  $root = core.toobj '$root'

  # No parameters
  fn1 = -> (ctx, args) -> 42
  method1 = new CoreMethod 'test', fn1, $root
  assert.deepStrictEqual method1._extractImportNames(), []

  # Single parameter
  fn2 = (create) -> (ctx, args) -> 42
  method2 = new CoreMethod 'test', fn2, $root
  assert.deepStrictEqual method2._extractImportNames(), ['create']

  # Multiple parameters
  fn3 = (create, cget, $sys) -> (ctx, args) -> 42
  method3 = new CoreMethod 'test', fn3, $root
  assert.deepStrictEqual method3._extractImportNames(), ['create', 'cget', '$sys']

test 'CoreMethod: _resolveImports resolves BIFs', ->
  core = new Core()
  $root = core.toobj '$root'
  obj = core.create $root

  fn = (create, toint) -> (ctx, args) -> 42
  method = new CoreMethod 'test', fn, $root
  method._importNames = ['create', 'toint']

  ctx = new (require '../lib/execution-context') core, obj, method
  imports = method._resolveImports core, ctx

  assert.strictEqual imports.length, 2
  assert.strictEqual typeof imports[0], 'function'
  assert.strictEqual typeof imports[1], 'function'
  assert.strictEqual imports[0], core.bifs.create
  assert.strictEqual imports[1], core.bifs.toint

test 'CoreMethod: _resolveImports resolves $names', ->
  core = new Core()
  $root = core.toobj '$root'
  $sys = core.toobj '$sys'
  obj = core.create $root

  fn = ($sys, $root) -> (ctx, args) -> 42
  method = new CoreMethod 'test', fn, $root
  method._importNames = ['$sys', '$root']

  ctx = new (require '../lib/execution-context') core, obj, method
  imports = method._resolveImports core, ctx

  assert.strictEqual imports.length, 2
  assert.strictEqual imports[0], $sys
  assert.strictEqual imports[1], $root

test 'CoreMethod: _resolveImports resolves ctx methods', ->
  core = new Core()
  $root = core.toobj '$root'
  obj = core.create $root

  fn = (cget, cset, definer) -> (ctx, args) -> 42
  method = new CoreMethod 'test', fn, $root
  method._importNames = ['cget', 'cset', 'definer']

  ctx = new (require '../lib/execution-context') core, obj, method
  imports = method._resolveImports core, ctx

  assert.strictEqual imports.length, 3
  assert.strictEqual typeof imports[0], 'function'
  assert.strictEqual typeof imports[1], 'function'
  assert.strictEqual typeof imports[2], 'function'
  assert.strictEqual imports[0], ctx.cget
  assert.strictEqual imports[1], ctx.cset
  assert.strictEqual imports[2], ctx.definer

test 'CoreMethod: _resolveImports returns null for unknown', ->
  core = new Core()
  $root = core.toobj '$root'
  obj = core.create $root

  fn = (unknown, $nonexistent) -> (ctx, args) -> 42
  method = new CoreMethod 'test', fn, $root
  method._importNames = ['unknown', '$nonexistent']

  ctx = new (require '../lib/execution-context') core, obj, method
  imports = method._resolveImports core, ctx

  assert.strictEqual imports.length, 2
  assert.strictEqual imports[0], null
  assert.strictEqual imports[1], null
