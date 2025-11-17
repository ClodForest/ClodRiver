# Object Model - Revised Design

**Version:** 2.0  
**Date:** November 2025  
**Status:** Proof of Concept Phase

---

## Summary of Changes

We've revised the object model to eliminate ES6 `class` syntax and embrace a simpler approach where every object is equivalent. This brings us closer to ColdMUD's model while still leveraging JavaScript's prototype chain.

---

## Core Design: Objects Without Classes

### No Class Syntax

Instead of using `class $sword extends $thing`, we create objects directly and link them via prototypes:

```coffeescript
# Old (class syntax):
class $sword extends $thing
  swing: (ctx, args) -> ...

# New (object creation):
$sword = CoreAPI.create($thing)
CoreAPI.add_method $sword, 'swing', (ctx, args) -> ...
```

### Every Object Is Equivalent

```coffeescript
$thing._id === 6           # Has an ID
$sword._id === 41          # Has an ID
$excalibur._id === 42      # Has an ID

$sword.prototype === $thing           # Parent linkage
$excalibur.prototype === $sword       # Child of $sword
```

Any object can be a parent. There's no distinction between "class" and "instance" - they're all just objects.

---

## State Storage: Class-Namespaced

### Structure

Each object's `_state` is a map from class ID to properties:

```coffeescript
$excalibur._state = {
  1:  {name: '$excalibur'},        # $root's namespace
  6:  {displayName: 'Excalibur'},  # $thing's namespace
  41: {dmg: '3d12+10'},            # $sword's namespace
  42: {wielder: arthur}            # $excalibur's namespace
}
```

### Closure-Bound Accessors

When an object is created, its `get` and `set` methods are bound via closure to its class ID:

```coffeescript
CoreAPI.create = (parent) ->
  class_id = @nextId++
  
  obj = Object.create(parent)  # Link to parent
  obj._id = class_id
  obj._state = {}
  
  # Closure captures class_id
  obj.get = (key) ->
    @_state[class_id]?[key]
    
  obj.set = (data) ->
    @_state[class_id] ?= {}
    Object.assign(@_state[class_id], data)
    @
  
  obj
```

Now `@get` and `@set` automatically access the correct namespace:

```coffeescript
$sword.set({dmg: 'd6'})      # Sets _state[41].dmg
damage = $sword.get('dmg')   # Reads _state[41].dmg
```

---

## Method Dispatch: Definer-Scoped Context

### The Problem

When `$excalibur` inherits a method from `$sword`, and that method calls `@get('dmg')`, whose closure runs?

```coffeescript
# $sword.get is bound to class_id = 41
$excalibur.get === $sword.get  # true (inherited via prototype)

# But we want the method to access $sword's namespace (41),
# not $excalibur's namespace (42)!
```

### The Solution: Context-Scoped Accessors

Methods don't use `@get/@set` directly. Instead, they use `ctx.get/ctx.set` which are bound to the **definer's** namespace:

```coffeescript
CoreAPI.add_method = (obj, methodName, fn) ->
  obj[methodName] = fn
  obj[methodName].definer = obj  # Mark who defined this method
  
CoreAPI.call = (obj, methodName, ctx, args) ->
  method = obj[methodName]
  definer = method.definer
  
  # Provide definer-scoped accessors in context
  ctx.get = (key) ->
    obj._state[definer._id]?[key]
    
  ctx.set = (data) ->
    obj._state[definer._id] ?= {}
    Object.assign(obj._state[definer._id], data)
    obj
  
  # Invoke
  method.call(obj, ctx, args)
```

### Usage

```coffeescript
# Define method on $sword
CoreAPI.add_method $sword, 'swing', (ctx, args) ->
  dmg = ctx.get('dmg')  # Reads _state[41].dmg (definer's namespace)
  wielder = ctx.get('wielder')  # Reads _state[41].wielder (undefined!)

# When called on $excalibur:
CoreAPI.call($excalibur, 'swing', {}, [])
# ctx.get still reads _state[41] because definer = $sword
```

### Accessing Caller's State

If a method needs to read the caller's (not definer's) state, use the object directly:

```coffeescript
CoreAPI.add_method $sword, 'swing', (ctx, args) ->
  # Definer's (sword's) damage
  base_dmg = ctx.get('dmg')
  
  # Caller's (excalibur's) bonus
  bonus = @_state[42]?.magic_bonus or 0
  
  total = base_dmg + bonus
```

But generally, methods should only access their definer's namespace. If cross-namespace access is needed frequently, the design should be reconsidered.

---

## Method Inheritance and Pass

### Inheritance

Methods are inherited via prototype chain:

```coffeescript
$thing = CoreAPI.create()
CoreAPI.add_method $thing, 'look', (ctx, args) ->
  "You see a thing"

$sword = CoreAPI.create($thing)

# $sword inherits look()
CoreAPI.call($sword, 'look')  # "You see a thing"
```

### Override

Child objects can define their own version:

```coffeescript
CoreAPI.add_method $sword, 'look', (ctx, args) ->
  "You see a sword"

CoreAPI.call($sword, 'look')  # "You see a sword"
```

### Pass to Parent

Use `ctx.pass()` to call the parent's version:

```coffeescript
CoreAPI.add_method $sword, 'look', (ctx, args) ->
  parent_desc = ctx.pass(args...)
  "#{parent_desc} with a blade"

CoreAPI.call($sword, 'look')  # "You see a thing with a blade"
```

Implementation:

```coffeescript
ctx.pass = (passArgs...) ->
  # Find parent's version of this method
  parent = definer.prototype or Object.getPrototypeOf(definer)
  parentMethod = parent?[methodName]
  
  if parentMethod?
    CoreAPI.call(obj, methodName, {
      ...ctx
      definer: parentMethod.definer
    }, passArgs)
```

---

## Module Format

Modules export a function that receives CoreAPI and creates/configures an object:

```coffeescript
# core/sword.coffee
module.exports = (CoreAPI, $sys, $root) ->
  {$thing, $weapon} = CoreAPI
  
  # Create object
  $sword = CoreAPI.create($weapon)
  
  # Register name
  CoreAPI.call($sys, 'set_obj_name', {}, [$sword, 'sword'])
  
  # Set initial state
  $sword.set({
    name: 'sword'
    displayName: 'a sword'
    damage: 'd6'
  })
  
  # Add methods
  CoreAPI.add_method $sword, 'swing', (ctx, args) ->
    [target] = args
    damage = ctx.get('damage')
    # Attack logic...
  
  # Return object for registration
  $sword
```

---

## Bootstrap Sequence

```coffeescript
# Create CoreAPI
coreAPI = new CoreAPI()

# Create #0 and #1 (bootstrap objects)
coreAPI.nextId = 0
$sys = coreAPI.create()  # #0

coreAPI.nextId = 1  
$root = coreAPI.create()  # #1

# Make $sys child of $root
Object.setPrototypeOf($sys, $root)

# Store for global access
coreAPI.$sys = $sys
coreAPI.$root = $root

# Load core modules
rootModule = require('./core/root')
rootModule(coreAPI, $sys, $root)

sysModule = require('./core/sys')
sysModule(coreAPI, $sys, $root)

# Load additional core objects
for file in findCoreFiles('./core/lib')
  obj = require(file)(coreAPI, $sys, $root)
  # Objects self-register via set_obj_name
```

---

## Object Reference Serialization

### Serialize

```coffeescript
serializeValue: (value) ->
  if @isCoreRef(value)
    {$ref: value._id}
  else if value?.$ref?
    {$ref: false, value}
  else
    value
```

### Deserialize

```coffeescript
deserializeValue: (value) ->
  if value?.$ref?
    if value.value?
      value.value
    else
      @toObjectRef(value.$ref)
  else
    value
```

### Cases

```coffeescript
# Object reference
$room  # → {$ref: 100}

# User data with $ref key  
{$ref: "data"}  # → {$ref: false, value: {$ref: "data"}}

# Normal data
{name: "Bob"}  # → {name: "Bob"}
```

---

## Key Differences from 03-ObjectModel.md

1. **No `class` syntax** - Objects created directly with `CoreAPI.create()`
2. **Closure-bound `@get/@set`** - Automatically access correct namespace
3. **Context-scoped accessors** - `ctx.get/set` access definer's namespace
4. **Method metadata** - `.definer` property tracks defining object
5. **Simpler hierarchy** - No intermediate anonymous classes

---

## What This Enables

- ✓ Every object can be a parent (true ColdMUD semantics)
- ✓ No state inheritance (enforces open/closed principle)
- ✓ Methods access their definer's namespace automatically
- ✓ Hot reload by replacing methods on prototype
- ✓ Simple serialization (just objects and prototypes)

---

## Next Steps

1. **Proof of concept** - Implement in `lib/core.coffee` and test
2. **Fix `ctx.pass()`** - Prototype chain walking needs refinement
3. **Add $sys BIFs** - `create()`, `set_obj_name()`, etc.
4. **Add $root BIFs** - `add_method()`, `del_method()`
5. **LLM integration** - Implement `llm_*` BIFs

---

## Open Questions

1. Should `@get/@set` still exist on objects, or only `ctx.get/set`?
2. How to handle initialization - should constructors set default state?
3. Does `ctx.pass()` need access to caller's args, or definer's?
4. Should we support multiple inheritance via mixin pattern?

---

*This design brings us closer to ColdMUD's elegance while maintaining JavaScript compatibility.*