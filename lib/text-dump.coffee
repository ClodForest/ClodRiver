CoreMethod       = require './core-method'
ExecutionContext = require './execution-context'

class TextDump
  constructor: ->
    @objects = {}

  @fromString: (source) ->
    dump = new TextDump()
    dump._parse source
    dump

  @fromCore: (core) ->
    dump = new TextDump()
    dump._captureFromCore core
    dump

  _parse: (source) ->
    lines = source.split '\n'
    @objects = {}
    @nameToId = {}
    @defaultParent = null
    @nextAutoId = 0
    @currentObject = null
    @currentMethod = null
    @inMethod = false
    @inData = false

    for line, lineNum in lines
      try
        @_parseLine line, lineNum + 1
      catch error
        throw new Error "Line #{lineNum + 1}: #{error.message}"

  _parseLine: (line, lineNum) ->
    trimmed = line.trim()
    return if trimmed is '' or trimmed[0] is '#'

    # object <numeric id>
    if match = trimmed.match /^object\s+(\d+)$/
      id = parseInt match[1]
      @nextAutoId = Math.max @nextAutoId, id + 1
      @currentObject = {
        id:       id
        parent:   @defaultParent
        name:     null
        methods:  {}
        data:     null
        lineNum:  lineNum
      }
      @objects[id] = @currentObject
      @inMethod = false
      @inData = false
      return

    # object $name - either switch to existing or create new
    if match = trimmed.match /^object\s+\$(\w+)$/
      name = match[1]
      if @nameToId[name]?
        # Switch to existing object
        id = @nameToId[name]
        @currentObject = @objects[id]
      else
        # Create new object with auto-ID
        id = @nextAutoId++
        @currentObject = {
          id:       id
          parent:   @defaultParent
          name:     name
          methods:  {}
          data:     null
          lineNum:  lineNum
        }
        @objects[id] = @currentObject
        @nameToId[name] = id
      @inMethod = false
      @inData = false
      return

    # parent $name
    if match = trimmed.match /^parent\s+\$(\w+)$/
      throw new Error "parent outside object definition" unless @currentObject?
      name = match[1]
      throw new Error "Unknown object $#{name}" unless @nameToId[name]?
      @currentObject.parent = @nameToId[name]
      return

    # parent <numeric id>
    if match = trimmed.match /^parent\s+(\d+)$/
      throw new Error "parent outside object definition" unless @currentObject?
      @currentObject.parent = parseInt match[1]
      return

    # default_parent $name
    if match = trimmed.match /^default_parent\s+\$(\w+)$/
      name = match[1]
      throw new Error "Unknown object $#{name}" unless @nameToId[name]?
      @defaultParent = @nameToId[name]
      return

    # name <identifier>
    if match = trimmed.match /^name\s+(\w+)$/
      throw new Error "name outside object definition" unless @currentObject?
      name = match[1]
      @currentObject.name = name
      @nameToId[name] = @currentObject.id
      return

    if match = trimmed.match /^method\s+(\w+)$/
      throw new Error "method outside object definition" unless @currentObject?
      @currentMethod = {
        name:              match[1]
        using:             []
        argsRaw:           null
        vars:              []
        body:              []
        disallowOverrides: false
        lineNum:           lineNum
      }
      @currentObject.methods[match[1]] = @currentMethod
      @inMethod = true
      @inData = false
      return

    if trimmed is 'data'
      throw new Error "data outside object definition" unless @currentObject?
      @currentObject.data = {
        body:    []
        lineNum: lineNum
      }
      @inData = true
      @inMethod = false
      return

    if @inMethod
      if match = trimmed.match /^using\s+(.+)$/
        imports = match[1].split(/\s*,\s*/)
        @currentMethod.using = imports
        return

      if match = trimmed.match /^args\s+(.+)$/
        @currentMethod.argsRaw = match[1]
        return

      if match = trimmed.match /^vars\s+(.+)$/
        @currentMethod.vars = match[1].split(/\s*,\s*/)
        return

      if trimmed is 'disallow overrides'
        @currentMethod.disallowOverrides = true
        return

      @currentMethod.body.push line
      return

    if @inData
      @currentObject.data.body.push line
      return

    throw new Error "Unexpected line: #{trimmed}"

  _captureFromCore: (core) ->
    CoreMethod = require './core-method'

    parentMap = {}
    for id, obj of core.objectIDs
      proto = Object.getPrototypeOf obj
      if proto and proto != Object.prototype
        parentMap[id] = proto._id

    nameMap = {}
    for name, obj of core.objectNames
      nameMap[obj._id] = name

    for id, obj of core.objectIDs
      objDef = {
        id:      parseInt(id)
        parent:  parentMap[id] ? null
        name:    nameMap[id] ? null
        methods: {}
        data:    null
      }

      for methodName, method of obj when method instanceof CoreMethod
        continue unless obj.hasOwnProperty methodName
        objDef.methods[methodName] = {
          name:              methodName
          source:            method.source
          disallowOverrides: method.disallowOverrides
        }

      hasState = false
      for namespaceId, data of obj._state
        if data? and Object.keys(data).length > 0
          hasState = true
          break

      if hasState
        serializedState = {}
        for namespaceId, data of obj._state
          continue unless data? and Object.keys(data).length > 0
          serializedState[namespaceId] = obj._serializeValue data

        objDef.data = {serialized: serializedState}

      @objects[id] = objDef

  apply: (core) ->
    CoffeeScript = require 'coffeescript'

    objRefs = {}

    sortedIds = Object.keys(@objects).map((id) -> parseInt id).sort (a, b) -> a - b

    # First pass: create all objects without parents
    for id in sortedIds
      objDef = @objects[id]
      newObj = core.create null, objDef.name
      objRefs[id] = newObj

    # Second pass: set up parent relationships (handles forward references)
    for id in sortedIds
      objDef = @objects[id]
      if objDef.parent?
        parent = objRefs[objDef.parent]
        child = objRefs[id]
        core.change_parent child, parent if parent?

    for id in sortedIds
      objDef = @objects[id]
      obj = objRefs[id]

      for methodName, methodDef of objDef.methods
        if methodDef.source?
          source = methodDef.source
        else
          source = @_generateMethodSource methodDef

        try
          jsCode = CoffeeScript.compile source, {bare: true}
          fn = eval jsCode
        catch error
          console.error "Failed to compile method #{id}.#{methodName}:", error.message
          continue

        flags = if methodDef.disallowOverrides then {disallowOverrides: true} else {}
        core.addMethod obj, methodName, fn, source, flags

    for id in sortedIds
      objDef = @objects[id]
      obj = objRefs[id]

      if objDef.data?
        if objDef.data.serialized?
          for namespaceId, data of objDef.data.serialized
            newObj = objRefs[parseInt(namespaceId)]
            if newObj?
              newNamespaceId = newObj._id
              obj._state[newNamespaceId] = obj._deserializeValue data, (refId) -> objRefs[refId]
            else
              obj._state[namespaceId] = obj._deserializeValue data, (refId) -> objRefs[refId]
        else if objDef.data.body?
          source = @_generateDataSource objDef.data, objRefs
          try
            CoffeeScript = require 'coffeescript'
            jsCode = CoffeeScript.compile source, {bare: true}
            fn = eval jsCode

            dummyMethod = {definer: obj, name: '_data_loader'}
            ctx = new ExecutionContext core, obj, dummyMethod
            stateData = fn ctx

            for namespaceKey, data of stateData
              # Handle $name keys by resolving to actual object
              if typeof namespaceKey is 'string' and namespaceKey[0] is '$'
                name = namespaceKey[1..]
                targetObj = core.toobj namespaceKey
                if targetObj?
                  obj._state[targetObj._id] = data
                else
                  console.error "Unknown object #{namespaceKey} in data block"
              else
                # Numeric ID - remap to new object ID
                newObj = objRefs[parseInt(namespaceKey)]
                if newObj?
                  obj._state[newObj._id] = data
                else
                  obj._state[namespaceKey] = data
          catch error
            console.error "Failed to apply data for object #{id}:", error.message

    objRefs

  toString: ->
    lines = []
    lines.push "# Textdump generated by ClodRiver"
    lines.push "# vim: ft=coffee"
    lines.push ""

    sortedIds = Object.keys(@objects).map((id) -> parseInt id).sort (a, b) -> a - b

    for id in sortedIds
      objDef = @objects[id]

      lines.push "object #{id}"

      if objDef.parent?
        lines.push "parent #{objDef.parent}"

      if objDef.name?
        lines.push "name #{objDef.name}"

      for methodName, methodDef of objDef.methods
        lines.push ""
        if methodDef.source?
          for line in methodDef.source.split('\n')
            lines.push line
        else
          lines.push "method #{methodName}"
          if methodDef.disallowOverrides
            lines.push "  disallow overrides"
          if methodDef.using?.length > 0
            lines.push "  using #{methodDef.using.join(', ')}"
          if methodDef.argsRaw?
            lines.push "  args #{methodDef.argsRaw}"
          lines.push ""
          for bodyLine in (methodDef.body or [])
            lines.push bodyLine

      if objDef.data?
        lines.push ""
        lines.push "data"
        if objDef.data.serialized?
          stateStr = @_objectToCoffeeScript objDef.data.serialized, 0
          for line in stateStr.split('\n')
            lines.push "  #{line}"
        else if objDef.data.body?
          for bodyLine in objDef.data.body
            lines.push bodyLine

      lines.push ""

    lines.join '\n'

  _generateMethodSource: (methodDef) ->
    lines = []
    hasVars = methodDef.vars?.length > 0

    if methodDef.using?.length > 0
      imports = methodDef.using.join ', '
      lines.push "(#{imports}) ->"
    else
      lines.push "() ->"

    lines.push "  (ctx, args) ->"

    if methodDef.argsRaw and methodDef.argsRaw.trim() isnt ''
      lines.push "    [#{methodDef.argsRaw}] = args"
      lines.push ""

    # Load vars from state
    if hasVars
      varsList = methodDef.vars.join ', '
      lines.push "    {#{varsList}} = @_state[ctx._definer._id] ? {}"
      lines.push ""
      lines.push "    try"

    # Determine base indent for body
    bodyIndent = if hasVars then "      " else "    "

    minIndent = Infinity
    for bodyLine in (methodDef.body or [])
      continue if bodyLine.trim() is ''
      indent = bodyLine.match(/^(\s*)/)[1].length
      minIndent = Math.min minIndent, indent

    minIndent = 0 if minIndent is Infinity

    for bodyLine in (methodDef.body or [])
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

  _generateDataSource: (dataDef, objRefs = {}) ->
    lines = []
    lines.push "(ctx) ->"

    minIndent = Infinity
    for bodyLine in dataDef.body
      continue if bodyLine.trim() is ''
      indent = bodyLine.match(/^(\s*)/)[1].length
      minIndent = Math.min minIndent, indent

    minIndent = 0 if minIndent is Infinity

    for bodyLine in dataDef.body
      if bodyLine.trim() is ''
        lines.push ''
      else
        stripped = bodyLine.substring minIndent
        lines.push "  #{stripped}"

    lines.join '\n'

  _objectToCoffeeScript: (obj, indent = 0) ->
    return 'null' unless obj?

    indentStr = '  '.repeat indent

    if Array.isArray obj
      return '[]' if obj.length is 0
      lines = ['[']
      for item, i in obj
        itemStr = @_objectToCoffeeScript item, indent + 1
        comma = if i < obj.length - 1 then ',' else ''
        lines.push "#{indentStr}  #{itemStr}#{comma}"
      lines.push "#{indentStr}]"
      return lines.join '\n'

    if typeof obj is 'object' and obj.$ref?
      return "{$ref: #{obj.$ref}}"

    if typeof obj is 'object'
      keys = Object.keys obj
      return '{}' if keys.length is 0

      lines = ['{']
      for key, i in keys
        value = obj[key]
        valueStr = @_objectToCoffeeScript value, indent + 1
        comma = if i < keys.length - 1 then ',' else ''

        if valueStr.includes '\n'
          lines.push "#{indentStr}  #{key}:"
          for line in valueStr.split('\n')
            lines.push "#{indentStr}    #{line}"
          lines.push "#{comma}" if comma
        else
          lines.push "#{indentStr}  #{key}: #{valueStr}#{comma}"

      lines.push "#{indentStr}}"
      return lines.join '\n'

    if typeof obj is 'string'
      escaped = obj.replace /\\/g, '\\\\'
                    .replace /'/g, "\\'"
                    .replace /\n/g, '\\n'
                    .replace /\r/g, '\\r'
                    .replace /\t/g, '\\t'
      return "'#{escaped}'"

    if typeof obj is 'number' or typeof obj is 'boolean'
      return String obj

    return 'undefined'

module.exports = TextDump
