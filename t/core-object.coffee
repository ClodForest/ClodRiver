# Tests for CoreObject class

{describe, it}   = require 'node:test'
assert           = require 'node:assert'
CoreObject       = require '../lib/core-object'

describe 'CoreObject', ->
  it 'creates an object with an ID', ->
    obj = new CoreObject(1)
    assert.strictEqual obj._id, 1

  it 'initializes empty state', ->
    obj = new CoreObject(1)
    assert.deepStrictEqual obj._state, {}

  it 'allows direct state manipulation', ->
    obj = new CoreObject(1)
    obj._state[1] = {name: 'test', value: 42}

    assert.strictEqual obj._state[1].name, 'test'
    assert.strictEqual obj._state[1].value, 42

  it 'sets up prototype chain with parent', ->
    parent = new CoreObject(1)
    child  = new CoreObject(2, parent)

    assert.strictEqual Object.getPrototypeOf(child), parent

  it 'child and parent have separate namespaces', ->
    parent = new CoreObject(1)
    child  = new CoreObject(2, parent)

    parent._state[1] = {name: 'parent'}
    child._state[2] = {name: 'child'}

    assert.deepStrictEqual parent._state[1], {name: 'parent'}
    assert.deepStrictEqual child._state[2], {name: 'child'}

  it 'serializes object references as {$ref: id}', ->
    obj1 = new CoreObject(1)
    obj2 = new CoreObject(2)

    obj1._state[1] = {ref: obj2, normal: 'value'}
    serialized = obj1.serialize()

    assert.deepStrictEqual serialized[1].ref, {$ref: 2}
    assert.strictEqual serialized[1].normal, 'value'

  it 'serializes user data with $ref key by escaping it', ->
    obj = new CoreObject(1)
    obj._state[1] = {data: {$ref: 'user-data'}}

    serialized = obj.serialize()
    assert.deepStrictEqual serialized[1].data, {$ref: false, value: {$ref: 'user-data'}}

  it 'deserializes object references', ->
    obj1 = new CoreObject(1)
    obj2 = new CoreObject(2)

    resolver = (id) ->
      if id == 2 then obj2 else null

    obj1.deserialize({
      1: {ref: {$ref: 2}, normal: 'value'}
    }, resolver)

    assert.strictEqual obj1._state[1].ref, obj2
    assert.strictEqual obj1._state[1].normal, 'value'

  it 'deserializes escaped user data with $ref', ->
    obj = new CoreObject(1)

    obj.deserialize({
      1: {data: {$ref: false, value: {$ref: 'user-data'}}}
    }, -> null)

    assert.deepStrictEqual obj._state[1].data, {$ref: 'user-data'}

  it 'handles multiple namespaces in state', ->
    obj = new CoreObject(3)
    obj._state[1] = {root_prop: 'root'}
    obj._state[2] = {parent_prop: 'parent'}
    obj._state[3] = {my_prop: 'mine'}

    serialized = obj.serialize()
    assert.deepStrictEqual serialized, {
      1: {root_prop: 'root'}
      2: {parent_prop: 'parent'}
      3: {my_prop: 'mine'}
    }
