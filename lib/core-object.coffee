class CoreObject
  constructor: (@_id, parent = null) ->
    @_state = {}

    Object.setPrototypeOf(this, parent) if parent?


  serialize: ->
    serialized = {}
    for classId, namespace of @_state
      serialized[classId] = {}
      for key, value of namespace
        serialized[classId][key] = @_serializeValue(value)
    serialized

  deserialize: (state, resolver) ->
    for classId, namespace of state
      @_state[classId] = {}
      for key, value of namespace
        @_state[classId][key] = @_deserializeValue(value, resolver)
    this

  _serializeValue: (value) ->
    if @_isCoreObject(value)
      {$ref: value._id}
    else if Array.isArray(value)
      (@_serializeValue(item) for item in value)
    else if value?.constructor == Object
      if value.$ref? and not @_isCoreObject(value)
        {$ref: false, value: value}
      else
        result = {}
        for key, val of value
          result[key] = @_serializeValue(val)
        result
    else
      value

  _deserializeValue: (value, resolver) ->
    if value?.$ref?
      if value.$ref == false
        value.value
      else
        resolver(value.$ref)
    else if Array.isArray(value)
      (@_deserializeValue(item, resolver) for item in value)
    else if value?.constructor == Object
      result = {}
      for key, val of value
        result[key] = @_deserializeValue(val, resolver)
      result
    else
      value

  _isCoreObject: (value) ->
    value instanceof CoreObject

module.exports = CoreObject
