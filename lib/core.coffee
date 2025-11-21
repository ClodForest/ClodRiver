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

  addMethod: (obj, methodName, fn, source = null) ->
    obj[methodName] = fn
    obj[methodName].definer = obj
    obj[methodName].methodName = methodName
    obj[methodName].source = source if source?

  delMethod: (obj, methodName) ->
    delete obj[methodName]

  freeze: ->
    parentMap = {}
    for id, obj of @objectIDs
      proto = Object.getPrototypeOf obj
      if proto and proto != Object.prototype
        parentMap[id] = proto._id

    nameMap = {}
    for name, obj of @objectNames
      nameMap[name] = obj._id

    objects = {}
    methods = {}
    for id, obj of @objectIDs
      objects[id] = obj.serialize()

      objMethods = {}
      for key, val of obj when typeof val is 'function'
        continue if key in ['constructor', 'serialize', 'deserialize', '_serializeValue', '_deserializeValue', '_isCoreObject']
        continue unless obj.hasOwnProperty key

        methodSource = if val.source?
          val.source
        else
          @_extractMethodSource val

        objMethods[key] = {
          definer: val.definer._id
          source:  methodSource
        }

      methods[id] = objMethods if Object.keys(objMethods).length > 0

    {
      nextId:      @nextId
      parentMap:   parentMap
      nameMap:     nameMap
      objects:     objects
      methods:     methods
    }

  _extractMethodSource: (fn) ->
    src = fn.toString()
    src = src.replace /^function[^(]*\([^)]*\)\s*\{\s*return\s*/, ''
    src = src.replace /;\s*\}$/, ''
    src

  thaw: (frozen, opts = {}) ->
    @nextId      = frozen.nextId
    @objectIDs   = {}
    @objectNames = {}

    for id, serializedState of frozen.objects
      @objectIDs[id] = new CoreObject parseInt(id), null

    for id, parentId of frozen.parentMap
      child  = @objectIDs[id]
      parent = @objectIDs[parentId]
      Object.setPrototypeOf child, parent if parent?

    resolver = (id) => @objectIDs[id] or null

    for id, serializedState of frozen.objects
      @objectIDs[id].deserialize serializedState, resolver

    for name, id of frozen.nameMap
      @objectNames[name] = @objectIDs[id]

    if frozen.methods? and opts.compileFn?
      for id, objMethods of frozen.methods
        obj = @objectIDs[id]
        for methodName, methodData of objMethods
          definer = @objectIDs[methodData.definer]
          try
            fn = opts.compileFn methodData.source
            @addMethod obj, methodName, fn, methodData.source
            fn.definer = definer
          catch error
            console.error "Failed to compile method #{id}.#{methodName}:", error.message

    this

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
