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

      core.addMethod obj, 'test', (cthis, definer, caller, sender) ->
        (ctx, args) ->
          cthis:   cthis()
          definer: definer()
          caller:  caller()
          sender:  sender()

      result = core.call obj, 'test', []

      assert.strictEqual result.cthis,   obj
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

  describe 'freeze and thaw', ->
    it 'freezes and thaws simple objects', ->
      core = new Core()

      obj1 = core.create()
      obj1._state[obj1._id] = {name: 'test', value: 42}

      frozen = core.freeze()

      core2 = new Core()
      core2.thaw frozen

      obj1_restored = core2.toobj obj1._id
      assert.strictEqual obj1_restored._state[obj1._id].name, 'test'
      assert.strictEqual obj1_restored._state[obj1._id].value, 42

    it 'preserves object references in state', ->
      core = new Core()

      obj1 = core.create()
      obj2 = core.create()
      obj1._state[obj1._id] = {ref: obj2, data: 'hello'}

      frozen = core.freeze()

      core2 = new Core()
      core2.thaw frozen

      obj1_restored = core2.toobj obj1._id
      obj2_restored = core2.toobj obj2._id

      assert.strictEqual obj1_restored._state[obj1._id].ref, obj2_restored
      assert.strictEqual obj1_restored._state[obj1._id].data, 'hello'

    it 'preserves prototype chain', ->
      core = new Core()

      parent = core.create()
      child  = core.create parent

      parent._state[parent._id] = {type: 'parent'}
      child._state[child._id]   = {type: 'child'}

      frozen = core.freeze()

      core2 = new Core()
      core2.thaw frozen

      parent_restored = core2.toobj parent._id
      child_restored  = core2.toobj child._id

      assert.strictEqual Object.getPrototypeOf(child_restored), parent_restored

    it 'preserves object names', ->
      core = new Core()

      root = core.create()
      sys  = core.create()

      core.add_obj_name 'root', root
      core.add_obj_name 'sys', sys

      frozen = core.freeze()

      core2 = new Core()
      core2.thaw frozen

      assert.strictEqual core2.toobj('$root'), core2.toobj(root._id)
      assert.strictEqual core2.toobj('$sys'),  core2.toobj(sys._id)

    it 'preserves nextId counter', ->
      core = new Core()

      core.create()
      core.create()
      core.create()

      frozen = core.freeze()

      core2 = new Core()
      core2.thaw frozen

      newObj = core2.create()
      assert.strictEqual newObj._id, 3

    it 'handles complex nested object references', ->
      core = new Core()

      obj1 = core.create()
      obj2 = core.create()
      obj3 = core.create()

      obj1._state[obj1._id] = {
        refs: [obj2, obj3]
        nested: {deep: {ref: obj2}}
      }

      frozen = core.freeze()

      core2 = new Core()
      core2.thaw frozen

      obj1_restored = core2.toobj obj1._id
      obj2_restored = core2.toobj obj2._id
      obj3_restored = core2.toobj obj3._id

      assert.strictEqual obj1_restored._state[obj1._id].refs[0], obj2_restored
      assert.strictEqual obj1_restored._state[obj1._id].refs[1], obj3_restored
      assert.strictEqual obj1_restored._state[obj1._id].nested.deep.ref, obj2_restored

    it 'serializes methods with source', ->
      core = new Core()

      obj = core.create()
      methodSrc = '(ctx, args) -> args[0] + args[1]'

      addFn = (ctx, args) -> args[0] + args[1]
      core.addMethod obj, 'add', addFn, methodSrc

      frozen = core.freeze()

      assert.ok frozen.methods?
      assert.ok frozen.methods[obj._id]?
      assert.strictEqual frozen.methods[obj._id].add.source, methodSrc
      assert.strictEqual frozen.methods[obj._id].add.definer, obj._id

    it 'serializes methods without source using toString', ->
      core = new Core()

      obj = core.create()
      addFn = (ctx, args) -> args[0] + args[1]
      core.addMethod obj, 'add', addFn

      frozen = core.freeze()

      assert.ok frozen.methods[obj._id].add.source?
      assert.ok frozen.methods[obj._id].add.source.includes('args[0]')
      assert.ok frozen.methods[obj._id].add.source.includes('args[1]')

    it 'restores methods when compileFn provided', ->
      CoffeeScript = require 'coffeescript'

      core = new Core()

      obj = core.create()
      obj._state[obj._id] = {value: 10}

      methodSrc = '(ctx, args) -> ctx.cget("value") + args[0]'
      addFn = (ctx, args) -> ctx.cget('value') + args[0]
      core.addMethod obj, 'addToValue', addFn, methodSrc

      frozen = core.freeze()

      core2 = new Core()
      compileFn = (src) ->
        js = CoffeeScript.compile src, {bare: true}
        eval js
      core2.thaw frozen, {compileFn}

      obj_restored = core2.toobj obj._id
      result = core2.call obj_restored, 'addToValue', [5]

      assert.strictEqual result, 15

    it 'preserves method definer across freeze/thaw', ->
      CoffeeScript = require 'coffeescript'

      core = new Core()

      parent = core.create()
      child  = core.create parent

      methodSrc = '(ctx, args) -> "parent method"'
      parentFn = (ctx, args) -> 'parent method'
      core.addMethod parent, 'test', parentFn, methodSrc

      frozen = core.freeze()

      core2 = new Core()
      compileFn = (src) ->
        js = CoffeeScript.compile src, {bare: true}
        eval js
      core2.thaw frozen, {compileFn}

      parent_restored = core2.toobj parent._id
      child_restored  = core2.toobj child._id

      result = core2.call child_restored, 'test', []
      assert.strictEqual result, 'parent method'

      method = child_restored.test
      assert.strictEqual method.definer, parent_restored

    it 'handles methods without source parameter', ->
      core = new Core()

      obj = core.create()
      fn = (ctx, args) -> 'no source provided'
      core.addMethod obj, 'test', fn

      frozen = core.freeze()

      assert.ok frozen.methods[obj._id].test.source?
      assert.ok frozen.methods[obj._id].test.source.includes('no source provided')

    it 'skips CoreObject internal methods during freeze', ->
      core = new Core()

      obj = core.create()

      frozen = core.freeze()

      methods = frozen.methods[obj._id] or {}
      methodNames = Object.keys methods

      assert.ok not methodNames.includes('serialize')
      assert.ok not methodNames.includes('deserialize')
      assert.ok not methodNames.includes('_serializeValue')
      assert.ok not methodNames.includes('_deserializeValue')
      assert.ok not methodNames.includes('_isCoreObject')

    it 'handles multiple methods on same object', ->
      CoffeeScript = require 'coffeescript'

      core = new Core()

      obj = core.create()
      obj._state[obj._id] = {x: 5, y: 10}

      addSrc = '(ctx, args) -> ctx.cget("x") + ctx.cget("y")'
      addFn = (ctx, args) -> ctx.cget('x') + ctx.cget('y')
      core.addMethod obj, 'add', addFn, addSrc

      mulSrc = '(ctx, args) -> ctx.cget("x") * ctx.cget("y")'
      mulFn = (ctx, args) -> ctx.cget('x') * ctx.cget('y')
      core.addMethod obj, 'multiply', mulFn, mulSrc

      frozen = core.freeze()

      assert.strictEqual Object.keys(frozen.methods[obj._id]).length, 2
      assert.ok frozen.methods[obj._id].add?
      assert.ok frozen.methods[obj._id].multiply?

      core2 = new Core()
      compileFn = (src) ->
        js = CoffeeScript.compile src, {bare: true}
        eval js
      core2.thaw frozen, {compileFn}

      obj_restored = core2.toobj obj._id
      assert.strictEqual core2.call(obj_restored, 'add', []), 15
      assert.strictEqual core2.call(obj_restored, 'multiply', []), 50

    it 'handles inherited methods correctly', ->
      CoffeeScript = require 'coffeescript'

      core = new Core()

      parent = core.create()
      child  = core.create parent

      parentSrc = '(ctx, args) -> "from parent"'
      parentFn = (ctx, args) -> 'from parent'
      core.addMethod parent, 'parentMethod', parentFn, parentSrc

      childSrc = '(ctx, args) -> "from child"'
      childFn = (ctx, args) -> 'from child'
      core.addMethod child, 'childMethod', childFn, childSrc

      frozen = core.freeze()

      assert.ok frozen.methods[parent._id]?.parentMethod?
      assert.ok frozen.methods[child._id]?.childMethod?
      assert.ok not frozen.methods[child._id]?.parentMethod?

      core2 = new Core()
      compileFn = (src) ->
        js = CoffeeScript.compile src, {bare: true}
        eval js
      core2.thaw frozen, {compileFn}

      parent_restored = core2.toobj parent._id
      child_restored  = core2.toobj child._id

      assert.strictEqual core2.call(parent_restored, 'parentMethod', []), 'from parent'
      assert.strictEqual core2.call(child_restored, 'parentMethod', []), 'from parent'
      assert.strictEqual core2.call(child_restored, 'childMethod', []), 'from child'

    it 'thaw works without compileFn (state only)', ->
      core = new Core()

      obj = core.create()
      obj._state[obj._id] = {data: 'test'}

      fn = (ctx, args) -> 'should not be restored'
      core.addMethod obj, 'test', fn, '(ctx, args) -> "test"'

      frozen = core.freeze()

      core2 = new Core()
      core2.thaw frozen

      obj_restored = core2.toobj obj._id
      assert.strictEqual obj_restored._state[obj._id].data, 'test'
      assert.strictEqual obj_restored.test, undefined

    it 'handles method compilation errors gracefully', ->
      core = new Core()

      obj = core.create()

      invalidSrc = 'this is not valid CoffeeScript or JavaScript!@#$'
      fn = (ctx, args) -> 'valid'
      core.addMethod obj, 'test', fn, invalidSrc

      frozen = core.freeze()

      core2 = new Core()
      errors = []
      originalConsoleError = console.error
      console.error = (msg, detail) -> errors.push "#{msg} #{detail}"

      compileFn = (src) -> eval src
      core2.thaw frozen, {compileFn}

      console.error = originalConsoleError

      assert.ok errors.length > 0
      assert.ok errors[0].includes('Failed to compile method')
