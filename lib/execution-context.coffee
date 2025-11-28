CoreMethod = require './core-method'
{
  InvalidMethodError
  InvalidObjectError
  NoParentMethodError
  MethodNotFoundError
} = require './errors'

class ExecutionContext
  constructor: (@core, @obj, @method, @parent = null) ->
    @_definer = @method.definer
    @stack    = if @parent then [@parent.stack..., @parent.obj] else []

  cget: (key) =>
    @obj._state[@_definer._id]?[key]

  cset: (data) =>
    @obj._state[@_definer._id] ?= {}
    Object.assign @obj._state[@_definer._id], data
    @obj

  cthis:   => @obj
  definer: => @_definer
  caller:  => @parent?.obj or null
  sender:  => @parent?._definer or null

  send: (target, methodName, args...) =>
    throw new InvalidObjectError("Cannot send to null target") unless target?
    throw new InvalidMethodError("Method name must be a string") unless typeof methodName is 'string'

    method = @core._findMethod target, methodName
    throw new MethodNotFoundError(target._id, methodName) unless method?

    childCtx = new ExecutionContext @core, target, method, this
    method.invoke @core, target, childCtx, args

  pass: (args...) =>
    throw new Error("ExecutionContext has no definer") if not @_definer
    parent = Object.getPrototypeOf @_definer
    throw new NoParentMethodError(@obj._id, @method.name) if parent is Object.prototype

    parentMethod = @core._findMethod parent, @method.name
    throw new NoParentMethodError(@obj._id, @method.name) unless parentMethod?

    parentCtx = new ExecutionContext @core, @obj, parentMethod, this
    parentMethod.invoke @core, @obj, parentCtx, args

  # Network methods that need ctx
  listen: (listener, options) =>
    @core.bifs.listen this, listener, options

  accept: (connection) =>
    @core.bifs.accept this, connection

  emit: (data) =>
    @core.bifs.emit this, data

module.exports = ExecutionContext
