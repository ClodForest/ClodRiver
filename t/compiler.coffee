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

    assert.ok code.includes '@addMethod obj0, \'test\''
    assert.ok code.includes '(send, get) ->'
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

    assert.ok code.includes '@addMethod obj0, \'simple\''
    assert.ok code.includes '() ->'
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

    assert.ok code.includes '@addMethod obj0, \'noargs\''
    assert.ok code.includes '(get) ->'
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

  it 'generates correct indentation for method body', ->
    compiler = new Compiler()

    source = '''
object 0
parent 1
name sys

method create
  using create, $root, send, add_obj_name
  args parent = $root, name

  newObj = create parent

  if typeof name is 'string' and name isnt ''
    add_obj_name name, newObj
    send newObj.root_name, name

  newObj
'''

    compiler.compile source
    generated = compiler.generate()

    lines = generated.split '\n'

    # Find the method body lines (after args destructuring)
    bodyStartIdx = lines.findIndex (l) -> l.includes 'newObj = create parent'
    assert.ok bodyStartIdx > 0, 'Should find method body'

    # Check that method body lines have exactly 8 spaces of indent (in do block + inner fn)
    bodyLine = lines[bodyStartIdx]
    assert.match bodyLine, /^        [^ ]/, 'Method body should have 8 spaces indent, not more'
    assert.match bodyLine, /^        newObj = create parent$/, 'First body line should be correctly indented'

    # Check the if statement is also at 8 spaces
    ifLineIdx = lines.findIndex (l) -> l.includes "if typeof name"
    assert.ok ifLineIdx > bodyStartIdx, 'Should find if statement'
    ifLine = lines[ifLineIdx]
    assert.match ifLine, /^        if typeof name/, 'If statement should have 8 spaces indent'

  it 'preserves relative indentation in method body', ->
    compiler = new Compiler()

    source = '''
object 0
name test

method foo
  args x

  if x > 0
    return x
  else
    return 0
'''

    compiler.compile source
    generated = compiler.generate()
    lines = generated.split '\n'

    # Find the if and return statements
    ifLineIdx = lines.findIndex (l) -> l.includes 'if x > 0'
    returnLineIdx = lines.findIndex (l, i) -> i > ifLineIdx and l.includes 'return x'

    assert.ok ifLineIdx > 0, 'Should find if statement'
    assert.ok returnLineIdx > ifLineIdx, 'Should find return statement'

    # The if should be at 8 spaces (in do block + inner fn), the return at 10 spaces
    assert.match lines[ifLineIdx], /^        if x > 0$/, 'If should have 8 spaces'
    assert.match lines[returnLineIdx], /^          return x$/, 'Return should have 10 spaces (8 + 2 for block)'
