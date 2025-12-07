class CoreMethod
  constructor: (@name, @fn, @definer, @source = null, @flags = {}) ->
    @overrideable = @flags.overrideable ? false
    @disallowOverrides = @flags.disallowOverrides ? false
    @_importNames = null

  invoke: (core, obj, ctx, args) ->
    @_importNames ?= @_extractImportNames()

    resolvedImports = @_resolveImports core, ctx

    innerFn = @fn.apply obj, resolvedImports

    innerFn.call obj, ctx, args

  canBeOverridden: ->
    return false if @disallowOverrides
    @overrideable

  serialize: ->
    name:              @name
    definer:           @definer._id
    source:            @source ? @fn.toString()
    overrideable:      @overrideable
    disallowOverrides: @disallowOverrides

  @deserialize: (data, resolver, compileFn) ->
    definer = resolver data.definer
    fn = compileFn data.source
    new CoreMethod data.name, fn, definer, data.source, {
      overrideable:      data.overrideable
      disallowOverrides: data.disallowOverrides
    }

  _extractImportNames: ->
    src = @fn.toString()
    match = src.match /^(?:function\s*)?\(([^)]*)\)/
    return [] unless match?

    paramNames = match[1].split(',').map (p) -> p.trim()
    return [] if paramNames.length is 0 or paramNames[0] is ''
    paramNames

  _resolveImports: (core, ctx) ->
    # BIFs that require ctx as first argument
    ctxBifs = [
      'textdump', 'listen', 'accept', 'emit', 'emit_error', 'attach_stdio',
      'require', 'load_core', 'core_toobj', 'core_call', 'core_destroy',
      'list_methods'
    ]

    imports = []
    for name in @_importNames
      if core.bifs[name]?
        bif = core.bifs[name]
        # Wrap ctx-requiring BIFs to auto-inject ctx
        if name in ctxBifs
          do (bif) ->
            imports.push (args...) -> bif(ctx, args...)
        else
          imports.push bif
      else if name[0] is '$'
        obj = core.toobj name
        imports.push obj
      else if ctx[name]?
        imports.push ctx[name]
      else
        imports.push null
    imports

module.exports = CoreMethod
