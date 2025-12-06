# ClodLang - CoffeeScript with ClodMUD extensions
#
# Transforms ClodMUD syntax to standard CoffeeScript:
#   $name       → toobj('$name')       - named object references
#   ~id         → toobj('#id')         - object ID references (~ avoids # comment conflict)
#   obj.method(...) → _dispatch(obj, 'method', ...) - method calls
#
# Uses CoffeeScript's AST for robust transformation

CoffeeScript = require 'coffeescript'

class ClodLang
  # Transform ClodMUD code to executable CoffeeScript
  @transform: (code, options = {}) ->
    # Pre-process #id syntax (CoffeeScript treats # as comment)
    preprocessed = @_preprocessObjectRefs code

    # Parse to AST
    ast = CoffeeScript.nodes preprocessed

    # Walk and transform the AST
    @_transformNode ast

    # Compile back to JavaScript
    ast.compile {bare: true}

  # Pre-process ~id references before parsing
  # Replace ~123 with __clod_ref_123__ (~ is not valid CoffeeScript syntax)
  @_preprocessObjectRefs: (code) ->
    code.replace /~(\d+)/g, '__clod_ref_$1__'

  # Recursively transform AST nodes
  @_transformNode: (node) ->
    return unless node?

    # Get node constructor name
    nodeType = node.constructor.name

    switch nodeType
      when 'Block'
        for expr in node.expressions
          @_transformNode expr

      when 'Value'
        @_transformValue node

      when 'Call'
        @_transformCall node

      when 'Assign'
        @_transformNode node.value
        @_transformNode node.variable

      when 'Code'  # Function definition
        @_transformNode node.body

      when 'If'
        @_transformNode node.condition
        @_transformNode node.body
        @_transformNode node.elseBody

      when 'For'
        @_transformNode node.source
        @_transformNode node.body

      when 'While'
        @_transformNode node.condition
        @_transformNode node.body

      when 'Switch'
        @_transformNode node.subject
        for switchCase in node.cases or []
          @_transformNode switchCase.conditions
          @_transformNode switchCase.block
        @_transformNode node.otherwise

      when 'Try'
        @_transformNode node.attempt
        @_transformNode node.recovery
        @_transformNode node.ensure

      when 'Op'
        @_transformNode node.first
        @_transformNode node.second

      when 'Parens'
        @_transformNode node.body

      when 'Arr'
        for obj in node.objects or []
          @_transformNode obj

      when 'Obj'
        for prop in node.properties or []
          @_transformNode prop.value if prop.value?

      when 'Return'
        @_transformNode node.expression

      when 'Throw'
        @_transformNode node.expression

      when 'Splat'
        @_transformNode node.name

      when 'Expansion'
        null  # Nothing to transform

      when 'Root'
        @_transformNode node.body

      else
        # For unknown node types, try to traverse common properties
        @_transformNode node.body if node.body?
        @_transformNode node.expression if node.expression?
        if node.args?
          for arg in node.args
            @_transformNode arg

  # Transform a Value node (handles $name and __clod_ref_id__)
  @_transformValue: (node) ->
    return unless node?.base?

    # First, recursively transform any nested nodes
    if node.base.constructor.name is 'Call'
      @_transformCall node.base

    if node.base.constructor.name is 'Parens'
      @_transformNode node.base.body

    # Transform $name identifiers to toobj('$name') calls
    if node.base.constructor.name is 'IdentifierLiteral'
      name = node.base.value
      if name.startsWith '$'
        @_replaceWithToobjCall node, "'#{name}'"
      else if (name.startsWith '__clod_ref_') and (name.endsWith '__')
        # Extract ID from __clod_ref_123__
        id = name.slice(11, -2)
        @_replaceWithToobjCall node, "'##{id}'"

    # Transform properties
    for prop in node.properties or []
      if prop.constructor.name is 'Index'
        @_transformNode prop.index

  # Transform a Call node to _dispatch
  @_transformCall: (node) ->
    return unless node?

    # First transform arguments recursively
    for arg in node.args or []
      @_transformNode arg

    # Transform the thing being called
    @_transformNode node.variable

    # Check if this is a method call on an object (not a plain function call)
    variable = node.variable
    return unless variable?.constructor.name is 'Value'
    return unless variable.properties?.length > 0

    # Get the last property (the method being called)
    lastProp = variable.properties[variable.properties.length - 1]
    return unless lastProp?.constructor.name is 'Access'
    return unless lastProp.name?.constructor.name is 'PropertyName'

    methodName = lastProp.name.value

    # Don't transform _dispatch calls (avoid infinite loop)
    return if methodName is '_dispatch'

    # Build the object part (everything except the last property)
    # We need to extract the base object and all properties except the last
    @_convertToDispatch node, methodName

  # Convert a Call node to use _dispatch
  @_convertToDispatch: (callNode, methodName) ->
    variable = callNode.variable

    # Create the object expression (base + all props except last)
    objBase = variable.base
    objProps = variable.properties.slice(0, -1)

    # Build source for _dispatch call
    # We'll rebuild this as source and re-parse
    # This is simpler than constructing AST nodes manually

    # Compile the object part
    objValue = new CoffeeScript.nodes('x').body.expressions[0]
    objValue.base = objBase
    objValue.properties = objProps

    # We need to get the source representation
    # For now, let's mark the node for post-processing
    callNode._clodDispatch = {
      methodName: methodName
      objBase: objBase
      objProps: objProps
      args: callNode.args
    }

  # Replace a Value node's base with a toobj() call
  @_replaceWithToobjCall: (valueNode, refArg) ->
    # Create a new Call node for toobj(refArg)
    # Mark for post-processing since direct node construction is complex
    valueNode._clodToobj = refArg

  # Compile ClodLang to JavaScript
  @compile: (code, options = {}) ->
    # Pre-process ~id syntax
    preprocessed = @_preprocessObjectRefs code

    # Parse to AST
    ast = CoffeeScript.nodes preprocessed

    # Collect transformations
    transforms = []
    @_collectTransforms ast, transforms

    # Apply transforms
    transformed = @_applyTransforms preprocessed, transforms

    # Compile the transformed CoffeeScript to JavaScript
    CoffeeScript.compile transformed, {bare: options.bare ? true}

  @_collectTransforms: (node, transforms) ->
    return unless node?

    nodeType = node.constructor.name

    switch nodeType
      when 'Root'
        @_collectTransforms node.body, transforms

      when 'Block'
        for expr in node.expressions
          @_collectTransforms expr, transforms

      when 'Value'
        @_collectValueTransforms node, transforms
        for prop in node.properties or []
          @_collectTransforms prop, transforms

      when 'Call'
        @_collectCallTransforms node, transforms

      when 'Assign'
        @_collectTransforms node.value, transforms
        @_collectTransforms node.variable, transforms

      when 'Code'
        @_collectTransforms node.body, transforms

      when 'If'
        @_collectTransforms node.condition, transforms
        @_collectTransforms node.body, transforms
        @_collectTransforms node.elseBody, transforms

      when 'For'
        @_collectTransforms node.source, transforms
        @_collectTransforms node.body, transforms
        @_collectTransforms node.guard, transforms

      when 'While'
        @_collectTransforms node.condition, transforms
        @_collectTransforms node.body, transforms

      when 'Switch'
        @_collectTransforms node.subject, transforms
        for switchCase in node.cases or []
          @_collectTransforms switchCase.conditions, transforms
          @_collectTransforms switchCase.block, transforms
        @_collectTransforms node.otherwise, transforms

      when 'Try'
        @_collectTransforms node.attempt, transforms
        @_collectTransforms node.recovery, transforms
        @_collectTransforms node.ensure, transforms

      when 'Op'
        @_collectTransforms node.first, transforms
        @_collectTransforms node.second, transforms

      when 'Parens'
        @_collectTransforms node.body, transforms

      when 'Arr'
        for obj in node.objects or []
          @_collectTransforms obj, transforms

      when 'Obj'
        for prop in node.properties or []
          @_collectTransforms prop.value, transforms if prop.value?

      when 'Return'
        @_collectTransforms node.expression, transforms

      when 'Throw'
        @_collectTransforms node.expression, transforms

      when 'Index'
        @_collectTransforms node.index, transforms

      when 'Splat'
        @_collectTransforms node.name, transforms

      else
        # Generic traversal for unknown types
        @_collectTransforms node.body, transforms if node.body?
        @_collectTransforms node.expression, transforms if node.expression?
        if node.args?
          for arg in node.args
            @_collectTransforms arg, transforms

  @_collectValueTransforms: (node, transforms) ->
    return unless node?.base?

    # Handle nested calls/parens/arrays/objects
    if node.base.constructor.name is 'Call'
      @_collectCallTransforms node.base, transforms
    if node.base.constructor.name is 'Parens'
      @_collectTransforms node.base.body, transforms
    if node.base.constructor.name is 'Arr'
      for obj in node.base.objects or []
        @_collectTransforms obj, transforms
    if node.base.constructor.name is 'Obj'
      for prop in node.base.properties or []
        @_collectTransforms prop.value, transforms if prop.value?

    # Transform $name to toobj('$name')
    if node.base.constructor.name is 'IdentifierLiteral'
      name = node.base.value
      if name.startsWith '$'
        loc = node.base.locationData
        transforms.push {
          start: loc.range[0]
          end: loc.range[1]
          replacement: "toobj('#{name}')"
        }
      else if (name.startsWith '__clod_ref_') and (name.endsWith '__')
        id = name.slice(11, -2)
        loc = node.base.locationData
        transforms.push {
          start: loc.range[0]
          end: loc.range[1]
          replacement: "toobj('##{id}')"
        }

  @_collectCallTransforms: (node, transforms) ->
    return unless node?

    # First collect transforms in arguments
    for arg in node.args or []
      @_collectTransforms arg, transforms

    # Collect transforms in the callee
    @_collectTransforms node.variable, transforms

    # Check if this is a method call
    variable = node.variable
    return unless variable?.constructor.name is 'Value'
    return unless variable.properties?.length > 0

    lastProp = variable.properties[variable.properties.length - 1]
    return unless lastProp?.constructor.name is 'Access'
    return unless lastProp.name?.constructor.name is 'PropertyName'

    methodName = lastProp.name.value

    # Don't transform _dispatch or toobj calls
    return if methodName in ['_dispatch', 'toobj']

    # Get the location of the entire call
    callLoc = node.locationData

    # Get the location of the object part (base + props except last)
    objStart = variable.base.locationData.range[0]
    # End at the start of the last property (includes everything before the dot)
    objEnd = lastProp.locationData.range[0]

    # Build args string from args
    argsLoc = null
    if node.args?.length > 0 and node.args[0].locationData?
      argsStart = node.args[0].locationData.range[0]
      argsEnd = node.args[node.args.length - 1].locationData.range[1]
      argsLoc = {start: argsStart, end: argsEnd}

    transforms.push {
      type: 'call'
      start: callLoc.range[0]
      end: callLoc.range[1]
      objStart: objStart
      objEnd: objEnd
      methodName: methodName
      argsLoc: argsLoc
    }

  # Apply collected transforms
  @_applyTransforms: (code, transforms) ->
    # Filter out transforms that are inside another call's range
    # This handles nested calls - only the outermost call is processed
    callRanges = transforms
      .filter((t) -> t.type is 'call')
      .map (t) -> [t.start, t.end]

    filtered = transforms.filter (t) ->
      # Check if this transform is strictly inside any call range
      for [start, end] in callRanges
        # Strictly inside means not the same range
        if t.start >= start and t.end <= end and not (t.start is start and t.end is end)
          return false
      return true

    # Sort by position (reverse order) so we process from end to start
    filtered.sort (a, b) -> b.start - a.start

    result = code
    for t in filtered
      if t.type is 'call'
        # Extract and transform object part
        objPart = @_transformObjectPart code.substring(t.objStart, t.objEnd)
        # Extract and recursively transform args (handles nested calls)
        argsPart = if t.argsLoc?
          argsCode = code.substring(t.argsLoc.start, t.argsLoc.end)
          @_transformCode argsCode
        else
          ''

        # Build _dispatch call
        if argsPart
          replacement = "_dispatch(#{objPart}, '#{t.methodName}', #{argsPart})"
        else
          replacement = "_dispatch(#{objPart}, '#{t.methodName}')"

        before = result.substring 0, t.start
        after = result.substring t.end
        result = before + replacement + after
      else
        # Simple replacement
        before = result.substring 0, t.start
        after = result.substring t.end
        result = before + t.replacement + after

    result

  # Recursively transform a code fragment (for nested expressions in args)
  @_transformCode: (code) ->
    preprocessed = @_preprocessObjectRefs code
    try
      ast = CoffeeScript.nodes preprocessed
      transforms = []
      @_collectTransforms ast, transforms
      @_applyTransforms preprocessed, transforms
    catch
      # If parsing fails (e.g., comma-separated args), try wrapping in array
      try
        wrapped = "[#{preprocessed}]"
        ast = CoffeeScript.nodes wrapped
        transforms = []
        @_collectTransforms ast, transforms
        # Adjust positions to account for leading bracket
        for t in transforms
          t.start -= 1
          t.end -= 1
          if t.objStart? then t.objStart -= 1
          if t.objEnd? then t.objEnd -= 1
          if t.argsLoc?
            t.argsLoc.start -= 1
            t.argsLoc.end -= 1
        @_applyTransforms preprocessed, transforms
      catch
        # If still fails, just apply simple transforms
        @_transformObjectPart preprocessed

  # Transform $name and __clod_ref_N__ patterns within a code fragment
  @_transformObjectPart: (code) ->
    code
      .replace /\$([a-zA-Z_][a-zA-Z0-9_]*)/g, (_, name) -> "toobj('$#{name}')"
      .replace /__clod_ref_(\d+)__/g, (_, id) -> "toobj('##{id}')"

module.exports = ClodLang
