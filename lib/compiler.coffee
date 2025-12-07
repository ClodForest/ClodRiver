vm         = require 'vm'
sourceMaps = require './source-maps'
ClodLang   = require './clod-lang'

class Compiler
  @compileMethod: (source, options = {}) ->
    CoffeeScript = require 'coffeescript'

    metadata = @parseMethodSource source

    # In v2 mode, ClodLang transforms happen in _generateFunctionSource

    fnSource = @_generateFunctionSource metadata, options
    result = CoffeeScript.compile fnSource, {bare: true, sourceMap: true}
    scriptFilename = "method.#{metadata.name}"
    sourceMap = JSON.parse result.v3SourceMap
    sourceMap.sources = [scriptFilename]
    sourceMap.sourcesContent = [fnSource]
    sourceMaps.register scriptFilename, JSON.stringify sourceMap
    script = new vm.Script result.js, {filename: scriptFilename}
    fn = script.runInThisContext()

    if options.returnMetadata
      {
        fn:                fn
        name:              metadata.name
        using:             metadata.using
        argsRaw:           metadata.argsRaw
        overrideable:      metadata.overrideable
        disallowOverrides: metadata.disallowOverrides
        source:            source
      }
    else
      fn

  @parseMethodSource: (source) ->
    lines = source.split '\n'
    result = {
      name:              null
      using:             []
      argsRaw:           null
      vars:              []
      body:              []
      overrideable:      false
      disallowOverrides: false
    }

    inBody = false
    headerDone = false

    for line in lines
      trimmed = line.trim()
      continue if trimmed is '' and not inBody
      continue if trimmed[0] is '#' and not inBody

      if match = trimmed.match /^method\s+(\w+)$/
        result.name = match[1]
        continue

      unless result.name?
        throw new Error "Method source must start with 'method <name>'"

      if not headerDone
        if match = trimmed.match /^using\s+(.+)$/
          result.using = match[1].split(/\s*,\s*/)
          continue

        if match = trimmed.match /^args\s+(.+)$/
          result.argsRaw = match[1]
          continue

        if match = trimmed.match /^vars\s+(.+)$/
          result.vars = match[1].split(/\s*,\s*/)
          continue

        if trimmed is 'overrideable'
          result.overrideable = true
          continue

        if trimmed is 'disallow overrides'
          result.disallowOverrides = true
          continue

      headerDone = true
      inBody = true
      result.body.push line

    result

  @_generateFunctionSource: (metadata, options = {}) ->
    lines = []
    hasVars = metadata.vars?.length > 0

    # In v2 mode, auto-add _dispatch and toobj to imports (deduplicated)
    imports = if options.v2
      userImports = metadata.using or []
      allImports = ['_dispatch', 'toobj']
      for imp in userImports
        allImports.push imp unless imp in allImports
      allImports.join ', '
    else if metadata.using.length > 0
      metadata.using.join ', '
    else
      null

    if imports
      lines.push "(#{imports}) ->"
    else
      lines.push "() ->"

    lines.push "  (ctx, args) ->"

    if metadata.argsRaw and metadata.argsRaw.trim() isnt ''
      lines.push "    [#{metadata.argsRaw}] = args"
      lines.push ""

    # Load vars from state
    if hasVars
      varsList = metadata.vars.join ', '
      lines.push "    {#{varsList}} = @_state[ctx._definer._id] ? {}"
      lines.push ""
      lines.push "    try"

    # Determine base indent for body
    bodyIndent = if hasVars then "      " else "    "

    minIndent = Infinity
    for bodyLine in metadata.body
      continue if bodyLine.trim() is ''
      indent = bodyLine.match(/^(\s*)/)[1].length
      minIndent = Math.min minIndent, indent

    minIndent = 0 if minIndent is Infinity

    # Transform body using ClodLang in v2 mode
    bodyLines = metadata.body
    if options.v2
      bodySource = bodyLines.join '\n'
      transformedBody = @_transformWithClodLang bodySource
      bodyLines = transformedBody.split '\n'

    for bodyLine in bodyLines
      if bodyLine.trim() is ''
        lines.push ''
      else
        stripped = bodyLine.substring minIndent
        lines.push "#{bodyIndent}#{stripped}"

    # Save vars to state in finally block
    if hasVars
      lines.push "    finally"
      lines.push "      @_state[ctx._definer._id] ?= {}"
      lines.push "      Object.assign @_state[ctx._definer._id], {#{varsList}}"

    lines.join '\n'

  @_transformWithClodLang: (code) ->
    CoffeeScript = require 'coffeescript'
    preprocessed = ClodLang._preprocessObjectRefs code
    try
      ast = CoffeeScript.nodes preprocessed
      transforms = []
      ClodLang._collectTransforms ast, transforms
      ClodLang._applyTransforms preprocessed, transforms
    catch e
      # If transformation fails, return original code
      code

module.exports = Compiler
