class Compiler
  @compileMethod: (source, options = {}) ->
    CoffeeScript = require 'coffeescript'

    metadata = @parseMethodSource source

    fnSource = @_generateFunctionSource metadata
    jsCode = CoffeeScript.compile fnSource, {bare: true}
    fn = eval jsCode

    if options.returnMetadata
      {
        fn:                fn
        name:              metadata.name
        using:             metadata.using
        argsRaw:           metadata.argsRaw
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

        if trimmed is 'disallow overrides'
          result.disallowOverrides = true
          continue

      headerDone = true
      inBody = true
      result.body.push line

    result

  @_generateFunctionSource: (metadata) ->
    lines = []
    hasVars = metadata.vars?.length > 0

    if metadata.using.length > 0
      imports = metadata.using.join ', '
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

    for bodyLine in metadata.body
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

module.exports = Compiler
