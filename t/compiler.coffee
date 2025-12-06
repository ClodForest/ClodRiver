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

    it 'parses vars directive', ->
      source = '''
        method test
          vars foo, bar

          foo ?= 42
          bar = foo + 1
      '''

      metadata = Compiler.parseMethodSource source

      assert.deepStrictEqual metadata.vars, ['foo', 'bar']

  describe 'vars directive', ->
    it 'compiles method with vars', ->
      source = '''
        method test
          vars counter

          counter ?= 0
          counter += 1
      '''

      fn = Compiler.compileMethod source

      assert.ok typeof fn is 'function'

    it 'loads vars from state at start', ->
      source = '''
        method get_counter
          vars counter

          counter
      '''

      result = Compiler.compileMethod source, {returnMetadata: true}

      core = new Core()
      obj = core.create()
      obj._state[obj._id] = {counter: 42}

      core.addMethod obj, result.name, result.fn, source

      output = core.call obj, 'get_counter', []
      assert.strictEqual output, 42

    it 'saves vars to state at end', ->
      source = '''
        method increment
          vars counter

          counter ?= 0
          counter += 1
      '''

      result = Compiler.compileMethod source, {returnMetadata: true}

      core = new Core()
      obj = core.create()

      core.addMethod obj, result.name, result.fn, source

      core.call obj, 'increment', []
      assert.strictEqual obj._state[obj._id].counter, 1

      core.call obj, 'increment', []
      assert.strictEqual obj._state[obj._id].counter, 2

    it 'saves vars even on exception', ->
      source = '''
        method failing
          vars counter

          counter ?= 0
          counter += 1
          throw new Error "oops"
      '''

      result = Compiler.compileMethod source, {returnMetadata: true}

      core = new Core()
      obj = core.create()

      core.addMethod obj, result.name, result.fn, source

      assert.throws -> core.call obj, 'failing', []

      assert.strictEqual obj._state[obj._id].counter, 1

    it 'works with using and args together', ->
      source = '''
        method add_to_total
          using toint
          args amount
          vars total

          total ?= 0
          total += amount
          total
      '''

      result = Compiler.compileMethod source, {returnMetadata: true}

      core = new Core()
      obj = core.create()

      core.addMethod obj, result.name, result.fn, source

      output = core.call obj, 'add_to_total', [10]
      assert.strictEqual output, 10

      output = core.call obj, 'add_to_total', [5]
      assert.strictEqual output, 15

      assert.strictEqual obj._state[obj._id].total, 15

  describe 'v2 mode', ->
    it 'transforms method calls to _dispatch', ->
      source = '''
        method test
          args x

          x.foo(1, 2)
      '''

      result = Compiler.compileMethod source, {returnMetadata: true, v2: true}

      core = new Core()
      obj = core.create()

      # Create a test object with foo method
      testObj = {
        foo: (a, b) -> a + b
      }

      core.addMethod obj, result.name, result.fn, source

      output = core.call obj, 'test', [testObj]
      assert.strictEqual output, 3

    it 'transforms @method calls', ->
      source = '''
        method test

          @helper()
      '''

      result = Compiler.compileMethod source, {returnMetadata: true, v2: true}

      core = new Core()
      obj = core.create()

      core.addMethod obj, 'helper', -> (ctx, args) -> 'helped!'
      core.addMethod obj, result.name, result.fn, source

      output = core.call obj, 'test', []
      assert.strictEqual output, 'helped!'

    it 'auto-adds _dispatch to imports', ->
      source = '''
        method test
          using $root

          $root.children()
      '''

      result = Compiler.compileMethod source, {returnMetadata: true, v2: true}

      # The function should have _dispatch as first import
      fnStr = result.fn.toString()
      assert.ok fnStr.includes('_dispatch')

    it 'works with chained calls', ->
      source = '''
        method test
          args x

          x.first().second()
      '''

      result = Compiler.compileMethod source, {returnMetadata: true, v2: true}

      core = new Core()
      obj = core.create()

      chainObj = {
        first: -> {second: -> 'chained!'}
      }

      core.addMethod obj, result.name, result.fn, source

      output = core.call obj, 'test', [chainObj]
      assert.strictEqual output, 'chained!'

    it 'does not transform property access without call', ->
      line = "  x = foo.bar"
      transformed = Compiler._transformMethodCalls line
      assert.strictEqual transformed, line

