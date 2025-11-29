{describe, it} = require 'node:test'
assert         = require 'node:assert'

TextDump       = require '../lib/text-dump'
Core           = require '../lib/core'

describe 'TextDump', ->
  describe 'fromString', ->
    it 'parses object definitions', ->
      source = '''
        object 0
        parent 1
        name sys

        object 1
        name root
      '''

      textDump = TextDump.fromString source

      assert.ok textDump.objects?
      assert.strictEqual Object.keys(textDump.objects).length, 2
      assert.strictEqual textDump.objects[0].id, 0
      assert.strictEqual textDump.objects[0].parent, 1
      assert.strictEqual textDump.objects[0].name, 'sys'
      assert.strictEqual textDump.objects[1].id, 1
      assert.strictEqual textDump.objects[1].name, 'root'
      assert.strictEqual textDump.objects[1].parent, null

    it 'parses method definitions', ->
      source = '''
        object 0

        method test
          using foo, bar
          args x, y = 5

          x + y
      '''

      textDump = TextDump.fromString source

      method = textDump.objects[0].methods.test
      assert.ok method?
      assert.deepStrictEqual method.using, ['foo', 'bar']
      assert.strictEqual method.argsRaw, 'x, y = 5'
      assert.ok method.body.length > 0

    it 'parses disallow overrides directive', ->
      source = '''
        object 1

        method critical
          disallow overrides

          return "safe"
      '''

      textDump = TextDump.fromString source

      method = textDump.objects[1].methods.critical
      assert.strictEqual method.disallowOverrides, true

    it 'parses data blocks', ->
      source = '''
        object 0
        name test

        data
          {
            0: {name: 'test', value: 42}
          }
      '''

      textDump = TextDump.fromString source

      assert.ok textDump.objects[0].data?
      assert.ok textDump.objects[0].data.body.length > 0

    it 'ignores comments and blank lines', ->
      source = '''
        # This is a comment
        object 0

        # Another comment
        name sys

        method test
          # Method comment
          args x

          # Inline comment
          x + 1
      '''

      textDump = TextDump.fromString source

      assert.strictEqual textDump.objects[0].name, 'sys'
      assert.ok textDump.objects[0].methods.test?

    it 'throws error for invalid syntax', ->
      source = '''
        object 0
        invalid directive here
      '''

      assert.throws(
        -> TextDump.fromString source
        /Unexpected line/
      )

    it 'throws error for method outside object', ->
      source = '''
        method orphan
          args x
          x
      '''

      assert.throws(
        -> TextDump.fromString source
        /method outside object definition/
      )

  describe 'apply', ->
    it 'creates objects in core', ->
      source = '''
        object 0
        name test_obj
      '''

      textDump = TextDump.fromString source
      core = new Core()
      textDump.apply core

      obj = core.toobj '$test_obj'
      assert.ok obj?, 'should create named object'

    it 'sets up parent relationships', ->
      source = '''
        object 0
        name parent_obj

        object 1
        parent 0
        name child_obj
      '''

      textDump = TextDump.fromString source
      core = new Core()
      textDump.apply core

      parent = core.toobj '$parent_obj'
      child = core.toobj '$child_obj'

      assert.ok parent?
      assert.ok child?
      assert.strictEqual Object.getPrototypeOf(child), parent

    it 'adds methods to objects', ->
      source = '''
        object 0
        name test_obj

        method greet
          using cget

          "Hello, " + cget('name')
      '''

      textDump = TextDump.fromString source
      core = new Core()
      textDump.apply core

      obj = core.toobj '$test_obj'
      obj._state[obj._id] = {name: 'World'}

      result = core.call obj, 'greet', []
      assert.strictEqual result, 'Hello, World'

    it 'applies data blocks', ->
      source = '''
        object 0
        name test_obj

        data
          {
            0: {name: 'test', value: 42}
          }
      '''

      textDump = TextDump.fromString source
      core = new Core()
      refs = textDump.apply core

      obj = core.toobj '$test_obj'
      assert.strictEqual obj._state[obj._id].name, 'test'
      assert.strictEqual obj._state[obj._id].value, 42

    it 'returns object reference map', ->
      source = '''
        object 0
        name first

        object 1
        name second
      '''

      textDump = TextDump.fromString source
      core = new Core()
      refs = textDump.apply core

      assert.ok refs[0]?
      assert.ok refs[1]?
      assert.strictEqual refs[0], core.toobj('$first')
      assert.strictEqual refs[1], core.toobj('$second')

  describe 'fromCore', ->
    it 'captures objects and names', ->
      core = new Core()
      $root = core.toobj '$root'

      obj = core.create $root, 'test_obj'

      textDump = TextDump.fromCore core

      assert.ok textDump.objects?
      names = Object.values(textDump.objects).map (o) -> o.name
      assert.ok names.includes('test_obj')

    it 'captures parent relationships', ->
      core = new Core()
      $root = core.toobj '$root'

      parent = core.create $root, 'parent_obj'
      child = core.create parent, 'child_obj'

      textDump = TextDump.fromCore core

      childDef = Object.values(textDump.objects).find (o) -> o.name is 'child_obj'
      parentDef = Object.values(textDump.objects).find (o) -> o.name is 'parent_obj'

      assert.strictEqual childDef.parent, parentDef.id

    it 'captures methods with source', ->
      core = new Core()
      $root = core.toobj '$root'

      obj = core.create $root, 'test_obj'
      core.addMethod obj, 'greet',
        (cget) -> (ctx, args) -> "Hello"
        '''
        method greet
          using cget

          "Hello"
        '''

      textDump = TextDump.fromCore core

      objDef = Object.values(textDump.objects).find (o) -> o.name is 'test_obj'
      assert.ok objDef.methods.greet?

    it 'captures state data', ->
      core = new Core()
      $root = core.toobj '$root'

      obj = core.create $root, 'test_obj'
      obj._state[obj._id] = {name: 'test', value: 42}

      textDump = TextDump.fromCore core

      objDef = Object.values(textDump.objects).find (o) -> o.name is 'test_obj'
      assert.ok objDef.data?

  describe 'toString', ->
    it 'generates valid .clod format', ->
      core = new Core()
      $root = core.toobj '$root'

      obj = core.create $root, 'test_obj'
      obj._state[obj._id] = {value: 42}

      textDump = TextDump.fromCore core
      output = textDump.toString()

      assert.ok output.includes('object'), 'should have object declarations'
      assert.ok output.includes('name test_obj'), 'should include object name'
      assert.ok output.includes('data'), 'should include data block'

    it 'includes method source', ->
      core = new Core()
      $root = core.toobj '$root'

      obj = core.create $root, 'test_obj'
      core.addMethod obj, 'greet',
        -> (ctx, args) -> "Hello"
        '''
        method greet

          "Hello"
        '''

      textDump = TextDump.fromCore core
      output = textDump.toString()

      assert.ok output.includes('method greet'), 'should include method declaration'

  describe 'round-trip', ->
    it 'preserves core state through fromCore -> toString -> fromString -> apply', ->
      core1 = new Core()
      $root = core1.toobj '$root'

      obj = core1.create $root, 'test_obj'
      obj._state[obj._id] = {data: 'test value', count: 42}

      core1.addMethod obj, 'getData',
        (cget) -> (ctx, args) -> cget 'data'
        '''
        method getData
          using cget

          cget 'data'
        '''

      dump1 = TextDump.fromCore core1
      dumpString = dump1.toString()

      dump2 = TextDump.fromString dumpString
      core2 = new Core()
      dump2.apply core2

      obj_restored = core2.toobj '$test_obj'
      assert.ok obj_restored?, 'should find restored object'

      result = core2.call obj_restored, 'getData', []
      assert.strictEqual result, 'test value'

    it 'preserves object references in state', ->
      core1 = new Core()
      $root = core1.toobj '$root'

      obj1 = core1.create $root, 'obj1'
      obj2 = core1.create $root, 'obj2'

      obj1._state[obj1._id] = {partner: obj2, name: 'first'}
      obj2._state[obj2._id] = {partner: obj1, name: 'second'}

      dump1 = TextDump.fromCore core1
      dumpString = dump1.toString()

      dump2 = TextDump.fromString dumpString
      core2 = new Core()
      dump2.apply core2

      obj1_restored = core2.toobj '$obj1'
      obj2_restored = core2.toobj '$obj2'

      assert.strictEqual obj1_restored._state[obj1_restored._id].name, 'first'
      assert.strictEqual obj2_restored._state[obj2_restored._id].name, 'second'
