# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClodRiver is a modern MUD (Multi-User Dungeon) server written in Node.js/CoffeeScript that integrates Large Language Models for natural language parsing, dynamic world building, and intelligent NPC behavior. The project takes inspiration from ColdMUD's elegant design while leveraging modern JavaScript/CoffeeScript capabilities.

**Current Status:** Object model design phase - implementing Core and CoreObject with nested function import pattern.

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
    @_name = null
    @_state = {}
    Object.setPrototypeOf(this, parent) if parent?
```

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

  assignName: (name, obj) ->
    # Register object with name
    # objectNames[name] = obj (not obj._id)
    # Sets obj._name if not already set

  resolve: (ref) ->
    # Resolves '$name', '#id', number, or {$ref: id}

  call: (obj, method, args = []) ->
    # Entry point from server - creates ctx

  # Note: Core.$ removed - use objectNames directly
```

### Execution Context (ctx)

The ctx object provides execution environment:

```coffee
ctx = {
  core:     coreInstance
  _stack:   [...]
  _definer: currentDefiner
  _caller:  previousObject
  _sender:  previousDefiner

  # Builtins (based on method imports)
  get:      (key) -> obj._state[definer._id]?[key]
  set:      (data) -> ...
  send:     (target, method, args) -> ...
}
```

### Method Dispatch

- `Core.call(obj, method, args)` - Entry point from server
- `ctx.send(target, method, args)` - Object-to-object calls within methods
- `send` updates call stack and manages definer/caller/sender tracking

## Directory Structure

```
ClodRiver/
├── docs/
│   ├── 00-ObjectModel.md       # Current object model spec (PRIMARY)
│   ├── 00-ProjectVision.md     # Project goals
│   ├── 01-Architecture.md      # Server/Core architecture
│   ├── 02-DesignDecisions.md   # Design rationale
│   ├── 03-ObjectModel.md       # Earlier iteration (superseded)
│   ├── 04-ObjectModel-Revised.md  # Earlier iteration (superseded)
│   └── 05-ObjectModel.md       # Earlier iteration (superseded)
├── lib/
│   ├── core.coffee             # Core class (needs rewrite)
│   └── core_object.coffee      # CoreObject class (needs rewrite)
├── t/
│   ├── core.coffee             # Core tests (needs update)
│   └── core_object.coffee      # CoreObject tests (needs update)
└── package.json
```

**Note:** `lib/core*.coffee` were written before nested function import pattern was designed. They need to be rewritten based on `docs/00-ObjectModel.md`.

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

### assignName vs registerDollar
Renamed for clarity:
- `assignName(name, obj)` - registers name
- `deassignName(name)` - removes name
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
- **Methods declare imports** - Nested function pattern
- **ctx manages execution** - Call stack, builtins, definer tracking
- **No comments in code** - Self-documenting preferred

## Current Implementation Status

- ✅ package.json configured
- ✅ lib/core_object.coffee created (needs rewrite for v3.0)
- ✅ lib/core.coffee created (needs rewrite for v3.0)
- ✅ t/core_object.coffee created (needs update)
- ✅ t/core.coffee created (needs update)
- ✅ docs/00-ObjectModel.md - primary specification (in review)
- 🔄 Tests run but fail (implementation doesn't match v3.0 design)

**Next:** Rewrite core*.coffee and tests based on docs/00-ObjectModel.md after Robert finishes review.

## Related Documentation

Primary docs (in order of importance):
1. `docs/00-ObjectModel.md` - Current object model (PRIMARY - being reviewed)
2. `docs/00-ProjectVision.md` - Project goals and philosophy
3. `docs/01-Architecture.md` - Server/Core two-tier architecture
4. `docs/02-DesignDecisions.md` - Design rationale

## Project Context

Part of ClodForest ecosystem:
- **ClodForest** - MCP server infrastructure
- **ClodRiver** - This MUD server
- **Agent Calico** - Multi-agent orchestration

ClodRiver revives ColdMUD's elegance with modern LLM integration for natural language parsing, dynamic world building, and intelligent NPCs.
