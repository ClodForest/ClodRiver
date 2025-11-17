# ClodRiver Object Model

**Version:** 3.0
**Date:** November 2025
**Status:** Current Design

---

## Core Principles

1. **Every object is equivalent** - No distinction between "class" and "instance"
2. **Any object can be a parent** - True ColdMUD semantics
3. **State is never inherited** - Only methods are inherited via prototype chain
4. **State is class-namespaced** - Each definer gets its own namespace in `_state`
5. **Methods declare their imports** - Nested function pattern for clean code
6. **ctx is the execution environment** - Manages call stack, provides builtins

---

## CoreObject Class

Minimal object class with just identity and state:

```coffee
class CoreObject
  constructor: (@_id, parent = null) ->
    @_name = null
    @_state = {}
    Object.setPrototypeOf(this, parent) if parent?

module.exports = CoreObject
```

### Object Structure

Every object has:
- `_id`    - Unique numeric identifier
- `_name`  - If set, then `Core.objectNames[@_name] is @`
- `_state` - Map from class ID to properties
- Prototype chain via `Object.setPrototypeOf`

### State Storage

State is namespaced by definer ID to prevent interference:

```coffee
    # $sword has _id = 41
    $sword._state = {
      1:  {name: '$sword'}      # $root's namespace
      41: {damage: 'd6'}        # $sword's namespace
    }

    # $excalibur has _id = 42, parent = $sword
    $excalibur._state = {
      1:  {name: '$excalibur'}  # $root's namespace
      41: {damage: 'd6'}        # $sword's namespace (for inherited methods)
      42: {magic: '+10'}        # $excalibur's namespace
    }
```

---

## Core API

The Core class manages the object system:

```coffee
class Core
  constructor: ->
    @objectIDs   = {}    # id   -> object
    @objectNames = {}    # name -> object
    @nextId      = 0

  create: (parent = null) ->
    id = @nextId++
    obj = new CoreObject(id, parent)
    @objectIDs[id] = obj
    obj

  destroy: (id) ->
    obj = @objectIDs[id]
    return unless obj
    delete @objectIDs[id]
    name = obj.get('name')
    delete @objectNames[name] if name

  isObject: (obj) ->
    'object' is typeof obj and @objectIDs[obj::_id] is obj

  assignName: (name, obj) ->
    if @isObject obj
      @objectNames[name] = obj._id
      obj._name ?= name

  deassignName: (name) ->
    obj = @objectNames[name]

    if obj?._name is name
      obj._name = null

    obj

  resolve: (ref) ->
    switch
      when 'string' is typeof ref
        return switch ref[0]
          when '#' then @objectIDs[ref[1..]]
          when '$' then @objectIDs[@objectNames[ref[1..]]]
          else null

      when 'number' is typeof ref
        return @objectIDs[ref] or null

      when not ref
        return null

      when ref.$ref
        return @objectIDs[ref.$ref] or null

      else null

  addMethod: (obj, methodName, fnWrapper) ->
    # Parse imports and create wrapper
    # Install on object's prototype

  call: (obj, methodName, args = []) ->
    # Entry point from server
    # Creates ctx and invokes method
```

### resolve()

Resolves references to objects in multiple formats:

```coffee
core.resolve('$sys')    # Dollar-sign name
core.resolve('#42')     # Hash-number format
core.resolve(42)        # Numeric ID
core.resolve({$ref: 42})  # Serialized reference
```

---

## Execution Context (ctx)

The `ctx` object is the execution environment passed to all methods.

### Structure

```coffee
ctx = {
  core:     coreInstance       # The Core instance
  _stack:   [...]              # Call stack for debugging
  _definer: currentDefiner     # Object that defined current method
  _caller:  previousObject     # Previous object in call stack
  _sender:  previousDefiner    # Previous definer in call stack

  # Builtins (extracted based on method's imports)
  get:      (key) -> ...
  set:      (data) -> ...
  send:     (obj, method, args) -> ...
  throw:    (errorType) -> ...

  # Built-in functions
  this:     -> currentObject
  definer:  -> currentDefiner
  caller:   -> previousObject
  sender:   -> previousDefiner
}
```

### Builtins

Available builtins that methods can import:

- **get(key)**                   - Read property from definer's namespace
- **set(data)**                  - Write properties to definer's namespace
- **send(target, method, args)** - Invoke method on another object
- **throw(errorType)**           - Throw error
- **this()**                     - Current object being called
- **definer()**                  - Object that defined this method
- **caller()**                   - Previous object in call stack
- **sender()**                   - Previous definer in call stack

### Importing objects by name

Methods can import core.objectNames.name by listing $name in their import list.

### State Access (get/set)

The `get` and `set` builtins access the definer's namespace:

```coffee
    # When $sword method calls get/set
    ctx.get = (key) ->
      obj._state[definer._id]?[key]
    
    ctx.set = (data) ->
      obj._state[definer._id] ?= {}
      Object.assign(obj._state[definer._id], data)
      obj
```

This ensures methods always access their own namespace, regardless of which object they're called on.

---

## Method Definition Pattern

Methods use nested functions to declare which builtins they need:

```coffee
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

**Simple getter:**

```coffee
Core.add_methods
  description:
    (get) ->
      -> get 'description'
```

**Method with object interaction:**

```coffee
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

```coffee
Core.add_methods
  set_name:
    ($owners, sender, throw, set) ->
      ([name]) ->
        if sender not in $owners.of this
          throw 'perm'

        set {name}
```

**Method with no imports:**

```coffee
Core.add_methods
  simple:
    -> ([arg1, arg2]) ->
      arg1 + arg2
```

### How add_methods Works

The `add_methods` function:

1. Parses the outer function signature to extract import names
2. Creates a wrapper that receives `(ctx, args)`
3. Extracts requested builtins from ctx
4. Calls the outer function with imports bound
5. Calls the inner function (actual method) with args

```coffee
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

      # Call actual method with proper 'this'
      innerFn.call(this, args)

    # Mark definer
    actualMethod.definer = this

    # Install on prototype
    target::[methodName] = actualMethod
```

---

## Method Dispatch

### Core.call() - Entry Point

Called by server for I/O events, timers, startup:

```coffee
    # Server invokes startup
    core.call (core.resolve '$sys'), 'startup', []
```

Creates initial ctx with empty call stack.

### ctx.send() - Object-to-Object Calls

Methods call other methods using `ctx.send()`:

```coffee
    # In a method body
    send $root::allChildren
    send target::take_damage, amount
```

The `send` builtin:
- Finds method on target object's prototype chain
- Updates call stack `(_caller, _sender)`
- Creates new ctx with updated definer
- Invokes method

### Call Stack Example

```
Server:              core.call($sys, 'startup')
  ↓ creates ctx with stack: []

$sys.startup:        send $root::allChildren
  ↓ ctx.send updates stack: [$sys]

$root.allChildren:   send child::notify_startup
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

## Module Pattern

Core modules export a function that receives Core and sets up the object:

```coffee
    # sword.coffee
    module.exports = (Core) ->
      $thing = Core.resolve '$thing'
    
      $sword = Core.create($thing)
      Core.assignName 'sword', $sword
    
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

### Bootstrap Sequence

```coffee
    # Create Core
    core = new Core()
    
    # Create #0 and #1
    $sys = core.create()   # _id = 0
    $root = core.create()  # _id = 1
    Object.setPrototypeOf $sys, $root
    
    core.assignName 'sys',  $sys
    core.assignName 'root', $root
    
    # Load core modules
    require('./core/root')(core)
    require('./core/sys')(core)
    
    # Load additional objects
    for file in findCoreFiles('./core/lib')
      core.loadFromModule file
    
    # Start system
    core.call $sys.startup, []
```

---

## Object References in State

Object references are serialized with special handling to avoid conflicts with user data.

### Serialization

```coffee
_serializeValue: (value) ->
  if value instanceof CoreObject
    {$ref: value._id}
  else if value?.$ref? and not (value instanceof CoreObject)
    {$ref: false, value: value}
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
  else
    value
```

### Cases Handled

```coffee
    # Case 1: Actual object reference
    obj42 → {$ref: 42}
    
    # Case 2: User data with $ref key
    {$ref: "user data"} → {$ref: false, value: {$ref: "user data"}}
    
    # Case 3: Normal data
    {foo: "bar"} → {foo: "bar"}
```

---

## Method Inheritance

Methods are inherited via JavaScript's prototype chain:

```coffee
    $thing = Core.create()
    $thing._state[$thing._id].description = 'you see nothing special'
    Core.addMethod $thing, 'look',
      (get) ->
        -> (get 'description') ? 'this object is indescribable'
    
    $sword = Core.create($thing)
    
    send $sword.look, []  # Uses $thing's look method
    # => 'this object is indescribable'
    # uses default because $sword._state[$thing._id].description is undefined
```

### Override

Child objects can define their own version:

```coffee
Core.addMethod $sword, 'look',
  (get) ->
    -> "#{get 'name'} - a weapon"

send $sword.look, []  # Uses $sword's look method
```

### Pass to Parent

Use `ctx.pass()` to call parent's implementation:

```coffee
Core.addMethod $sword, 'look',
  (get, pass) ->
    ->
      parent_desc = pass()
      "#{parent_desc} with a blade"
```

---

## Reserved Names

Objects MUST NOT define methods or properties with these names:

- `_id`    - Object #ID
- `_name`  - Object $name
- `_state` - State storage

Method names can be anything else, including importable names and ColdMUD
built-in names. These are ok because they are invoked without JavaScript prop
lookup: `send $utils::toobj` doesn't conflict with `toobj()`.

Attempts to define functions with names starting with underscore will throw an
error or something.

---

## Deferred to v2

These features are not in v1 but planned for v2:

1. **Sandboxing via IPC** - OS-level isolation for untrusted code
2. **Dynamic method addition** - Runtime method definition
3. **Multiple inheritance** - Mixin pattern for composition
4. **Method finalization** - Prevent override for security
5. **Per-instance methods** - Methods on specific objects
6. **Full permissions system** - Admin/wizard checks, ownership

**Rationale:** v1 focuses on proving LLM integration works. These features add complexity without providing immediate value for single-user development.

---

## Summary

The ClodRiver object model:

- ✅ Every object is equivalent - any can be a parent
- ✅ State is class-namespaced - no inheritance conflicts
- ✅ Methods are inherited - via prototype chain
- ✅ Clean execution context - ctx manages everything
- ✅ Declarative imports - methods declare what they need
- ✅ ColdMUD semantics - definer/caller/sender tracking
- ✅ Simple serialization - {$ref: id} for object references

This balances ColdMUD's elegant design with JavaScript pragmatism, enabling rapid v1 development while maintaining a clear path to v2's full feature set.
