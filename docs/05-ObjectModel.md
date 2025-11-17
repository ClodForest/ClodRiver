# Object Model v3.0

**Date:** November 2025
**Status:** Current Design

---

## Core Principles

1. **CoreObject is minimal** - Just `_id` and `_state`
2. **Core manages everything** - Object lifecycle, method dispatch, context
3. **ctx is the execution environment** - Provides builtins, manages call stack
4. **Methods declare their imports** - Using nested function pattern
5. **No @ magic for state access** - Use `get`/`set` from ctx

---

## CoreObject Class

Minimal object class:

```coffeescript
class CoreObject
  constructor: (@_id, parent = null) ->
    @_state = {}
    Object.setPrototypeOf(this, parent) if parent?

module.exports = CoreObject
```

Every object has:
- `_id` - Unique numeric identifier
- `_state` - Map from class ID to properties: `{1: {name: 'root'}, 6: {desc: '...'}, ...}`
- Prototype chain via JavaScript's `Object.setPrototypeOf`

---

## Core API

The Core class manages the object system:

```coffeescript
class Core
  constructor: ->
    @objectIDs   = {}    # id -> object
    @objectNames = {}    # name -> id
    @nextId      = 0
    @$           = {}    # Dollar-sign namespace

  create: (parent = null) ->
    # Creates new CoreObject with sequential ID

  destroy: (id) ->
    # Removes object from registry

  resolve: (ref) ->
    # Resolves '$name', '#id', or numeric id to object

  addMethod: (obj, methodName, fn) ->
    # Installs method on object's prototype

  call: (obj, methodName, args = []) ->
    # Entry point from server - creates initial ctx and invokes method
```

### Core.resolve()

Resolves references to objects:

```coffeescript
resolve: (ref) ->
  if 'string' is typeof ref
    return switch ref[0]
      when '#' then @objectIDs[ref[1..]]
      when '$' then @objectIDs[@objectNames[ref[1..]]]
      else null

  if 'number' is typeof ref
    return @objectIDs[ref] or null

  if not ref
    return null

  if ref.$ref then return @objectIDs[ref.$ref] or null

  null
```

---

## Execution Context (ctx)

The `ctx` object is the execution environment passed to all methods. It provides:

### Builtins

Methods declare which builtins they need:

- `get(key)` - Read property from definer's namespace
- `set(data)` - Write properties to definer's namespace
- `send(obj, methodName, args)` - Invoke method on another object
- `throw(errorType)` - Throw error
- `this()` - Current object
- `definer()` - Object that defined this method
- `caller()` - Previous object in call stack
- `sender()` - Previous definer in call stack

### Core References

Access to the Core instance and registered objects:

- `ctx.core` - The Core instance
- Via `ctx.core.$` - Dollar-sign namespace (`$sys`, `$root`, etc.)

### Call Stack

The ctx maintains the call stack for debugging and security:

```coffeescript
ctx = {
  core:     coreInstance
  _stack:   [...]
  _definer: currentDefiner
  _caller:  previousObject
  _sender:  previousDefiner

  # Builtins provided based on method's imports
}
```

---

## Method Definition Pattern

Methods use nested functions to declare imports:

```coffeescript
Core.add_methods
  methodName:
    # Outer function: declares imports from ctx
    (import1, import2, import3) ->

      # Inner function: the actual method
      (args) ->
        # Method body uses the imports
        import1('foo')
        import2({bar: 'baz'})
```

### Examples

**Simple method with state access:**

```coffeescript
Core.add_methods
  description:
    (get) ->
      -> get 'description'
```

**Method with object interaction:**

```coffeescript
Core.add_methods
  swing:
    (get, send) ->
      ([target]) ->
        send get('rpg_system')::start_action,
          action:         get 'attack'
          subject:        get 'wielder'
          directObject:   target
          indirectObject: this
```

**Method with permission checking:**

```coffeescript
Core.add_methods
  set_name:
    ($owners, sender, throw, set) ->
      ([name]) ->
        if sender not in $owners.of this
          throw 'perm'

        set {name}
```

**Method with no imports:**

```coffeescript
Core.add_methods
  simple:
    -> ([arg1, arg2]) ->
      # No ctx access needed
      arg1 + arg2
```

---

## add_methods Implementation

The `add_methods` function:

1. Parses the outer function signature to extract import names
2. Creates a wrapper that receives `(ctx, args)`
3. Extracts requested builtins from ctx
4. Calls the inner function with imports bound
5. Calls the method body with args

```coffeescript
add_methods: (methods) ->
  for methodName, fnWrapper of methods
    imports = @_parseImports(fnWrapper)

    actualMethod = (ctx, args) ->
      # Extract requested imports from ctx
      bindings = {}
      for imp in imports
        bindings[imp] = ctx[imp]

      # Get inner function
      innerFn = fnWrapper(bindings...)

      # Call actual method
      innerFn.call(this, args)

    # Mark definer
    actualMethod.definer = this

    # Install on prototype
    this[methodName] = actualMethod
```

---

## State Access Pattern

State is namespaced by definer ID:

```coffeescript
# $sword has _id = 41
$sword._state = {
  1:  {name: '$sword'}      # $root's namespace
  41: {damage: 'd6'}        # $sword's namespace
}

# $excalibur has _id = 42, parent = $sword
$excalibur._state = {
  1:  {name: '$excalibur'}  # $root's namespace
  41: {damage: 'd6'}        # $sword's namespace (inherited method access)
  42: {magic: '+10'}        # $excalibur's namespace
}
```

When a method defined on `$sword` calls `get('damage')`, it accesses `@_state[41].damage` regardless of which object it's called on.

**In ctx.get/set:**

```coffeescript
ctx.get = (key) ->
  obj._state[definer._id]?[key]

ctx.set = (data) ->
  obj._state[definer._id] ?= {}
  Object.assign(obj._state[definer._id], data)
  obj
```

---

## Method Dispatch

### Core.call() - Entry Point

Called by server for I/O events, timers, startup:

```coffeescript
# Server invokes startup
core.call (core.resolve '$sys'), 'startup', []
```

### ctx.send() - Object-to-Object

Methods call other methods using `ctx.send()`:

```coffeescript
# In a method
send $root::allChildren
send target::take_damage, amount
```

The `send` builtin:
- Updates call stack
- Finds method on target object
- Creates new ctx with updated definer/caller/sender
- Invokes method

---

## Module Pattern

Core modules export a function that receives Core and sets up the object:

```coffeescript
# sword.coffee
module.exports = (Core) ->
  $thing = Core.resolve '$thing'

  $sword = Core.create($thing)
  Core.registerDollar('sword', $sword)

  $sword._state = {
    1:  {name: 'sword'}
    41: {damage: 'd6', weight: 5}
  }

  Core.addMethod $sword, 'swing',
    (get, send) ->
      ([target]) ->
        damage = get 'damage'
        send target::take_damage, damage

  $sword
```

---

## Call Stack Example

```
Server:          core.call($sys, 'startup')
  ↓ creates ctx with stack: []

$sys.startup:    send $root::allChildren
  ↓ ctx.send updates stack: [$sys]

$root.allChildren: send child::notify_startup
  ↓ ctx.send updates stack: [$sys, $root]

$child.notify_startup: ...
  ↓ stack: [$sys, $root, $child]
```

At each level:
- `this()` returns current object
- `definer()` returns object that defined current method
- `caller()` returns previous object in stack
- `sender()` returns previous definer in stack

---

## Key Differences from Previous Designs

1. **No closure-bound get/set on CoreObject** - Moved to ctx
2. **Nested function import pattern** - Cleaner than ctx.get everywhere
3. **ctx.send vs Core.call** - Distinction between entry point and object calls
4. **ctx manages call stack** - For debugging and security
5. **Plain objects, not Maps** - Simpler, `objectIDs` and `objectNames`

---

## Implementation Checklist

- [ ] CoreObject - minimal class
- [ ] Core.create/destroy/resolve
- [ ] Core.call - entry point with ctx creation
- [ ] ctx object structure
- [ ] ctx.send - object-to-object calls
- [ ] add_methods - parse imports and wrap
- [ ] ctx.get/set - definer-scoped access
- [ ] Call stack management
- [ ] Error handling with ctx.throw

---

## Open Questions

1. How do we handle `this` in nested function pattern? Is it bound correctly?
2. Should `$sys`, `$root` etc. be on ctx directly, or accessed via `ctx.core.$`?
3. Do we need ctx.pass() for calling parent implementation?
4. How does serialization work with this model?
