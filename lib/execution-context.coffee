class ExecutionContext
  constructor: (@core, @obj, @method, @parent = null) ->
    @_definer = @method.definer
    @stack    = if @parent then [@parent.stack..., @parent.obj] else []

  cget: (key) ->
    @_definer._state[@_definer._id]?[key]

  cset: (data) ->
    @_definer._state[@_definer._id] ?= {}
    Object.assign @_definer._state[@_definer._id], data
    @_definer

  cthis:   -> @obj
  definer: -> @_definer
  caller:  -> @parent?.obj or null
  sender:  -> @parent?._definer or null

  send: (fn, args...) ->
    return null unless fn? and typeof fn is 'function'

    recipient = fn.definer
    return null unless recipient?

    childCtx = new ExecutionContext @core, recipient, fn, this
    fn.call recipient, childCtx, args

  pass: (args...) ->
    parent = Object.getPrototypeOf @_definer
    return null if parent is Object.prototype

    parentMethod = @core._findMethod parent, @method.methodName
    return null unless parentMethod?

    parentCtx = new ExecutionContext @core, @obj, parentMethod, this
    parentMethod.call @obj, parentCtx, args

  # Network methods that need ctx
  listen: (listener, options) =>
    @core.bifs.listen this, listener, options

  accept: (connection) =>
    @core.bifs.accept this, connection

  emit: (data) =>
    @core.bifs.emit this, data

module.exports = ExecutionContext
