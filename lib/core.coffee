CoreObject        = require './core-object'
ExecutionContext  = require './execution-context'
BIFs              = require './bifs'

class Core
  constructor: ->
    @objectIDs   = {}
    @objectNames = {}
    @nextId      = 0
    @bifs        = new BIFs this

    sys  = @create null, 'sys'
    root = @create null, 'root'

    @change_parent sys, root

  create: (parent = null, name) ->
    id = @nextId++

    o = @objectIDs[id] = new CoreObject id, parent

    if name
      @add_obj_name name, o

    return o

  change_parent: (child, parent) ->

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

  add_method: Core::addMethod

  delMethod: (obj, methodName) ->
    delete obj[methodName]

  del_method: Core::delMethod

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

  change_parent: (child, parent) ->
    Object.setPrototypeOf child, parent if parent?

  thaw: (frozen, opts = {}) ->
    @nextId      = frozen.nextId
    @objectIDs   = {}
    @objectNames = {}

    for id, serializedState of frozen.objects
      @objectIDs[id] = new CoreObject parseInt(id), null

    for id, parentId of frozen.parentMap
      child  = @objectIDs[id]
      parent = @objectIDs[parentId]

      @change_parent child, parent if parent?

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
    if arguments.length is 2 and 'function' is typeof obj
      method     = obj
      args       = methodName
      methodName = method.name
    else
      method     = @_findMethod obj, methodName

    return null unless method?

    ctx = new ExecutionContext this, obj, method

    try
      # Resolve imports for nested function pattern
      imports = @_resolveImports method, ctx

      # Call outer function with imports to get inner function
      innerFn = method.apply obj, imports

      # Call inner function with ctx and args
      innerFn.call obj, ctx, args
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

  _resolveImports: (method, ctx) ->
    # Extract parameter names from outer function
    src = method.toString()
    match = src.match /^(?:function\s*)?\(([^)]*)\)/
    return [] unless match?

    paramNames = match[1].split(',').map (p) -> p.trim()
    return [] if paramNames.length is 0 or paramNames[0] is ''

    # Resolve each parameter
    imports = []
    for name in paramNames
      # Check if it's a BIF
      if @bifs[name]?
        imports.push @bifs[name]
      # Check if it's a $name object reference
      else if name[0] is '$'
        obj = @toobj name
        imports.push obj
      # Check if it's an ExecutionContext builtin
      else if ctx[name]?
        imports.push ctx[name]
      else
        # Unknown import - pass null or throw?
        imports.push null

    imports

  _handleError: (obj, methodName, error) ->
    console.error "Error in #{obj._id}.#{methodName}:", error.message
    console.error error.stack

module.exports = Core
