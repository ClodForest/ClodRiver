vm         = require 'vm'
sourceMaps = require './source-maps'

class Compiler
  @compileMethod: (source, options = {}) ->
    CoffeeScript = require 'coffeescript'

    metadata = @parseMethodSource source

    # Transform method calls in body if v2 mode
    if options.v2
      metadata.body = metadata.body.map (line) => @_transformMethodCalls line

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

  @_generateFunctionSource: (metadata, options = {}) ->
    lines = []
    hasVars = metadata.vars?.length > 0

    # In v2 mode, auto-add _dispatch to imports
    imports = if options.v2
      ['_dispatch', metadata.using...].join ', '
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

  @_transformMethodCalls: (line) ->
    # Transform obj.method(args) to _dispatch(obj, 'method', args)
    # Handles: foo.bar(x), @foo(x), @.foo(x), result.method()
    # Does NOT transform: property access without call
    # Uses balanced paren matching for nested calls

    result = line
    changed = true

    # Keep transforming until no more changes
    while changed
      changed = false

      # Pattern 1a: @method( - @ shorthand with explicit parens
      i = 0
      while i < result.length
        if result[i] is '@' and result[i + 1]?.match /\w/
          methodMatch = result.substring(i + 1).match /^(\w+)\(/
          if methodMatch and methodMatch[1] isnt '_dispatch'
            method = methodMatch[1]
            openParen = i + 1 + methodMatch[0].length - 1
            closeParen = @_findMatchingParen result, openParen
            if closeParen > openParen
              args = result.substring(openParen + 1, closeParen).trim()
              replacement = if args
                "_dispatch(@, '#{method}', #{args})"
              else
                "_dispatch(@, '#{method}')"
              result = result.substring(0, i) + replacement + result.substring(closeParen + 1)
              changed = true
              break
        i++

      continue if changed

      # Pattern 1b: @method arg - CoffeeScript implicit call (no parens, space before args)
      # Only transform if what follows is clearly an argument, not an operator
      i = 0
      while i < result.length
        if result[i] is '@' and result[i + 1]?.match /\w/
          methodMatch = result.substring(i + 1).match /^(\w+)( +)/
          if methodMatch and methodMatch[1] isnt '_dispatch'
            method = methodMatch[1]
            argsStart = i + 1 + methodMatch[0].length
            rest = result.substring(argsStart)
            # Skip if next char is an operator (property access, not call)
            if rest.length > 0 and not rest.match /^[\s]*$/ and not rest.match /^[-+*\/%=<>&|^!?:,\])]/
              args = @_findImplicitArgs rest
              if args.length > 0
                argsEnd = argsStart + args.length
                replacement = "_dispatch(@, '#{method}', #{args})"
                result = result.substring(0, i) + replacement + result.substring(argsEnd)
                changed = true
                break
        i++

      continue if changed

      # Pattern 2a: obj.method( where obj is word, @word, ), or ]
      i = 0
      while i < result.length
        if result[i] is '.'
          objEnd = i
          objStart = @_findObjStart result, i
          if objStart < i
            methodMatch = result.substring(i + 1).match /^(\w+)\(/
            if methodMatch and methodMatch[1] isnt '_dispatch'
              obj = result.substring(objStart, objEnd)
              method = methodMatch[1]
              openParen = i + 1 + methodMatch[0].length - 1
              closeParen = @_findMatchingParen result, openParen
              if closeParen > openParen
                args = result.substring(openParen + 1, closeParen).trim()
                replacement = if args
                  "_dispatch(#{obj}, '#{method}', #{args})"
                else
                  "_dispatch(#{obj}, '#{method}')"
                result = result.substring(0, objStart) + replacement + result.substring(closeParen + 1)
                changed = true
                break
        i++

      continue if changed

      # Pattern 2b: $name.method arg - implicit call on named objects only
      # Only transform $name objects to avoid breaking JS objects like Buffer, Array, etc.
      i = 0
      while i < result.length
        if result[i] is '.' and i > 0 and result[i - 1]?.match /\w/
          # Check if object is $name
          objMatch = result.substring(0, i).match /(\$\w+)$/
          if objMatch
            obj = objMatch[1]
            methodMatch = result.substring(i + 1).match /^(\w+)( +)/
            if methodMatch and methodMatch[1] isnt '_dispatch'
              method = methodMatch[1]
              argsStart = i + 1 + methodMatch[0].length
              rest = result.substring(argsStart)
              # Skip if next char is an operator (property access, not call)
              if rest.length > 0 and not rest.match /^[\s]*$/ and not rest.match /^[-+*\/%=<>&|^!?:,\])]/
                args = @_findImplicitArgs rest
                if args.length > 0
                  argsEnd = argsStart + args.length
                  objStart = i - obj.length
                  replacement = "_dispatch(#{obj}, '#{method}', #{args})"
                  result = result.substring(0, objStart) + replacement + result.substring(argsEnd)
                  changed = true
                  break
        i++

    result

  @_findImplicitArgs: (str) ->
    # Find the extent of implicit call arguments
    # Returns the substring that constitutes the arguments
    # Handles balanced parens/brackets, stops at unbalanced closers or keywords
    depth = {paren: 0, bracket: 0, brace: 0}
    i = 0
    while i < str.length
      char = str[i]
      switch char
        when '(' then depth.paren++
        when ')' then depth.paren--
        when '[' then depth.bracket++
        when ']' then depth.bracket--
        when '{' then depth.brace++
        when '}' then depth.brace--

      # Stop if we hit an unbalanced closer
      if depth.paren < 0 or depth.bracket < 0 or depth.brace < 0
        break

      # Check for CoffeeScript keywords that end implicit args
      rest = str.substring(i)
      if rest.match /^(\s+then\s|\s+if\s|\s+unless\s|\s+else\s|\s+for\s|\s+while\s)/
        break

      i++

    str.substring(0, i).trimEnd()

  @_findMatchingParen: (str, openPos) ->
    return -1 unless str[openPos] is '('
    depth = 1
    i = openPos + 1
    while i < str.length and depth > 0
      if str[i] is '('
        depth++
      else if str[i] is ')'
        depth--
      i++
    if depth is 0 then i - 1 else -1

  @_findObjStart: (str, dotPos) ->
    # Find start of object expression before the dot
    # Handles: word, @word, ), ]
    i = dotPos - 1

    # Skip whitespace before dot
    while i >= 0 and str[i] is ' '
      i--

    return dotPos if i < 0

    if str[i] is ')'
      # Find matching open paren
      depth = 1
      i--
      while i >= 0 and depth > 0
        if str[i] is ')'
          depth++
        else if str[i] is '('
          depth--
        i--
      i++ if depth is 0
      # Continue to find what precedes the paren
      j = i - 1
      while j >= 0 and str[j] is ' '
        j--
      if j >= 0 and str[j].match /\w/
        # There's a word before the paren (function call)
        while j >= 0 and str[j].match /\w/
          j--
        return j + 1
      else if j >= 0 and str[j] is '@'
        return j
      return i

    if str[i] is ']'
      # Find matching open bracket
      depth = 1
      i--
      while i >= 0 and depth > 0
        if str[i] is ']'
          depth++
        else if str[i] is '['
          depth--
        i--
      return i + 1 if depth is 0
      return dotPos

    if str[i] is '@'
      return i

    if str[i].match /\w/
      # Word - scan back to start
      while i > 0 and str[i - 1].match /\w/
        i--
      # Check for @ or $ prefix
      if i > 0 and str[i - 1] in ['@', '$']
        return i - 1
      return i

    dotPos

module.exports = Compiler
