{describe, it} = require 'node:test'
assert         = require 'node:assert'
Compiler       = require '../lib/compiler'
Core           = require '../lib/core'

describe 'Compiler', ->
  it 'parses object definitions', ->
    source = '''
      object 0
      parent 1
      name sys

      object 1
      name root
    '''

    compiler = new Compiler()
    objects = compiler.compile source

    assert.strictEqual Object.keys(objects).length, 2
    assert.strictEqual objects[0].id, 0
    assert.strictEqual objects[0].parent, 1
    assert.strictEqual objects[0].name, 'sys'
    assert.strictEqual objects[1].id, 1
    assert.strictEqual objects[1].name, 'root'
    assert.strictEqual objects[1].parent, null

  it 'parses method definitions', ->
    source = '''
      object 0

      method test
        using foo, bar
        args x, y = 5

        x + y
    '''

    compiler = new Compiler()
    objects = compiler.compile source

    method = objects[0].methods.test
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

    compiler = new Compiler()
    objects = compiler.compile source

    method = objects[1].methods.critical
    assert.strictEqual method.disallowOverrides, true

  it 'generates code for simple object', ->
    source = '''
      object 0
      name sys
    '''

    compiler = new Compiler()
    compiler.compile source
    code = compiler.generate()

    assert.ok code.includes 'obj0 = @create null'
    assert.ok code.includes "@add_obj_name 'sys', obj0"
    assert.ok code.includes '$sys = obj0'

  it 'generates code for object with parent', ->
    source = '''
      object 0
      name sys

      object 1
      parent 0
      name root
    '''

    compiler = new Compiler()
    compiler.compile source
    code = compiler.generate()

    assert.ok code.includes 'obj0 = @create null'
    assert.ok code.includes 'obj1 = @create @objectIDs[0]'

  it 'generates method with using clause', ->
    source = '''
      object 0

      method test
        using send, get
        args value

        get 'stored'
    '''

    compiler = new Compiler()
    compiler.compile source
    code = compiler.generate()

    assert.ok code.includes 'obj0.test = (send, get) ->'
    assert.ok code.includes '(ctx, args) ->'
    assert.ok code.includes '[value] = args'

  it 'generates method without using clause', ->
    source = '''
      object 0

      method simple
        args x

        x * 2
    '''

    compiler = new Compiler()
    compiler.compile source
    code = compiler.generate()

    assert.ok code.includes 'obj0.simple = () ->'
    assert.ok code.includes '(ctx, args) ->'
    assert.ok code.includes '[x] = args'

  it 'handles methods without args', ->
    source = '''
      object 0

      method noargs
        using get

        get 'value'
    '''

    compiler = new Compiler()
    compiler.compile source
    code = compiler.generate()

    assert.ok code.includes 'obj0.noargs = (get) ->'
    assert.ok code.includes '(ctx, args) ->'
    assert.ok not code.includes '] = args' # No destructuring

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

    compiler = new Compiler()
    objects = compiler.compile source

    assert.strictEqual objects[0].name, 'sys'
    assert.ok objects[0].methods.test?

  it 'throws error for invalid syntax', ->
    source = '''
      object 0
      invalid directive here
    '''

    compiler = new Compiler()
    assert.throws(
      -> compiler.compile source
      /Unexpected line/
    )

  it 'throws error for method outside object', ->
    source = '''
      method orphan
        args x
        x
    '''

    compiler = new Compiler()
    assert.throws(
      -> compiler.compile source
      /method outside object definition/
    )
