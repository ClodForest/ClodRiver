# Tests for Core API

{describe, it}   = require 'node:test'
assert           = require 'node:assert'
Core             = require '../lib/core'

describe 'Core', ->
  it 'creates a Core instance', ->
    core = new Core()
    assert.ok core instanceof Core

  it 'starts with nextId at 0', ->
    core = new Core()
    assert.strictEqual core.nextId, 0

  describe 'create', ->
    it 'creates an object with sequential IDs', ->
      core = new Core()

      obj1 = core.create()
      obj2 = core.create()

      assert.strictEqual obj1._id, 0
      assert.strictEqual obj2._id, 1

    it 'creates object with parent', ->
      core = new Core()

      parent = core.create()
      child  = core.create(parent)

      assert.strictEqual Object.getPrototypeOf(child), parent

  describe 'toobj', ->
    it 'retrieves object by ID', ->
      core = new Core()
      obj  = core.create()

      assert.strictEqual core.toobj(obj._id), obj

    it 'returns null for non-existent ID', ->
      core = new Core()
      assert.strictEqual core.toobj(999), null

  describe 'destroy', ->
    it 'removes object from registry', ->
      core = new Core()
      obj  = core.create()
      id   = obj._id

      core.destroy id
      assert.strictEqual core.toobj(id), null

    it 'removes named objects from name index', ->
      core = new Core()
      obj  = core.create()
      core.add_obj_name 'test', obj

      core.destroy obj._id
      assert.strictEqual core.objectNames.test, undefined

  describe 'add_obj_name', ->
    it 'associates names with objects', ->
      core = new Core()
      obj  = core.create()

      core.add_obj_name 'sys', obj

      assert.strictEqual core.objectNames.sys, obj

  describe 'toobj', ->
    it 'resolves numeric IDs', ->
      core = new Core()
      obj  = core.create()

      assert.strictEqual core.toobj(obj._id), obj

    it 'resolves #id format', ->
      core = new Core()
      obj  = core.create()

      assert.strictEqual core.toobj("##{obj._id}"), obj

    it 'resolves $name format', ->
      core = new Core()
      obj  = core.create()
      core.add_obj_name 'root', obj

      assert.strictEqual core.toobj('$root'), obj

    it 'returns null for unknown references', ->
      core = new Core()

      assert.strictEqual core.toobj('$unknown'), null
      assert.strictEqual core.toobj('#999'),     null
      assert.strictEqual core.toobj('invalid'),  null

  describe 'addMethod', ->
    it 'adds method to object', ->
      core = new Core()
      obj  = core.create()

      fn = (ctx, args) -> 'result'
      core.addMethod obj, 'test', fn

      assert.strictEqual obj.test, fn

    it 'marks method with definer', ->
      core = new Core()
      obj  = core.create()

      fn = (ctx, args) -> 'result'
      core.addMethod obj, 'test', fn

      assert.strictEqual obj.test.definer, obj
      assert.strictEqual obj.test.methodName, 'test'

  describe 'call', ->
    it 'executes method on object', ->
      core   = new Core()
      obj    = core.create()
      called = false

      core.addMethod obj, 'test', (ctx, args) ->
        called = true
        'result'

      result = core.call obj, 'test', []

      assert.strictEqual called, true
      assert.strictEqual result, 'result'

    it 'provides ctx.get and ctx.set accessing definer namespace', ->
      core = new Core()
      obj  = core.create()

      core.addMethod obj, 'test', (ctx, args) ->
        ctx.set value: 42
        ctx.get 'value'

      result = core.call obj, 'test', []

      assert.strictEqual result, 42
      assert.strictEqual obj._state[obj._id].value, 42

    it 'ctx.get fetches the definer data on children', ->
      core = new Core

      $root = core.create()
      $sys = core.create $root

      core.addMethod $root, 'name', (ctx, args) ->
        [name] = args

        if name
          ctx.set {name}
        else
          ctx.get 'name'

      core.call $root, 'name', ['root']
      core.call $sys,  'name', ['sys']

      sys_name = core.call $sys, 'name', []

      assert.strictEqual sys_name, 'sys'

    it 'provides ColdMUD built-in functions', ->
      core = new Core()
      obj  = core.create()

      core.addMethod obj, 'test', (ctx, args) ->
        this:    ctx.this()
        definer: ctx.definer()
        caller:  ctx.caller()
        sender:  ctx.sender()

      result = core.call obj, 'test', []

      assert.strictEqual result.this,    obj
      assert.strictEqual result.definer, obj
      assert.strictEqual result.caller,  null
      assert.strictEqual result.sender,  null

    it 'passes arguments to method', ->
      core = new Core()
      obj  = core.create()

      core.addMethod obj, 'test', (ctx, args) ->
        args[0] + args[1]

      result = core.call obj, 'test', [10, 20]

      assert.strictEqual result, 30

    it 'returns null for non-existent method', ->
      core = new Core()
      obj  = core.create()

      result = core.call obj, 'missing', []

      assert.strictEqual result, null

    it 'handles method errors gracefully', ->
      core = new Core()
      obj  = core.create()

      core.addMethod obj, 'test', (ctx, args) ->
        throw new Error('test error')

      result = core.call obj, 'test', []

      assert.strictEqual result, null

  describe 'method inheritance', ->
    it 'child inherits parent methods', ->
      core   = new Core()
      parent = core.create()
      child  = core.create(parent)

      core.addMethod parent, 'inherited', (ctx, args) ->
        'from parent'

      result = core.call child, 'inherited', []

      assert.strictEqual result, 'from parent'

    it 'child can override parent methods', ->
      core   = new Core()
      parent = core.create()
      child  = core.create(parent)

      core.addMethod parent, 'test', (ctx, args) -> 'parent'
      core.addMethod child,  'test', (ctx, args) -> 'child'

      result = core.call child, 'test', []

      assert.strictEqual result, 'child'

    it 'inherited method accesses definer namespace, not caller', ->
      core   = new Core()
      parent = core.create()
      child  = core.create(parent)

      parent._state[parent._id] = {name: 'parent'}
      child._state[child._id]   = {name: 'child'}

      core.addMethod parent, 'getName', (ctx, args) ->
        ctx.get 'name'

      result = core.call child, 'getName', []

      assert.strictEqual result, 'parent'

  describe 'ctx.pass', ->
    it 'calls parent method implementation', ->
      core   = new Core()
      parent = core.create()
      child  = core.create(parent)

      core.addMethod parent, 'test', (ctx, args) ->
        'parent: ' + args[0]

      core.addMethod child, 'test', (ctx, args) ->
        parentResult = ctx.pass args[0]
        'child + ' + parentResult

      result = core.call child, 'test', ['value']

      assert.strictEqual result, 'child + parent: value'

    it 'returns null if no parent method exists', ->
      core = new Core()
      obj  = core.create()

      core.addMethod obj, 'test', (ctx, args) ->
        ctx.pass()

      result = core.call obj, 'test', []

      assert.strictEqual result, null

  describe 'complex inheritance chain', ->
    it 'walks full prototype chain', ->
      core        = new Core()
      grandparent = core.create()
      parent      = core.create(grandparent)
      child       = core.create(parent)

      grandparent._state[grandparent._id] = {level: 'grandparent'}
      parent._state[parent._id]           = {level: 'parent'}
      child._state[child._id]             = {level: 'child'}

      core.addMethod grandparent, 'getLevel', (ctx, args) ->
        ctx.get 'level'

      result = core.call child, 'getLevel', []

      assert.strictEqual result, 'grandparent'

    it 'supports pass through multiple levels', ->
      core        = new Core()
      grandparent = core.create()
      parent      = core.create(grandparent)
      child       = core.create(parent)

      core.addMethod grandparent, 'test', (ctx, args) ->
        'gp'

      core.addMethod parent, 'test', (ctx, args) ->
        'p+' + ctx.pass()

      core.addMethod child, 'test', (ctx, args) ->
        'c+' + ctx.pass()

      result = core.call child, 'test', []

      assert.strictEqual result, 'c+p+gp'
