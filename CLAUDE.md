# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClodRiver is a modern MUD (Multi-User Dungeon) server written in Node.js/CoffeeScript that integrates Large Language Models for natural language parsing, dynamic world building, and intelligent NPC behavior. The project takes inspiration from ColdMUD's elegant design while leveraging modern JavaScript/CoffeeScript capabilities.

**Current Status:** Validating object model implementation - Core, CoreObject, and ExecutionContext classes implementing v3.0 design.

## Language and Style

- **Primary Language:** CoffeeScript for both server and core code
- **Why CoffeeScript:** Readable class syntax, `@` sugar for `this`, implicit returns, comprehensions, significant whitespace, compiles to readable ES6
- **No Comments:** Code should be self-documenting. Avoid comments in implementation.
- **Style:** Follow Robert's development standards (vertical alignment, self-documenting code, data structure lookups over if-chains)

## Object Model (Current Design - v3.0)

See `docs/00-ObjectModel.md` for complete specification. Key points:

### CoreObject - All Objects Share Same Constructor

```coffee
class CoreObject
  constructor: (@_id, parent = null) ->
    @_state = {}
    Object.setPrototypeOf(this, parent) if parent?
```

**Note:** Removed `@_name` - names are managed by Core.objectNames, not stored on objects.

**Important:** All objects are instances of CoreObject:
- `$root.constructor === $thing.constructor === CoreObject`
- Inheritance via `Object.setPrototypeOf(child, parent)`
- NOT class-per-instance pattern
- Simpler, fewer objects, cleaner

### State Storage - Class-Namespaced

State is namespaced by definer ID to prevent interference:

```coffee
$excalibur._state = {
  1:  {name: '$excalibur'}    # $root's namespace
  6:  {displayName: 'Excalibur'}  # $thing's namespace
  41: {damage: '3d12+10'}     # $sword's namespace
  42: {wielder: arthur}       # $excalibur's namespace
}
```

### Method Definition - Nested Function Import Pattern

Methods declare which builtins they need using nested functions:

```coffee
Core.addMethod $sword, 'swing',
  (get, send) ->          # Outer: declares imports
    ([target]) ->         # Inner: actual method
      damage = get 'damage'
      send target::take_damage, damage
```

Available imports:
- `get(key)` - Read from definer's namespace
- `set(data)` - Write to definer's namespace
- `send(target, method, args)` - Call method on another object
- `throw(errorType)` - Throw error
- `this()`, `definer()`, `caller()`, `sender()` - ColdMUD builtins
- `$name` - Import objects by name (e.g., `$sys`, `$root`)

### Core API

```coffee
class Core
  constructor: ->
    @objectIDs   = {}    # id -> object
    @objectNames = {}    # name -> object (not id!)
    @nextId      = 0

  create: (parent = null) ->
    # Creates CoreObject with sequential ID

  destroy: (ref) ->
    # Removes object from both objectIDs and objectNames

  add_obj_name: (name, obj) ->
    # Register object with name: objectNames[name] = obj

  del_obj_name: (name) ->
    # Remove name registration

  toobj: (ref) ->
    # Resolves '$name', '#id', number, or {$ref: id}
    # Returns object or null

  addMethod: (obj, methodName, fn) ->
    # Adds method to object, sets fn.definer and fn.methodName

  delMethod: (obj, methodName) ->
    # Removes method from object

  call: (obj, methodName, args = []) ->
    # Entry point from server - creates ExecutionContext
```

### ExecutionContext

Implemented in `lib/execution-context.coffee`, provides execution environment:

```coffee
class ExecutionContext
  constructor: (@core, @obj, @method, @parent = null) ->
    @definer = @method.definer
    @stack   = if @parent then [@parent.stack..., @parent.obj] else []

  # State access (definer's namespace)
  get: (key) ->
    @obj._state[@definer._id]?[key]

  set: (data) ->
    @obj._state[@definer._id] ?= {}
    Object.assign @obj._state[@definer._id], data
    @obj

  # ColdMUD builtins
  this:    -> @obj
  definer: -> @definer
  caller:  -> @parent?.obj or null
  sender:  -> @parent?.definer or null

  # Method dispatch
  send: (target, methodName, args...) ->
    # Resolves target, finds method, creates child context
    # Updates call stack automatically

  pass: (args...) ->
    # Calls parent's implementation with parent context
```

### Method Dispatch

- `core.call(obj, methodName, args)` - Entry point from server, creates root ExecutionContext
- `ctx.send(target, methodName, args)` - Object-to-object calls, creates child ExecutionContext
- `ctx.pass(args)` - Call parent implementation, preserves call stack
- Call stack tracked automatically through ExecutionContext parent chain

## Directory Structure

```
ClodRiver/
├── docs/
│   ├── 00-ObjectModel.md          # Current object model spec (PRIMARY)
│   ├── 00-ProjectVision.md        # Project goals
│   ├── 01-Architecture.md         # Server/Core architecture
│   ├── 02-DesignDecisions.md      # Design rationale
│   ├── 03-ObjectModel.md          # Earlier iteration (superseded)
│   ├── 04-ObjectModel-Revised.md  # Earlier iteration (superseded)
│   └── 05-ObjectModel.md          # Earlier iteration (superseded)
├── lib/
│   ├── core.coffee                # Core class - object system management
│   ├── core-object.coffee         # CoreObject class - minimal object structure
│   └── execution-context.coffee   # ExecutionContext - method execution environment
├── t/
│   ├── core.coffee                # Core tests (needs update)
│   └── core-object.coffee         # CoreObject tests (needs update)
└── package.json
```

## Key Design Decisions

### Plain Objects Not Maps
Use plain objects `{}` instead of `Map`:
- `objectIDs` and `objectNames` are plain objects
- Simpler, cheaper, don't need to distinguish `"42"` vs `42`

### objectNames Maps to Objects
`objectNames[name]` stores the object itself, not the ID:
- Consistency: `objectIDs[1]` is object, `objectNames.root` is same object
- Simplifies lookup

### No Core.$
Removed `Core.$` namespace as redundant:
- Methods can import `$name` directly
- `add_methods` checks if import matches a registered name

### add_obj_name vs assignName
Renamed for clarity:
- `add_obj_name(name, obj)` - registers name in objectNames
- `del_obj_name(name)` - removes name registration
- Can assign multiple names to same object

## CoffeeScript Notation

Uses `::` for prototype access:

```coffee
obj::method          # obj.prototype.method
$sword::swing        # The swing method on $sword

send obj::method     # Call method via prototype chain
```

## Module Pattern

```coffee
# sword.coffee
module.exports = (core) ->
  $thing = core.toobj '$thing'

  $sword = core.create $thing
  core.add_obj_name 'sword', $sword

  $sword._state = {
    1:  {name: 'sword'}
    41: {damage: 'd6', weight: 5}
  }

  core.addMethod $sword, 'swing',
    (get, send) ->
      ([target]) ->
        damage = get 'damage'
        send target, 'take_damage', damage

  $sword
```

## Testing

Tests use Node's built-in test runner:

```bash
npm test              # Run all tests
npm run test:watch   # Watch mode
```

Tests register CoffeeScript via `node -r coffeescript/register`.

## Important Notes

- **All objects are CoreObject instances** - No class-per-instance
- **State is class-namespaced** - Prevents inheritance conflicts
- **Methods declare imports** - Nested function pattern (planned for v2)
- **ExecutionContext manages execution** - Call stack, builtins, definer tracking
- **Deep serialization** - Object references handled at any depth in state
- **No comments in code** - Self-documenting preferred

## Current Implementation Status

- ✅ package.json configured for CoffeeScript testing
- ✅ docs/00-ObjectModel.md - finalized v3.0 specification
- ✅ lib/core-object.coffee - CoreObject with deep serialization
- ✅ lib/execution-context.coffee - ExecutionContext with send/pass
- ✅ lib/core.coffee - Core with toobj, add_obj_name, method management
- 🔄 t/core-object.coffee - needs update for v3.0 API
- 🔄 t/core.coffee - needs update for v3.0 API (ExecutionContext, renamed methods)
- 📋 Tests need to run to validate implementation

**Next:** Update tests and run them to validate the object model implementation.

## Related Documentation

Primary docs (in order of importance):
1. `docs/00-ObjectModel.md` - Current object model v3.0 (PRIMARY - finalized)
2. `docs/00-ProjectVision.md` - Project goals and philosophy
3. `docs/01-Architecture.md` - Server/Core two-tier architecture
4. `docs/02-DesignDecisions.md` - Design rationale

## Project Context

Part of ClodForest ecosystem:
- **ClodForest** - MCP server infrastructure
- **ClodRiver** - This MUD server
- **Agent Calico** - Multi-agent orchestration

ClodRiver revives ColdMUD's elegance with modern LLM integration for natural language parsing, dynamic world building, and intelligent NPCs.
