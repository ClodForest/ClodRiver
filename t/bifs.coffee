test       = require 'node:test'
assert     = require 'node:assert'
Core       = require '../lib/core'
CoreMethod = require '../lib/core-method'

test 'BIF: create', ->
  core = new Core()
  $root = core.toobj '$root'

  core.addMethod $root, 'test_create', (create) ->
    (ctx, args) ->
      obj = create ctx.cthis()
      obj

  result = core.call $root, 'test_create'
  assert.ok result?
  assert.strictEqual Object.getPrototypeOf(result), $root

test 'BIF: add_method', ->
  core = new Core()
  $root = core.toobj '$root'
  obj = core.create $root

  core.addMethod $root, 'test_add_method', (add_method) ->
    (ctx, args) ->
      [target, name, fn] = args
      add_method target, name, fn

  testFn = -> (ctx, args) -> 'hello'
  core.call $root, 'test_add_method', [obj, 'greet', testFn]

  assert.ok obj.greet instanceof CoreMethod
  result = core.call obj, 'greet'
  assert.strictEqual result, 'hello'

test 'BIF: add_obj_name', ->
  core = new Core()
  $root = core.toobj '$root'
  obj = core.create $root

  core.addMethod $root, 'test_add_name', (add_obj_name) ->
    (ctx, args) ->
      [name, target] = args
      add_obj_name name, target

  core.call $root, 'test_add_name', ['test', obj]

  assert.strictEqual core.toobj('$test'), obj

test 'BIF: del_obj_name', ->
  core = new Core()
  $root = core.toobj '$root'
  obj = core.create $root
  core.add_obj_name 'test', obj

  core.addMethod $root, 'test_del_name', (del_obj_name) ->
    (ctx, args) ->
      [name] = args
      del_obj_name name

  core.call $root, 'test_del_name', ['test']

  assert.strictEqual core.toobj('$test'), null

test 'BIF: rm_method', ->
  core = new Core()
  $root = core.toobj '$root'
  obj = core.create $root

  core.addMethod obj, 'temp', -> (ctx, args) -> 'temp'

  core.addMethod $root, 'test_rm_method', (rm_method) ->
    (ctx, args) ->
      [target, name] = args
      rm_method target, name

  assert.ok obj.temp instanceof CoreMethod
  core.call $root, 'test_rm_method', [obj, 'temp']
  assert.strictEqual obj.temp, undefined

test 'BIF: toint', ->
  core = new Core()
  $root = core.toobj '$root'
  obj = core.create $root

  core.addMethod $root, 'test_toint', (toint) ->
    (ctx, args) ->
      [target] = args
      toint target

  id = core.call $root, 'test_toint', [obj]
  assert.strictEqual typeof id, 'number'
  assert.strictEqual id, obj._id

test 'BIF: tostr', ->
  core = new Core()
  $root = core.toobj '$root'

  core.addMethod $root, 'test_tostr', (tostr) ->
    (ctx, args) ->
      [value] = args
      tostr value

  assert.strictEqual core.call($root, 'test_tostr', [42]), '42'
  assert.strictEqual core.call($root, 'test_tostr', ['hello']), 'hello'
  assert.strictEqual core.call($root, 'test_tostr', [null]), 'null'
  assert.strictEqual core.call($root, 'test_tostr', [undefined]), 'undefined'

  obj = core.create $root
  result = core.call $root, 'test_tostr', [obj]
  assert.match result, /#\d+/  # Should return #ID format

test 'BIF: children', ->
  core = new Core()
  $root = core.toobj '$root'

  child1 = core.create $root
  child2 = core.create $root
  grandchild = core.create child1

  core.addMethod $root, 'test_children', (children) ->
    (ctx, args) ->
      children ctx.cthis()

  result = core.call $root, 'test_children'
  assert.ok Array.isArray result
  assert.ok result.includes child1
  assert.ok result.includes child2
  assert.ok not result.includes grandchild  # grandchild is not direct child of $root

test 'BIF: lookup_method', ->
  core = new Core()
  $root = core.toobj '$root'
  parent = core.create $root
  child = core.create parent

  core.addMethod parent, 'inherited', -> (ctx, args) -> 'from parent'
  core.addMethod child, 'own', -> (ctx, args) -> 'from child'

  core.addMethod $root, 'test_lookup', (lookup_method) ->
    (ctx, args) ->
      [target, methodName] = args
      lookup_method target, methodName

  # Find method on child
  result = core.call $root, 'test_lookup', [child, 'own']
  assert.ok result?
  assert.strictEqual result.method, child.own
  assert.strictEqual result.definer, child

  # Find inherited method
  result = core.call $root, 'test_lookup', [child, 'inherited']
  assert.ok result?
  assert.strictEqual result.method, parent.inherited
  assert.strictEqual result.definer, parent

  # Method not found
  result = core.call $root, 'test_lookup', [child, 'nonexistent']
  assert.strictEqual result, null

test 'BIF: compile', ->
  core = new Core()
  $root = core.toobj '$root'

  core.addMethod $root, 'test_compile', (compile) ->
    (ctx, args) ->
      [code] = args
      compile code

  code = '''
    (ctx, args) ->
      [x, y] = args
      x + y
  '''

  fn = core.call $root, 'test_compile', [code]
  assert.strictEqual typeof fn, 'function'

  # Test the compiled function
  core.addMethod $root, 'add', fn
  result = core.call $root, 'add', [5, 3]
  assert.strictEqual result, 8

test 'BIF: clod_eval', ->
  core = new Core()
  $root = core.toobj '$root'

  core.addMethod $root, 'test_eval', (clod_eval) ->
    (ctx, args) ->
      [code] = args
      clod_eval code

  result = core.call $root, 'test_eval', ['2 + 2']
  assert.strictEqual result, 4

  result = core.call $root, 'test_eval', ['"hello".toUpperCase()']
  assert.strictEqual result, 'HELLO'

test 'BIF: listen', ->
  core = new Core()
  $sys = core.toobj '$sys'
  $root = core.toobj '$root'
  listener = core.create $root

  servers = []  # Track servers for cleanup

  # Test listen on $sys
  core.addMethod $sys, 'test_listen', (listen) ->
    (ctx, args) ->
      [listenerObj, options] = args
      result = listen listenerObj, options
      servers.push listenerObj._netServer if listenerObj._netServer
      result

  result = core.call $sys, 'test_listen', [listener, {port: 9999, addr: 'localhost'}]

  assert.ok result?
  assert.strictEqual result, listener
  assert.ok listener._netServer?
  assert.strictEqual typeof listener._netServer.close, 'function'

  # Test error on non-$sys
  obj = core.create $root
  core.addMethod obj, 'bad_listen', (listen) ->
    (ctx, args) ->
      listen listener, {port: 9998, addr: 'localhost'}

  try
    core.call obj, 'bad_listen'
    assert.fail 'Should have thrown error'
  catch error
    assert.match error.message, /can only be called on \$sys/

  # Cleanup
  for server in servers
    server.close()

test 'BIF: accept', ->
  core = new Core()
  $root = core.toobj '$root'
  listener = core.create $root
  connection = core.create $root

  # Mock socket
  mockSocket = {
    remoteAddress: '127.0.0.1'
    remotePort: 12345
    on: (event, handler) ->
    write: (data) ->
  }

  # Simulate pending connection
  listener._pendingSocket = mockSocket

  # Add accept method to listener
  core.addMethod listener, 'do_accept', (accept) ->
    (ctx, args) ->
      [conn] = args
      accept conn

  result = core.call listener, 'do_accept', [connection]

  assert.strictEqual result, connection
  assert.strictEqual connection._socket, mockSocket
  assert.strictEqual listener._pendingSocket, undefined

  # Test error when no pending connection
  try
    core.call listener, 'do_accept', [connection]
    assert.fail 'Should have thrown error'
  catch error
    assert.match error.message, /no pending connection/

test 'BIF: emit', ->
  core = new Core()
  $root = core.toobj '$root'
  connection = core.create $root

  # Mock socket
  emittedData = []
  mockSocket = {
    write: (data) -> emittedData.push data
  }

  # Associate socket with connection
  connection._socket = mockSocket

  core.addMethod connection, 'do_emit', (emit) ->
    (ctx, args) ->
      [data] = args
      emit data

  core.call connection, 'do_emit', ['hello world']

  assert.strictEqual emittedData.length, 1
  assert.strictEqual emittedData[0], 'hello world'

  # Test error on non-connection
  obj = core.create $root
  core.addMethod obj, 'bad_emit', (emit) ->
    (ctx, args) ->
      emit 'data'

  try
    core.call obj, 'bad_emit'
    assert.fail 'Should have thrown error'
  catch error
    assert.match error.message, /non-connection object/

test 'BIF integration: eval_on pattern from core.clod', ->
  core = new Core()
  $root = core.toobj '$root'

  # Simulate root.eval_on using BIFs
  core.addMethod $root, 'eval_on', (compile, add_method, rm_method) ->
    (ctx, args) ->
      [code] = args

      fn = compile code
      fn.definer = ctx.cthis()

      # Find temp name
      prefix = "eval_temp_"
      fnNumber = 0
      fnNumber++ while typeof ctx.cthis()[name = prefix + fnNumber] is 'function'

      try
        add_method ctx.cthis(), name, fn
        result = ctx.send ctx.cthis()[name]
      finally
        rm_method ctx.cthis(), name

      result

  code = '''
    (ctx, args) ->
      21 * 2
  '''

  result = core.call $root, 'eval_on', [code]
  assert.strictEqual result, 42

test 'BIF integration: $sys.create with name from core.clod', ->
  core = new Core()
  $sys = core.toobj '$sys'
  $root = core.toobj '$root'

  # Implement $sys.create as in core.clod
  core.addMethod $sys, 'create', (create, add_obj_name, send) ->
    (ctx, args) ->
      [parent = $root, name] = args

      newObj = create parent

      if typeof name is 'string' and name isnt ''
        add_obj_name name, newObj
        ctx.send newObj, 'root_name', [name]

      newObj

  # Add root_name method
  core.addMethod $root, 'root_name', (cset, cget) ->
    (ctx, args) ->
      [newName] = args
      if newName
        cset {name: newName}
      else
        cget 'name'

  obj = core.call $sys, 'create', [$root, 'test_obj']

  assert.ok obj?
  assert.strictEqual core.toobj('$test_obj'), obj
  assert.strictEqual core.call(obj, 'root_name'), 'test_obj'
