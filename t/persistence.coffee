# Tests for persistence: freeze/thaw and textdump

{describe, it}   = require 'node:test'
assert           = require 'node:assert'
fs               = require 'node:fs'
path             = require 'node:path'

Core             = require '../lib/core'
CoreMethod       = require '../lib/core-method'
Compiler         = require '../lib/compiler'

describe 'Persistence', ->
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
      assert.strictEqual newObj._id, 5

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
      methodSrc = '-> (ctx, args) -> args[0] + args[1]'

      addFn = -> (ctx, args) -> args[0] + args[1]
      core.addMethod obj, 'add', addFn, methodSrc

      frozen = core.freeze()

      assert.ok frozen.methods?
      assert.ok frozen.methods[obj._id]?
      assert.strictEqual frozen.methods[obj._id].add.source, methodSrc
      assert.strictEqual frozen.methods[obj._id].add.definer, obj._id

    it 'serializes methods without source using toString', ->
      core = new Core()

      obj = core.create()
      addFn = -> (ctx, args) -> args[0] + args[1]
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

      methodSrc = '(cget) -> (ctx, args) -> cget("value") + args[0]'
      addFn = (cget) -> (ctx, args) -> cget('value') + args[0]
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

      methodSrc = '-> (ctx, args) -> "parent method"'
      parentFn = -> (ctx, args) -> 'parent method'
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
      fn = -> (ctx, args) -> 'no source provided'
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

      addSrc = '(cget) -> (ctx, args) -> cget("x") + cget("y")'
      addFn = (cget) -> (ctx, args) -> cget('x') + cget('y')
      core.addMethod obj, 'add', addFn, addSrc

      mulSrc = '(cget) -> (ctx, args) -> cget("x") * cget("y")'
      mulFn = (cget) -> (ctx, args) -> cget('x') * cget('y')
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

      parentSrc = '-> (ctx, args) -> "from parent"'
      parentFn = -> (ctx, args) -> 'from parent'
      core.addMethod parent, 'parentMethod', parentFn, parentSrc

      childSrc = '-> (ctx, args) -> "from child"'
      childFn = -> (ctx, args) -> 'from child'
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

      fn = -> (ctx, args) -> 'should not be restored'
      core.addMethod obj, 'test', fn, '-> (ctx, args) -> "test"'

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
      fn = -> (ctx, args) -> 'valid'
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

  describe 'textdump', ->
    it 'creates textdump file with objects and methods', ->
      core = new Core()

      $root = core.toobj '$root'
      $sys  = core.toobj '$sys'

      thing = core.create $root, 'thing'
      thing._state[thing._id] = {name: 'thing', weight: 5}

      core.addMethod thing, 'describe',
        (cget) ->
          (ctx, args) ->
            "A #{cget('name')} weighing #{cget('weight')} pounds"
        '''
        method describe
          using cget

          "A #{cget('name')} weighing #{cget('weight')} pounds"
        '''

      dumpPath = path.join 'db', 'test-dump.clod'
      core.textdump dumpPath

      fullPath = path.join process.cwd(), dumpPath
      assert.ok fs.existsSync(fullPath), 'textdump file should exist'

      content = fs.readFileSync fullPath, 'utf8'

      assert.ok content.includes('object 0'), 'should include $sys'
      assert.ok content.includes('name sys'), 'should include $sys name'
      assert.ok content.includes('object 1'), 'should include $root'
      assert.ok content.includes('name root'), 'should include $root name'
      assert.ok content.includes('object 2'), 'should include thing'
      assert.ok content.includes('name thing'), 'should include thing name'
      assert.ok content.includes('parent 1'), 'thing should have $root as parent'
      assert.ok content.includes('method describe'), 'should include describe method'

      fs.unlinkSync fullPath

    it 'round-trips complete core state', ->
      core = new Core()

      $root = core.toobj '$root'

      obj = core.create $root, 'test_obj'
      obj._state[obj._id] = {data: 'test value', count: 42}

      core.addMethod obj, 'getData',
        (cget) ->
          (ctx, args) ->
            cget 'data'
        '''
        method getData
          using cget

          cget 'data'
        '''

      dumpPath = path.join 'db', 'test-roundtrip.clod'
      core.textdump dumpPath

      fullPath = path.join process.cwd(), dumpPath
      assert.ok fs.existsSync(fullPath), 'dump file should exist'

      source = fs.readFileSync fullPath, 'utf8'

      compiler = new Compiler core2  # IMPORTANT: Use core2, not core!
      compiler.compile source

      operations = compiler.getOperations()
      assert.ok operations.length > 0, 'should have operations'

      core2 = new Core()
      objRefs = {}

      for op in operations
        switch op.type
          when 'create_object'
            parent = if op.parent? then objRefs[op.parent] else null
            newObj = core2.create parent, op.name
            objRefs[op.id] = newObj
            core2.objectIDs[op.id] = newObj

          when 'add_method'
            targetObj = objRefs[op.objectId]
            flags = if op.disallowOverrides then {disallowOverrides: true} else {}
            core2.addMethod targetObj, op.methodName, op.fn, op.source, flags

          when 'set_data'
            targetObj = objRefs[op.objectId]
            ExecutionContext = require '../lib/execution-context'
            dummyMethod = {definer: targetObj, name: '_data_loader'}
            ctx = new ExecutionContext core2, targetObj, dummyMethod
            stateData = op.fn ctx
            # Remap namespace IDs from old object IDs to new object IDs
            for oldNamespaceId, data of stateData
              # Map old object ID to new object
              newObj = objRefs[parseInt(oldNamespaceId)]
              if newObj?
                newNamespaceId = newObj._id
                targetObj._state[newNamespaceId] = data
              else
                # No mapping found, use original ID (shouldn't happen in valid dumps)
                targetObj._state[oldNamespaceId] = data

      obj_restored = core2.toobj '$test_obj'
      assert.ok obj_restored?, 'should find restored object by name'

      result = core2.call obj_restored, 'getData', []
      assert.strictEqual result, 'test value', 'method should work after round-trip'

      fs.unlinkSync fullPath

    it 'textdump is only callable by $sys', ->
      core = new Core()

      $root = core.toobj '$root'
      $sys  = core.toobj '$sys'

      core.addMethod $root, 'tryDump',
        (textdump) ->
          (ctx, args) ->
            textdump 'test.clod'
        '''
        method tryDump
          using textdump

          textdump 'test.clod'
        '''

      assert.throws(
        -> core.call $root, 'tryDump', []
        (err) -> err.message.includes('textdump is only callable by $sys')
      )

    it 'preserves object references in state', ->
      core = new Core()

      $root = core.toobj '$root'

      obj1 = core.create $root, 'obj1'
      obj2 = core.create $root, 'obj2'

      obj1._state[obj1._id] = {partner: obj2, name: 'first'}
      obj2._state[obj2._id] = {partner: obj1, name: 'second'}

      dumpPath = path.join 'db', 'test-refs.clod'
      core.textdump dumpPath

      fullPath = path.join process.cwd(), dumpPath
      content = fs.readFileSync fullPath, 'utf8'

      assert.ok content.includes('data'), 'should have data section'
      assert.ok content.includes('partner'), 'should serialize partner reference'

      fs.unlinkSync fullPath
