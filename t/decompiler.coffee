test       = require 'node:test'
assert     = require 'node:assert'
Decompiler = require '../lib/decompiler'

test 'Decompiler: transforms _dispatch to method call', ->
  input = "_dispatch(obj, 'method', arg1, arg2)"
  output = Decompiler.decompile input
  assert.strictEqual output, 'obj.method(arg1, arg2)'

test 'Decompiler: handles no-args case', ->
  input = "_dispatch(obj, 'method')"
  output = Decompiler.decompile input
  assert.strictEqual output, 'obj.method()'

test 'Decompiler: handles @ shorthand', ->
  input = "_dispatch(@, 'helper')"
  output = Decompiler.decompile input
  assert.strictEqual output, '@helper()'

test 'Decompiler: handles @ shorthand with args', ->
  input = "_dispatch(@, 'method', x, y)"
  output = Decompiler.decompile input
  assert.strictEqual output, '@method(x, y)'

test 'Decompiler: handles double-quoted strings', ->
  input = '_dispatch(obj, "method", arg)'
  output = Decompiler.decompile input
  assert.strictEqual output, 'obj.method(arg)'

test 'Decompiler: handles multiple calls on same line', ->
  input = "_dispatch(a, 'foo', 1) + _dispatch(b, 'bar', 2)"
  output = Decompiler.decompile input
  assert.strictEqual output, 'a.foo(1) + b.bar(2)'

test 'Decompiler: preserves non-dispatch code', ->
  input = "x = 1 + 2"
  output = Decompiler.decompile input
  assert.strictEqual output, input

test 'Decompiler: handles chained calls', ->
  input = "_dispatch(_dispatch(obj, 'first'), 'second', arg)"
  output = Decompiler.decompile input
  assert.strictEqual output, 'obj.first().second(arg)'
