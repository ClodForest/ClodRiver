test   = require 'node:test'
assert = require 'node:assert'
fs     = require 'node:fs'
path   = require 'node:path'
os     = require 'node:os'

Core       = require '../lib/core'
CoreMethod = require '../lib/core-method'
TextDump   = require '../lib/text-dump'
ExecutionContext = require '../lib/execution-context'

createTempClodFile = (content) ->
  tmpDir  = os.tmpdir()
  tmpFile = path.join tmpDir, "test-module-#{Date.now()}.clod"
  fs.writeFileSync tmpFile, content, 'utf8'
  tmpFile

test 'load_core: loads .clod file into child Core', ->
  clodContent = '''
    object 0

    object 1
    parent 0
    name sys

    object 2
    parent 0
    name root

    object 3
    parent 2
    name module
  '''
  tmpFile = createTempClodFile clodContent

  try
    core   = new Core()
    $root  = core.toobj '$root'
    holder = core.create $root

    fn = (load_core) ->
      (ctx, args) ->
        [filePath, holderObj] = args
        load_core filePath, holderObj

    method = new CoreMethod 'load', fn, $root
    ctx    = new ExecutionContext core, holder, method

    result = method.invoke core, holder, ctx, [tmpFile, holder]

    assert.strictEqual result, holder
    assert.ok holder._childCore?
    assert.ok holder._childCore.toobj('$module')?
  finally
    fs.unlinkSync tmpFile

test 'core_toobj: looks up object by name in child Core', ->
  clodContent = '''
    object 0

    object 1
    parent 0
    name sys

    object 2
    parent 0
    name root

    object 3
    parent 2
    name widget
  '''
  tmpFile = createTempClodFile clodContent

  try
    core   = new Core()
    $root  = core.toobj '$root'
    holder = core.create $root

    # First load the child core
    loadFn = (load_core) ->
      (ctx, args) ->
        [filePath, holderObj] = args
        load_core filePath, holderObj

    loadMethod = new CoreMethod 'load', loadFn, $root
    loadCtx    = new ExecutionContext core, holder, loadMethod
    loadMethod.invoke core, holder, loadCtx, [tmpFile, holder]

    # Now test core_toobj
    fn = (core_toobj) ->
      (ctx, args) ->
        [holderObj, name] = args
        core_toobj holderObj, name

    method = new CoreMethod 'lookup', fn, $root
    ctx    = new ExecutionContext core, holder, method

    $widget = method.invoke core, holder, ctx, [holder, '$widget']

    assert.ok $widget?
    assert.ok $widget._id?
  finally
    fs.unlinkSync tmpFile

test 'core_call: calls method on child Core object', ->
  clodContent = '''
    object 0

    object 1
    parent 0
    name sys

    object 2
    parent 0
    name root

    object 3
    parent 2
    name greeter
  '''
  tmpFile = createTempClodFile clodContent

  try
    core   = new Core()
    $root  = core.toobj '$root'
    holder = core.create $root

    # Load the child core
    loadFn = (load_core) ->
      (ctx, args) ->
        [filePath, holderObj] = args
        load_core filePath, holderObj

    loadMethod = new CoreMethod 'load', loadFn, $root
    loadCtx    = new ExecutionContext core, holder, loadMethod
    loadMethod.invoke core, holder, loadCtx, [tmpFile, holder]

    # Add a method to $greeter in child Core
    $greeter = holder._childCore.toobj '$greeter'
    greetFn  = -> (ctx, args) -> "Hello, #{args[0]}!"
    holder._childCore.addMethod $greeter, 'greet', greetFn

    # Now test core_call
    fn = (core_toobj, core_call) ->
      (ctx, args) ->
        [holderObj, name] = args
        obj = core_toobj holderObj, '$greeter'
        core_call holderObj, obj, 'greet', 'World'

    method = new CoreMethod 'test', fn, $root
    ctx    = new ExecutionContext core, holder, method

    result = method.invoke core, holder, ctx, [holder, '$greeter']

    assert.strictEqual result, 'Hello, World!'
  finally
    fs.unlinkSync tmpFile

test 'core_destroy: removes child Core', ->
  clodContent = '''
    object 0

    object 1
    parent 0
    name sys

    object 2
    parent 0
    name root
  '''
  tmpFile = createTempClodFile clodContent

  try
    core   = new Core()
    $root  = core.toobj '$root'
    holder = core.create $root

    # Load the child core
    loadFn = (load_core) ->
      (ctx, args) ->
        [filePath, holderObj] = args
        load_core filePath, holderObj

    loadMethod = new CoreMethod 'load', loadFn, $root
    loadCtx    = new ExecutionContext core, holder, loadMethod
    loadMethod.invoke core, holder, loadCtx, [tmpFile, holder]

    assert.ok holder._childCore?

    # Now test core_destroy
    fn = (core_destroy) ->
      (ctx, args) ->
        [holderObj] = args
        core_destroy holderObj

    method = new CoreMethod 'destroy', fn, $root
    ctx    = new ExecutionContext core, holder, method

    result = method.invoke core, holder, ctx, [holder]

    assert.strictEqual result, holder
    assert.strictEqual holder._childCore, undefined
  finally
    fs.unlinkSync tmpFile

test 'core_toobj: throws if no child core', ->
  core   = new Core()
  $root  = core.toobj '$root'
  holder = core.create $root

  fn = (core_toobj) ->
    (ctx, args) ->
      [holderObj, name] = args
      core_toobj holderObj, name

  method = new CoreMethod 'lookup', fn, $root
  ctx    = new ExecutionContext core, holder, method

  assert.throws(
    -> method.invoke core, holder, ctx, [holder, '$test']
    /No child core/
  )

test 'core_call: throws if no child core', ->
  core   = new Core()
  $root  = core.toobj '$root'
  holder = core.create $root
  fakeObj = {_id: 999}

  fn = (core_call) ->
    (ctx, args) ->
      [holderObj, obj, methodName] = args
      core_call holderObj, obj, methodName

  method = new CoreMethod 'test', fn, $root
  ctx    = new ExecutionContext core, holder, method

  assert.throws(
    -> method.invoke core, holder, ctx, [holder, fakeObj, 'test']
    /No child core/
  )

test 'load_core: child Core is isolated from parent', ->
  clodContent = '''
    object 0

    object 1
    parent 0
    name sys

    object 2
    parent 0
    name root

    object 3
    parent 2
    name isolated
  '''
  tmpFile = createTempClodFile clodContent

  try
    core   = new Core()
    $root  = core.toobj '$root'
    holder = core.create $root

    # Load the child core
    loadFn = (load_core) ->
      (ctx, args) ->
        [filePath, holderObj] = args
        load_core filePath, holderObj

    loadMethod = new CoreMethod 'load', loadFn, $root
    loadCtx    = new ExecutionContext core, holder, loadMethod
    loadMethod.invoke core, holder, loadCtx, [tmpFile, holder]

    childCore = holder._childCore

    # Verify child Core has its own $sys and $root
    assert.ok childCore.toobj('$sys')?
    assert.ok childCore.toobj('$root')?

    # Verify they are different from parent Core's objects
    assert.notStrictEqual childCore.toobj('$sys'), core.toobj('$sys')
    assert.notStrictEqual childCore.toobj('$root'), core.toobj('$root')

    # Verify $isolated only exists in child
    assert.ok childCore.toobj('$isolated')?
    assert.strictEqual core.toobj('$isolated'), null
  finally
    fs.unlinkSync tmpFile

test 'core_call: returns plain values unchanged', ->
  clodContent = '''
    object 0

    object 1
    parent 0
    name sys

    object 2
    parent 0
    name root

    object 3
    parent 2
    name calculator
  '''
  tmpFile = createTempClodFile clodContent

  try
    core   = new Core()
    $root  = core.toobj '$root'
    holder = core.create $root

    # Load the child core
    loadFn = (load_core) ->
      (ctx, args) ->
        [filePath, holderObj] = args
        load_core filePath, holderObj

    loadMethod = new CoreMethod 'load', loadFn, $root
    loadCtx    = new ExecutionContext core, holder, loadMethod
    loadMethod.invoke core, holder, loadCtx, [tmpFile, holder]

    # Add methods that return various types
    $calc = holder._childCore.toobj '$calculator'

    holder._childCore.addMethod $calc, 'getNumber', -> (ctx, args) -> 42
    holder._childCore.addMethod $calc, 'getString', -> (ctx, args) -> "hello"
    holder._childCore.addMethod $calc, 'getArray', -> (ctx, args) -> [1, 2, 3]
    holder._childCore.addMethod $calc, 'getObject', -> (ctx, args) -> {a: 1, b: 2}

    # Test core_call with different return types
    fn = (core_toobj, core_call) ->
      (ctx, args) ->
        [holderObj, methodName] = args
        obj = core_toobj holderObj, '$calculator'
        core_call holderObj, obj, methodName

    method = new CoreMethod 'test', fn, $root
    ctx    = new ExecutionContext core, holder, method

    assert.strictEqual method.invoke(core, holder, ctx, [holder, 'getNumber']), 42
    assert.strictEqual method.invoke(core, holder, ctx, [holder, 'getString']), 'hello'
    assert.deepStrictEqual method.invoke(core, holder, ctx, [holder, 'getArray']), [1, 2, 3]
    assert.deepStrictEqual method.invoke(core, holder, ctx, [holder, 'getObject']), {a: 1, b: 2}
  finally
    fs.unlinkSync tmpFile
