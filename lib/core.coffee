CoreObject        = require './core-object'
ExecutionContext  = require './execution-context'

class Core
  constructor: ->
    @objectIDs   = {}
    @objectNames = {}
    @nextId      = 0

  create: (parent = null) ->
    id = @nextId++

    @objectIDs[id] = new CoreObject id, parent

  destroy: (ref) ->
    return unless obj = @toobj ref

    for k, v of @objectIDs when v is obj
      delete @objectIDs[k]

    for k, v of @objectNames when v is obj
      delete @objectNames[k]

    return

  add_obj_name: (name, obj) ->
    @objectNames[name] = obj

  del_obj_name: (name) ->
    delete @objectNames[name]

  toobj: (ref) ->
    if 'string' is typeof ref
      return switch ref[0]
        when '#' then @objectIDs[ref[1..]] or null
        when '$' then @objectNames[ref[1..]] or null
        else null

    if 'number' is typeof ref
      return @objectIDs[ref] or null

    if not ref
      return null

    if ref.$ref
      return @objectIDs[ref.$ref] or null

    null

  addMethod: (obj, methodName, fn) ->
    obj[methodName] = fn
    obj[methodName].definer = obj
    obj[methodName].methodName = methodName

  delMethod: (obj, methodName) ->
    delete obj[methodName]

  call: (obj, methodName, args = []) ->
    method = @_findMethod obj, methodName
    return null unless method?

    ctx = new ExecutionContext this, obj, method

    try
      method.call obj, ctx, args
    catch error
      @_handleError obj, methodName, error
      null

  _findMethod: (obj, methodName) ->
    return null unless obj?
    return obj[methodName] if obj[methodName]? and typeof obj[methodName] == 'function'

    proto = Object.getPrototypeOf(obj)
    if proto and proto != Object.prototype
      @_findMethod(proto, methodName)
    else
      null


  _handleError: (obj, methodName, error) ->
    console.error "Error in #{obj._id}.#{methodName}:", error.message
    console.error error.stack

module.exports = Core
