# ClodMUD v2 syntax compiler
# Compiles declarative object definitions to Core API calls

class Compiler
  constructor: (@core) ->
    @objects = {}
    @currentObject = null
    @builtins = {}

  # Parse a v2 source file and return compiled objects
  compile: (source) ->
    lines = source.split '\n'
    @objects = {}
    @currentObject = null

    for line, lineNum in lines
      try
        @parseLine line, lineNum + 1
      catch error
        throw new Error "Line #{lineNum + 1}: #{error.message}"

    @objects

  parseLine: (line, lineNum) ->
    trimmed = line.trim()
    return if trimmed is '' or trimmed[0] is '#'

    # Match 'object N'
    if match = trimmed.match /^object\s+(\d+)$/
      id = parseInt match[1]
      @currentObject = {
        id:      id
        parent:  null
        name:    null
        methods: {}
      }
      @objects[id] = @currentObject
      return

    # Match 'parent N'
    if match = trimmed.match /^parent\s+(\d+)$/
      throw new Error "parent outside object definition" unless @currentObject?
      @currentObject.parent = parseInt match[1]
      return

    # Match 'name foo'
    if match = trimmed.match /^name\s+(\w+)$/
      throw new Error "name outside object definition" unless @currentObject?
      @currentObject.name = match[1]
      return

    # Match 'method methodName'
    if match = trimmed.match /^method\s+(\w+)$/
      throw new Error "method outside object definition" unless @currentObject?
      @currentMethod = {
        name:            match[1]
        using:           []
        args:            []
        body:            []
        disallowOverrides: false
      }
      @currentObject.methods[match[1]] = @currentMethod
      @inMethod = true
      return

    # Inside method definition
    if @inMethod
      # Match 'using foo, bar, baz'
      if match = trimmed.match /^using\s+(.+)$/
        imports = match[1].split(/\s*,\s*/)
        @currentMethod.using = imports
        return

      # Match 'args foo, bar = default'
      if match = trimmed.match /^args\s+(.+)$/
        @currentMethod.argsRaw = match[1]
        return

      # Match 'disallow overrides'
      if trimmed is 'disallow overrides'
        @currentMethod.disallowOverrides = true
        return

      # Body line - collect for now
      @currentMethod.body.push line
      return

    throw new Error "Unexpected line: #{trimmed}"

  # Generate executable code from parsed objects
  generate: ->
    code = []

    # Bootstrap: create all objects first
    for id, objDef of @objects
      parentRef = if objDef.parent? then "@objectIDs[#{objDef.parent}]" else 'null'
      code.push "obj#{id} = @create #{parentRef}"
      code.push "@objectIDs[#{id}] = obj#{id}"

      if objDef.name?
        code.push "@add_obj_name '#{objDef.name}', obj#{id}"
        code.push "$#{objDef.name} = obj#{id}"

    code.push ''

    # Add methods
    for id, objDef of @objects
      for methodName, methodDef of objDef.methods
        methodCode = @generateMethod objDef, methodName, methodDef
        code.push methodCode
        code.push ''

    code.join '\n'

  generateMethod: (objDef, methodName, methodDef) ->
    lines = []
    objVar = "obj#{objDef.id}"

    # Generate the method function
    lines.push "do ->"
    lines.push "  fn = "

    # Outer function takes imports
    if methodDef.using.length > 0
      imports = methodDef.using.join ', '
      lines.push "    (#{imports}) ->"
    else
      lines.push "    () ->"

    # Inner function takes ctx and args
    lines.push "      (ctx, args) ->"

    # Args destructuring (only if args specified)
    if methodDef.argsRaw and methodDef.argsRaw.trim() isnt ''
      lines.push "        [#{methodDef.argsRaw}] = args"
      lines.push ""

    # Detect minimum indentation in body
    minIndent = Infinity
    for bodyLine in methodDef.body
      continue if bodyLine.trim() is ''
      indent = bodyLine.match(/^(\s*)/)[1].length
      minIndent = Math.min minIndent, indent

    minIndent = 0 if minIndent is Infinity

    # Method body - strip source indent and add 6 spaces (nested in do block)
    for bodyLine in methodDef.body
      if bodyLine.trim() is ''
        lines.push ''
      else
        stripped = bodyLine.substring minIndent
        lines.push "        #{stripped}"

    lines.push ""

    # Generate source string for serialization
    lines.push "  source = '''"
    if methodDef.using.length > 0
      imports = methodDef.using.join ', '
      lines.push "  (#{imports}) ->"
    else
      lines.push "  () ->"
    lines.push "    (ctx, args) ->"
    if methodDef.argsRaw and methodDef.argsRaw.trim() isnt ''
      lines.push "      [#{methodDef.argsRaw}] = args"
    for bodyLine in methodDef.body
      if bodyLine.trim() is ''
        lines.push ''
      else
        stripped = bodyLine.substring minIndent
        lines.push "      #{stripped}"
    lines.push "  '''"
    lines.push ""

    # Call addMethod with flags if needed
    if methodDef.disallowOverrides
      lines.push "  @addMethod #{objVar}, '#{methodName}', fn, source, {disallowOverrides: true}"
    else
      lines.push "  @addMethod #{objVar}, '#{methodName}', fn, source"

    lines.join '\n'

module.exports = Compiler
