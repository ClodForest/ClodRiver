# Tests for Core API

{describe, it}   = require 'node:test'
assert           = require 'node:assert'

CoreMethod       = require '../lib/core-method'
Core             = require '../lib/core'
{
  MethodNotFoundError
  NoParentMethodError
}                = require '../lib/errors'

describe 'Core', ->
  it 'creates a Core instance', ->
    core = new Core()
    assert.ok core instanceof Core

  it 'starts with nextId at 2', ->
    core = new Core()
    # Core creates $sys and $root in constructor, so nextId starts at 2
    assert.strictEqual core.nextId, 2

  describe 'create', ->
    it 'creates an object with sequential IDs', ->
      core = new Core()

      obj1 = core.create()
      obj2 = core.create()

      # Core creates $sys (id 0) and $root (id 1) in constructor
      assert.strictEqual obj1._id, 2
      assert.strictEqual obj2._id, 3

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

      fn = -> (ctx, args) -> 'result'
      core.addMethod obj, 'test', fn

      assert.ok obj.test instanceof CoreMethod
      assert.strictEqual obj.test.fn, fn

    it 'marks method with definer', ->
      core = new Core()
      obj  = core.create()

      fn = -> (ctx, args) -> 'result'
      core.addMethod obj, 'test', fn

      assert.strictEqual obj.test.definer, obj
      assert.strictEqual obj.test.name, 'test'

  describe 'call', ->
    it 'executes method on object', ->
      core   = new Core()
      obj    = core.create()
      called = false

      core.addMethod obj, 'test', ->
        (ctx, args) ->
          called = true
          'result'

      result = core.call obj, 'test', []

      assert.strictEqual called, true
      assert.strictEqual result, 'result'

    it 'provides ctx.cget and ctx.cset accessing definer namespace', ->
      core = new Core()
      obj  = core.create()

      core.addMethod obj, 'test', (cget, cset) ->
        (ctx, args) ->
          cset value: 42
          cget 'value'

      result = core.call obj, 'test', []

      assert.strictEqual result, 42
      assert.strictEqual obj._state[obj._id].value, 42

    it 'ctx.cget fetches the definer data on children', ->
      core = new Core

      $root = core.create()
      $sys = core.create $root

      core.addMethod $root, 'name', (cget, cset) ->
        (ctx, args) ->
          [name] = args

          if name
            cset {name}
          else
            cget 'name'

      core.call $root, 'name', ['root']
      core.call $sys,  'name', ['sys']

      sys_name = core.call $sys, 'name', []

      assert.strictEqual sys_name, 'sys'

    it 'provides ColdMUD built-in functions', ->
      core = new Core()
      obj  = core.create()

      core.addMethod obj, 'test', (definer, caller, sender) ->
        (ctx, args) ->
          definer: definer()
          caller:  caller()
          sender:  sender()

      result = core.call obj, 'test', []

      assert.strictEqual result.definer, obj
      assert.strictEqual result.caller,  null
      assert.strictEqual result.sender,  null

    it 'passes arguments to method', ->
      core = new Core()
      obj  = core.create()

      core.addMethod obj, 'test', ->
        (ctx, args) ->
          args[0] + args[1]

      result = core.call obj, 'test', [10, 20]

      assert.strictEqual result, 30

    it 'throws error for non-existent method', ->
      core = new Core()
      obj  = core.create()

      assert.throws(
        -> core.call obj, 'missing', []
        MethodNotFoundError
      )

    it 'propagates method errors', ->
      core = new Core()
      obj  = core.create()

      core.addMethod obj, 'test', ->
        (ctx, args) ->
          throw new Error('test error')

      assert.throws(
        -> core.call obj, 'test', []
        (error) -> error.message is 'test error'
      )

  describe 'method inheritance', ->
    it 'child inherits parent methods', ->
      core   = new Core()
      parent = core.create()
      child  = core.create(parent)

      core.addMethod parent, 'inherited', ->
        (ctx, args) ->
          'from parent'

      result = core.call child, 'inherited', []

      assert.equal result, 'from parent'

    it 'child can override parent methods', ->
      core   = new Core()
      parent = core.create()
      child  = core.create(parent)

      core.addMethod parent, 'test', -> (ctx, args) -> 'parent'
      core.addMethod child,  'test', -> (ctx, args) -> 'child'

      result = core.call child, 'test', []

      assert.strictEqual result, 'child'

    it 'inherited method accesses definer namespace, not caller', ->
      core   = new Core()
      parent = core.create()
      child  = core.create(parent)

      parent._state[parent._id] = {name: 'parent'}
      child._state[parent._id]  = {name: 'parent in child'}
      child._state[child._id]   = {name: 'child'}

      core.addMethod parent, 'getName', (cget) ->
        (ctx, args) ->
          cget 'name'

      result = core.call child, 'getName', []

      assert.strictEqual result, 'parent in child'

  describe 'ctx.pass', ->
    it 'calls parent method implementation', ->
      core   = new Core()
      parent = core.create()
      child  = core.create(parent)

      core.addMethod parent, 'test', ->
        (ctx, args) ->
          s = 'parent: ' + args[0]
          console.log {parent: s}
          s

      core.addMethod child, 'test', (pass) ->
        (ctx, args) ->
          parentResult = pass args[0]
          s = 'child + ' + parentResult
          console.log {child: s}
          s

      result = core.call child, 'test', ['value']

      assert.strictEqual result, 'child + parent: value'

    it 'throws error if no parent method exists', ->
      core = new Core()
      obj  = core.create()

      core.addMethod obj, 'test', (pass) ->
        (ctx, args) ->
          pass()

      assert.throws(
        -> core.call obj, 'test', []
        NoParentMethodError
      )

  describe '_dispatch', ->
    it 'dispatches to CoreObject via ClodMUD path', ->
      core = new Core()
      obj  = core.create()

      core.addMethod obj, 'greet', ->
        (ctx, args) ->
          "Hello, #{args[0]}!"

      core.addMethod obj, 'caller', (send) ->
        (ctx, args) ->
          send obj, 'greet', 'World'

      result = core.call obj, 'caller', []

      assert.strictEqual result, 'Hello, World!'

    it 'dispatches to plain JS object directly', ->
      core = new Core()
      obj  = core.create()

      core.addMethod obj, 'test_js', (send) ->
        (ctx, args) ->
          jsObj = {
            greet: (name) -> "Hi, #{name}!"
          }
          send jsObj, 'greet', 'JS'

      result = core.call obj, 'test_js', []

      assert.strictEqual result, 'Hi, JS!'

    it 'throws for missing method on JS object', ->
      core = new Core()
      obj  = core.create()

      core.addMethod obj, 'test_missing', (send) ->
        (ctx, args) ->
          jsObj = {}
          send jsObj, 'missing', 'arg'

      assert.throws(
        -> core.call obj, 'test_missing', []
        /No method missing on JS object/
      )

  return
  describe 'complex inheritance chain', ->
    it 'walks full prototype chain', ->
      core        = new Core()
      grandparent = core.create()
      parent      = core.create(grandparent)
      child       = core.create(parent)

      grandparent._state[grandparent._id] = {level: 'grandparent'}
      parent._state[parent._id]           = {level: 'parent'}
      child._state[child._id]             = {level: 'child'}

      core.addMethod grandparent, 'getLevel', (cget) ->
        (ctx, args) ->
          cget 'level'

      result = core.call child, 'getLevel', []

      assert.strictEqual result, 'grandparent'

    it 'supports pass through multiple levels', ->
      core        = new Core()
      grandparent = core.create()
      parent      = core.create(grandparent)
      child       = core.create(parent)

      core.addMethod grandparent, 'test', ->
        (ctx, args) ->
          'gp'

      core.addMethod parent, 'test', (pass) ->
        (ctx, args) ->
          'p+' + pass()

      core.addMethod child, 'test', (pass) ->
        (ctx, args) ->
          'c+' + pass()

      result = core.call child, 'test', []

      assert.strictEqual result, 'c+p+gp'
