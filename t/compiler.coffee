{describe, it} = require 'node:test'
assert         = require 'node:assert'

Compiler       = require '../lib/compiler'
Core           = require '../lib/core'
CoreMethod     = require '../lib/core-method'

describe 'Compiler', ->
  describe 'compileMethod', ->
    it 'compiles method with using clause', ->
      source = '''
        method test
          using send, cget
          args value

          cget 'stored'
      '''

      fn = Compiler.compileMethod source

      assert.ok typeof fn is 'function'

    it 'compiles method without using clause', ->
      source = '''
        method simple
          args x

          x * 2
      '''

      fn = Compiler.compileMethod source

      assert.ok typeof fn is 'function'

    it 'compiles method without args', ->
      source = '''
        method noargs
          using cget

          cget 'value'
      '''

      fn = Compiler.compileMethod source

      assert.ok typeof fn is 'function'

    it 'compiles method with disallow overrides', ->
      source = '''
        method critical
          disallow overrides

          return "safe"
      '''

      result = Compiler.compileMethod source, {returnMetadata: true}

      assert.ok result.fn?
      assert.strictEqual result.disallowOverrides, true

    it 'returns method name', ->
      source = '''
        method myMethod
          args x

          x + 1
      '''

      result = Compiler.compileMethod source, {returnMetadata: true}

      assert.strictEqual result.name, 'myMethod'

    it 'returns using list', ->
      source = '''
        method test
          using foo, bar, $baz

          foo + bar
      '''

      result = Compiler.compileMethod source, {returnMetadata: true}

      assert.deepStrictEqual result.using, ['foo', 'bar', '$baz']

    it 'works with Core.addMethod', ->
      source = '''
        method greet
          using cget

          "Hello, " + cget('name')
      '''

      result = Compiler.compileMethod source, {returnMetadata: true}

      core = new Core()
      obj = core.create()
      obj._state[obj._id] = {name: 'World'}

      flags = if result.disallowOverrides then {disallowOverrides: true} else {}
      core.addMethod obj, result.name, result.fn, source, flags

      output = core.call obj, 'greet', []
      assert.strictEqual output, 'Hello, World'

    it 'preserves relative indentation in method body', ->
      source = '''
        method foo
          args x

          if x > 0
            return x
          else
            return 0
      '''

      result = Compiler.compileMethod source, {returnMetadata: true}

      core = new Core()
      obj = core.create()
      core.addMethod obj, result.name, result.fn, source

      assert.strictEqual core.call(obj, 'foo', [5]), 5
      assert.strictEqual core.call(obj, 'foo', [-1]), 0

    it 'throws error for missing method declaration', ->
      source = '''
        using foo
        args x

        x + 1
      '''

      assert.throws(
        -> Compiler.compileMethod source
        /must start with 'method/
      )

  describe 'parseMethodSource', ->
    it 'extracts method metadata without compiling', ->
      source = '''
        method test
          using foo, bar
          args x, y = 5
          disallow overrides

          x + y
      '''

      metadata = Compiler.parseMethodSource source

      assert.strictEqual metadata.name, 'test'
      assert.deepStrictEqual metadata.using, ['foo', 'bar']
      assert.strictEqual metadata.argsRaw, 'x, y = 5'
      assert.strictEqual metadata.disallowOverrides, true
      assert.ok metadata.body.length > 0
