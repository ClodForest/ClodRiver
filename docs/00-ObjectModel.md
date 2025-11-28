# ClodRiver Object Model

**Version:** 4.0
**Date:** November 2025
**Status:** Current Implementation

---

## Core Principles

1. **Every object is equivalent** - No distinction between "class" and "instance"
2. **Any object can be a parent** - True ColdMUD semantics
3. **State is never inherited** - Only methods are inherited via prototype chain
4. **State is class-namespaced** - Each definer gets its own namespace in `_state`
5. **Methods are CoreMethod instances** - Encapsulate function, metadata, and behavior
6. **Methods declare their imports** - Nested function pattern for clean code
7. **ctx is the execution environment** - Manages call stack, provides builtins

---

## CoreObject Class

Minimal object class with just identity and state:

```coffee
class CoreObject
  constructor: (@_id, parent = null) ->
    @_state = {}
    Object.setPrototypeOf(this, parent) if parent?
```

### Object Structure

Every object has:
- `_id` - Unique numeric identifier
- `_state` - Map from definer ID to properties
- Prototype chain via `Object.setPrototypeOf`

Note: Object names are managed by `Core.objectNames`, not stored on objects.

### State Storage

State is namespaced by definer ID to prevent interference:

```coffee
# $sword has _id = 41
$sword._state = {
  1:  {name: '$sword'}    # $root's namespace
  41: {damage: 'd6'}      # $sword's namespace
}

# $excalibur has _id = 42, parent = $sword
$excalibur._state = {
  1:  {name: '$excalibur'}  # $root's namespace
  41: {damage: 'd6'}        # $sword's namespace (for inherited methods)
  42: {magic: '+10'}        # $excalibur's namespace
}
```

---

## CoreMethod Class

Methods are CoreMethod instances that encapsulate function and metadata:

```coffee
class CoreMethod
  constructor: (@name, @fn, @definer, @source = null, @flags = {}) ->
    @disallowOverrides = @flags.disallowOverrides ? false
    @_importNames = null  # Cached parameter names

  invoke: (core, obj, ctx, args) ->
    # Extract import names (cached)
    @_importNames ?= @_extractImportNames()

    # Resolve imports to actual values
    resolvedImports = @_resolveImports core, ctx

    # Call outer function with imports to get inner function
    innerFn = @fn.apply obj, resolvedImports

    # Call inner function with ctx and args
    innerFn.call obj, ctx, args

  canBeOverriddenBy: (newDefiner) ->
    not @disallowOverrides

  serialize: ->
    name:              @name
    definer:           @definer._id
    source:            @source
    disallowOverrides: @disallowOverrides
```

### CoreMethod Properties

- `name` - Method name
- `fn` - The actual function (outer wrapper)
- `definer` - Object that defined this method
- `source` - Original source code (for serialization)
- `disallowOverrides` - Flag to prevent overriding
- `_importNames` - Cached list of import parameter names

---

## Core API

The Core class manages the object system:

```coffee
class Core
  constructor: ->
    @objectIDs   = {}    # id   -> object
    @objectNames = {}    # name -> object
    @nextId      = 0
    @bifs        = new BIFs this

  create: (parent = null, name) ->
    id = @nextId++
    obj = new CoreObject(id, parent)
    @objectIDs[id] = obj
    @add_obj_name(name, obj) if name
    obj

  destroy: (ref) ->
    obj = @toobj ref
    return unless obj
    delete @objectIDs[id] for id, o of @objectIDs when o is obj
    delete @objectNames[name] for name, o of @objectNames when o is obj

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

    if ref?.$ref
      return @objectIDs[ref.$ref] or null

    null

  addMethod: (obj, methodName, fn, source = null, flags = {}) ->
    obj[methodName] = new CoreMethod methodName, fn, obj, source, flags

  delMethod: (obj, methodName) ->
    delete obj[methodName]

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
```

### toobj()

Resolves references to objects in multiple formats:

```coffee
core.toobj('$sys')    # Dollar-sign name
core.toobj('#42')     # Hash-number format
core.toobj(42)        # Numeric ID
core.toobj({$ref: 42})  # Serialized reference
```

### call() vs callIfExists()

- `call()` - Throws `MethodNotFoundError` if method doesn't exist
- `callIfExists()` - Logs and returns null if method doesn't exist (used for event handlers)

---

## Execution Context (ctx)

The `ctx` object is the execution environment passed to all methods.

### Structure

```coffee
class ExecutionContext
  constructor: (@core, @obj, @method, @parent = null) ->
    @_definer = @method.definer
    @stack    = if @parent then [@parent.stack..., @parent.obj] else []

  # State access (fat arrow for binding)
  cget: (key) =>
    @obj._state[@_definer._id]?[key]

  cset: (data) =>
    @obj._state[@_definer._id] ?= {}
    Object.assign @obj._state[@_definer._id], data
    @obj

  # ColdMUD builtins (fat arrow for binding)
  cthis:   => @obj
  definer: => @_definer
  caller:  => @parent?.obj or null
  sender:  => @parent?._definer or null

  # Method dispatch
  send: (target, methodName, args...) =>
    method = @core._findMethod target, methodName
    throw new MethodNotFoundError(target._id, methodName) unless method?

    childCtx = new ExecutionContext @core, target, method, this
    method.invoke @core, target, childCtx, args

  pass: (args...) =>
    parent = Object.getPrototypeOf @_definer
    throw new NoParentMethodError(@obj._id, @method.name) if parent is Object.prototype

    parentMethod = @core._findMethod parent, @method.name
    throw new NoParentMethodError(@obj._id, @method.name) unless parentMethod?

    parentCtx = new ExecutionContext @core, @obj, parentMethod, this
    parentMethod.invoke @core, @obj, parentCtx, args
```

### Builtins

Available builtins that methods can import:

- **cget(key)** - Read property from definer's namespace on current object
- **cset(data)** - Write properties to definer's namespace on current object
- **cthis()** - Current object being called
- **definer()** - Object that defined this method
- **caller()** - Previous object in call stack
- **sender()** - Previous definer in call stack
- **send(target, methodName, args...)** - Invoke method on another object
- **pass(args...)** - Call parent's implementation of current method

### Importing Objects by Name

Methods can import objects from `core.objectNames` by listing `$name` in their import list:

```coffee
core.addMethod obj, 'test', ($sys, $root) ->
  (ctx, args) ->
    # $sys and $root are the actual objects
```

### State Access (cget/cset)

The `cget` and `cset` builtins access the definer's namespace on the **current object**:

```coffee
# When $sword method calls cget/cset on $excalibur
cget = (key) ->
  $excalibur._state[$sword._id]?[key]

cset = (data) ->
  $excalibur._state[$sword._id] ?= {}
  Object.assign($excalibur._state[$sword._id], data)
  $excalibur
```

This ensures methods always access their own namespace, regardless of which object they're called on.

---

## Method Definition Pattern

Methods use nested functions to declare which builtins they need:

```coffee
core.addMethod obj, 'methodName',
  # Outer function: declares imports
  (import1, import2, import3) ->

    # Inner function: the actual method
    (ctx, args) ->
      # Method body uses the imports
      import1('foo')
      import2({bar: 'baz'})
```

### Examples

**Simple getter:**

```coffee
core.addMethod $thing, 'description', (cget) ->
  (ctx, args) ->
    cget 'description'
```

**Method with object interaction:**

```coffee
core.addMethod $sword, 'swing', (cget, send) ->
  (ctx, args) ->
    [target] = args
    damage = cget 'damage'
    send target, 'take_damage', damage
```

**Method with permission checking:**

```coffee
core.addMethod $thing, 'set_name', ($owners, sender, cset) ->
  (ctx, args) ->
    [name] = args
    if sender() not in $owners.of(ctx.cthis())
      throw new PermissionError()

    cset {name}
```

**Method with no imports:**

```coffee
core.addMethod $utils, 'add', ->
  (ctx, args) ->
    [x, y] = args
    x + y
```

### Import Resolution

The CoreMethod class resolves imports automatically:

1. **BIFs** - `create`, `add_method`, `toint`, etc. from `core.bifs`
2. **$name** - Objects from `core.objectNames`
3. **ctx methods** - `cget`, `cset`, `cthis`, `definer`, `caller`, `sender`, `send`, `pass`
4. **Unknown** - Passed as `null`

---

## Method Dispatch

### Core.call() - Entry Point

Called by server for I/O events, timers, startup:

```coffee
# Server invokes startup
core.call($sys, 'startup', [])
```

Creates initial ctx with empty call stack.

### ctx.send() - Object-to-Object Calls

Methods call other methods using `send()`:

```coffee
# In a method body
send $root, 'allChildren'
send target, 'take_damage', amount
```

The `send` builtin:
- Finds CoreMethod on target object's prototype chain
- Updates call stack (`caller`, `sender`)
- Creates new ctx with updated definer
- Invokes method via `CoreMethod.invoke()`

### Call Stack Example

```
Server:              core.call($sys, 'startup', [])
  ↓ creates ctx with stack: []

$sys.startup:        send $root, 'allChildren'
  ↓ ctx.send updates stack: [$sys]

$root.allChildren:   send child, 'notify_startup'
  ↓ ctx.send updates stack: [$sys, $root]

$child.notify_startup: ...
  ↓ stack: [$sys, $root, $child]
```

At each level:
- `cthis()` returns current object
- `definer()` returns object that defined current method
- `caller()` returns previous object in stack
- `sender()` returns previous definer in stack

---

## Module Pattern

Core modules export a function that receives Core and sets up the object:

```coffee
# sword.coffee
module.exports = (core) ->
  $thing = core.toobj '$thing'

  $sword = core.create($thing)
  core.add_obj_name 'sword', $sword

  $sword._state = {
    1:  {name: 'sword'}
    41: {damage: 'd6', weight: 5}
  }

  core.addMethod $sword, 'swing', (cget, send) ->
    (ctx, args) ->
      [target] = args
      damage = cget 'damage'
      send target, 'take_damage', damage

  $sword
```

### Bootstrap Sequence

```coffee
# Create Core
core = new Core()

# $sys and $root created automatically by Core constructor
# $sys has _id = 0
# $root has _id = 1
# Object.setPrototypeOf $sys, $root

$sys = core.toobj '$sys'
$root = core.toobj '$root'

# Load core modules
require('./core/root')(core)
require('./core/sys')(core)

# Load additional objects
for file in findCoreFiles('./core/lib')
  core.loadFromModule file

# Start system
core.call $sys, 'startup', []
```

---

## Object References in State

Object references are serialized with special handling to avoid conflicts with user data.

### Serialization

```coffee
_serializeValue: (value) ->
  if value instanceof CoreObject
    {$ref: value._id}
  else if Array.isArray(value)
    (@_serializeValue(item) for item in value)
  else if value?.constructor == Object
    if value.$ref? and not (value instanceof CoreObject)
      {$ref: false, value: value}
    else
      result = {}
      for key, val of value
        result[key] = @_serializeValue(val)
      result
  else
    value
```

### Deserialization

```coffee
_deserializeValue: (value, resolver) ->
  if value?.$ref?
    if value.$ref == false
      value.value
    else
      resolver(value.$ref)
  else if Array.isArray(value)
    (@_deserializeValue(item, resolver) for item in value)
  else if value?.constructor == Object
    result = {}
    for key, val of value
      result[key] = @_deserializeValue(val, resolver)
    result
  else
    value
```

### Cases Handled

```coffee
# Case 1: Actual object reference
obj42 → {$ref: 42}

# Case 2: User data with $ref key
{$ref: "user data"} → {$ref: false, value: {$ref: "user data"}}

# Case 3: Arrays
[obj1, obj2] → [{$ref: 1}, {$ref: 2}]

# Case 4: Nested objects
{weapon: obj42, stats: {str: 10}} → {weapon: {$ref: 42}, stats: {str: 10}}
```

---

## Method Inheritance

Methods are inherited via JavaScript's prototype chain:

```coffee
$thing = core.create()
$thing._state[$thing._id] = {description: 'nothing special'}
core.addMethod $thing, 'look', (cget) ->
  (ctx, args) ->
    (cget 'description') ? 'indescribable'

$sword = core.create($thing)

core.call $sword, 'look', []  # Uses $thing's look method
# => 'indescribable'
# uses default because $sword._state[$thing._id].description is undefined
```

### Override

Child objects can define their own version:

```coffee
core.addMethod $sword, 'look', (cget) ->
  (ctx, args) ->
    "#{cget 'name'} - a weapon"

core.call $sword, 'look', []  # Uses $sword's look method
```

### Pass to Parent

Use `pass()` to call parent's implementation:

```coffee
core.addMethod $sword, 'look', (cget, pass) ->
  (ctx, args) ->
    parent_desc = pass()
    "#{parent_desc} with a blade"
```

---

## Reserved Names

Objects MUST NOT define methods or properties with these names:

- `_id` - Object ID
- `_state` - State storage

CoreObject internal methods are also reserved:
- `serialize`, `deserialize`
- `_serializeValue`, `_deserializeValue`, `_isCoreObject`

Method names can be anything else, including importable names and ColdMUD
built-in names.

---

## Freeze and Thaw

Serialization of the entire object system:

```coffee
# Freeze
frozen = core.freeze()
# Returns: {nextId, parentMap, nameMap, objects, methods}

# Thaw
newCore = new Core()
newCore.thaw frozen, {
  compileFn: (source) ->
    # Compile CoffeeScript source to function
    jsCode = CoffeeScript.compile source, {bare: true}
    innerFn = eval(jsCode)
    -> innerFn  # Wrap for nested pattern
}
```

Methods are serialized with their source code and reconstructed during thaw using the provided `compileFn`.

---

## Summary

The ClodRiver object model:

- ✅ Every object is equivalent - any can be a parent
- ✅ CoreMethod instances - encapsulate function and metadata
- ✅ State is class-namespaced - no inheritance conflicts
- ✅ Methods are inherited - via prototype chain
- ✅ Clean execution context - ctx manages everything
- ✅ Declarative imports - methods declare what they need
- ✅ ColdMUD semantics - definer/caller/sender tracking
- ✅ Deep serialization - handles nested objects and arrays
- ✅ Error handling - proper exceptions with stack traces

This balances ColdMUD's elegant design with JavaScript pragmatism, enabling rapid development while maintaining clean semantics and strong error handling.
