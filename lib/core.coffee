CoreObject        = require './core-object'
CoreMethod        = require './core-method'
ExecutionContext  = require './execution-context'
BIFs              = require './bifs'
{
  MethodNotFoundError
  InvalidObjectError
  OverrideNotAllowedError
} = require './errors'

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

  addMethod: (obj, methodName, fn, source = null, flags = {}) ->
    # Check for existing method in prototype chain (not on obj itself)
    proto = Object.getPrototypeOf obj
    while proto? and proto isnt Object.prototype
      if proto.hasOwnProperty(methodName) and proto[methodName] instanceof CoreMethod
        parentMethod = proto[methodName]
        unless parentMethod.canBeOverridden()
          definerName = @_objectName(parentMethod.definer) or "##{parentMethod.definer._id}"
          throw new OverrideNotAllowedError obj._id, methodName, definerName
        # Inherit overrideable flag (unless child explicitly disallows)
        unless flags.disallowOverrides
          flags.overrideable ?= parentMethod.overrideable
        break
      proto = Object.getPrototypeOf proto

    obj[methodName] = new CoreMethod methodName, fn, obj, source, flags

  _objectName: (obj) ->
    for name, o of @objectNames when o is obj
      return "$#{name}"
    null

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
      for key, val of obj when val instanceof CoreMethod
        continue unless obj.hasOwnProperty key
        objMethods[key] = val.serialize()

      methods[id] = objMethods if Object.keys(objMethods).length > 0

    {
      nextId:      @nextId
      parentMap:   parentMap
      nameMap:     nameMap
      objects:     objects
      methods:     methods
    }

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
      resolver = (id) => @objectIDs[id] or null
      for id, objMethods of frozen.methods
        obj = @objectIDs[id]
        for methodName, methodData of objMethods
          try
            coreMethod = CoreMethod.deserialize methodData, resolver, opts.compileFn
            obj[methodName] = coreMethod
          catch error
            console.error "Failed to compile method #{id}.#{methodName}:", error.message

    this

  call: (obj, methodName, args = []) ->
    coreMethod = @_findMethod obj, methodName
    throw new MethodNotFoundError(obj._id, methodName) unless coreMethod?

    ctx = new ExecutionContext this, obj, coreMethod
    coreMethod.invoke this, obj, ctx, args

  callIfExists: (obj, methodName, args = []) ->
    coreMethod = @_findMethod obj, methodName
    unless coreMethod?
      console.log "Event handler not found: ##{obj._id}.#{methodName}"
      return null

    ctx = new ExecutionContext this, obj, coreMethod
    coreMethod.invoke this, obj, ctx, args

  _findMethod: (obj, methodName) ->
    throw new InvalidObjectError("Cannot find method on null object") unless obj?
    return obj[methodName] if obj[methodName] instanceof CoreMethod

    proto = Object.getPrototypeOf(obj)
    if proto and proto != Object.prototype
      @_findMethod(proto, methodName)
    else
      null

module.exports = Core
