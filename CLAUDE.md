# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClodRiver is a modern MUD (Multi-User Dungeon) server written in Node.js/CoffeeScript that integrates Large Language Models for natural language parsing, dynamic world building, and intelligent NPC behavior. The project takes inspiration from ColdMUD's elegant design while leveraging modern JavaScript/CoffeeScript capabilities.

**Current Status:** Object model v4.0 implemented and tested - Core, CoreObject, CoreMethod, and ExecutionContext classes fully functional. Modular core loading BIFs added for package/module systems. Extended .clod format with `object $name`, `parent $name`, and `default_parent`. 134 tests passing.

## Language and Style

- **Primary Language:** CoffeeScript for both server and core code
- **Why CoffeeScript:** Readable class syntax, `@` sugar for `this`, implicit returns, comprehensions, significant whitespace, compiles to readable ES6
- **No Comments:** Code should be self-documenting. Avoid comments in implementation.
- **Style:** Follow Robert's development standards (vertical alignment, self-documenting code, data structure lookups over if-chains)

## Object Model (Current Design - v4.0)

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

### CoreMethod - Encapsulates Method Metadata

Methods are CoreMethod instances that encapsulate function, definer, source, and flags:

```coffee
class CoreMethod
  constructor: (@name, @fn, @definer, @source = null, @flags = {}) ->
    @disallowOverrides = @flags.disallowOverrides ? false
    @_importNames = null

  invoke: (core, obj, ctx, args) ->
    # Extract imports, resolve them, call outer then inner function
```

### Method Definition - Nested Function Import Pattern

Methods declare which builtins they need using nested functions:

```coffee
core.addMethod $sword, 'swing',
  (cget, send) ->         # Outer: declares imports
    (ctx, args) ->        # Inner: actual method (receives ctx and args)
      [target] = args
      damage = cget 'damage'
      send target, 'take_damage', damage
```

Available imports:
- `cget(key)` - Read from definer's namespace on current object
- `cset(data)` - Write to definer's namespace on current object
- `send(target, methodName, args...)` - Call method on another object
- `pass(args...)` - Call parent's implementation of current method
- `cthis()`, `definer()`, `caller()`, `sender()` - ColdMUD builtins
- `$name` - Import objects by name (e.g., `$sys`, `$root`)
- Any BIF name - `create`, `add_method`, `toint`, `tostr`, `children`, `lookup_method`, `compile`, `clod_eval`, `listen`, `accept`, `emit`, `load_core`, `core_toobj`, `core_call`, `core_destroy`

### Core API

```coffee
class Core
  constructor: ->
    @objectIDs   = {}    # id -> object
    @objectNames = {}    # name -> object (not id!)
    @nextId      = 0
    @bifs        = new BIFs this

  create: (parent = null, name) ->
    # Creates CoreObject with sequential ID
    # Optionally registers name if provided

  destroy: (ref) ->
    # Removes object from both objectIDs and objectNames

  add_obj_name: (name, obj) ->
    # Register object with name: objectNames[name] = obj

  del_obj_name: (name) ->
    # Remove name registration

  toobj: (ref) ->
    # Resolves '$name', '#id', number, or {$ref: id}
    # Returns object or null

  addMethod: (obj, methodName, fn, source = null, flags = {}) ->
    # Creates CoreMethod instance and adds to object
    # source: CoffeeScript source for serialization
    # flags: {disallowOverrides: bool}

  delMethod: (obj, methodName) ->
    # Removes method from object

  call: (obj, methodName, args = []) ->
    # Entry point from server - creates ExecutionContext
    # Finds CoreMethod via _findMethod, creates ctx, invokes method

  callIfExists: (obj, methodName, args = []) ->
    # Same as call() but logs and returns null if method not found
    # Used for event handlers
```

### ExecutionContext

Implemented in `lib/execution-context.coffee`, provides execution environment:

```coffee
class ExecutionContext
  constructor: (@core, @obj, @method, @parent = null) ->
    @_definer = @method.definer
    @stack    = if @parent then [@parent.stack..., @parent.obj] else []

  # State access (definer's namespace) - fat arrow for binding
  cget: (key) =>
    @obj._state[@_definer._id]?[key]

  cset: (data) =>
    @obj._state[@_definer._id] ?= {}
    Object.assign @obj._state[@_definer._id], data
    @obj

  # ColdMUD builtins - fat arrow for binding
  cthis:   => @obj
  definer: => @_definer
  caller:  => @parent?.obj or null
  sender:  => @parent?._definer or null

  # Method dispatch - fat arrow for binding
  send: (target, methodName, args...) =>
    # Resolves target via _findMethod, creates child context
    # Updates call stack automatically
    method = @core._findMethod target, methodName
    throw new MethodNotFoundError(target._id, methodName) unless method?
    childCtx = new ExecutionContext @core, target, method, this
    method.invoke @core, target, childCtx, args

  pass: (args...) =>
    # Calls parent's implementation with parent context
    parent = Object.getPrototypeOf @_definer
    throw new NoParentMethodError(@obj._id, @method.name) if parent is Object.prototype
    parentMethod = @core._findMethod parent, @method.name
    throw new NoParentMethodError(@obj._id, @method.name) unless parentMethod?
    parentCtx = new ExecutionContext @core, @obj, parentMethod, this
    parentMethod.invoke @core, @obj, parentCtx, args

  # Network methods - fat arrow for binding
  listen: (listener, options) =>
    @core.bifs.listen this, listener, options

  accept: (connection) =>
    @core.bifs.accept this, connection

  emit: (data) =>
    @core.bifs.emit this, data
```

### Method Dispatch

- `core.call(obj, methodName, args)` - Entry point from server
  - Finds CoreMethod via `_findMethod(obj, methodName)`
  - Creates root ExecutionContext with empty parent
  - Invokes `coreMethod.invoke(core, obj, ctx, args)`
- `ctx.send(target, methodName, args...)` - Object-to-object calls
  - Finds CoreMethod via `_findMethod(target, methodName)`
  - Creates child ExecutionContext with current ctx as parent
  - Updates call stack automatically
  - Invokes method
- `ctx.pass(args...)` - Call parent implementation
  - Finds parent object via `Object.getPrototypeOf(@_definer)`
  - Finds parent's CoreMethod for same method name
  - Creates ExecutionContext with parent definer
  - Preserves call stack
- Call stack tracked automatically through ExecutionContext parent chain

## Directory Structure

```
ClodRiver/
├── docs/
│   ├── 00-ObjectModel.md          # Current object model spec v4.0 (PRIMARY)
│   ├── 00-ProjectVision.md        # Project goals
│   ├── BIFs.md                    # Built-in functions documentation
│   ├── 01-Architecture.md         # Server/Core architecture (aspirational)
│   ├── 02-DesignDecisions.md      # Design rationale (aspirational)
│   ├── 03-ObjectModel.md          # Earlier iteration (superseded)
│   ├── 04-ObjectModel-Revised.md  # Earlier iteration (superseded)
│   └── 05-ObjectModel.md          # Earlier iteration (superseded)
├── lib/
│   ├── core.coffee                # Core class - object system management
│   ├── core-object.coffee         # CoreObject class - minimal object structure
│   ├── core-method.coffee         # CoreMethod class - method metadata and invocation
│   ├── execution-context.coffee   # ExecutionContext - method execution environment
│   ├── text-dump.coffee           # TextDump class - .clod format serialization
│   ├── compiler.coffee            # Compiler class - method source compilation
│   ├── bifs.coffee                # Built-in functions (BIFs)
│   └── errors.coffee              # Error classes
├── t/
│   ├── core.coffee                # Core tests
│   ├── core-object.coffee         # CoreObject tests
│   ├── core-method.coffee         # CoreMethod tests
│   ├── text-dump.coffee           # TextDump tests
│   ├── compiler.coffee            # Compiler tests
│   ├── persistence.coffee         # freeze/thaw tests
│   ├── load-core.coffee           # Core loading tests
│   └── bifs.coffee                # BIF tests
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

## Import Resolution

CoreMethod automatically resolves imports in this order:

1. **BIFs** - Check `core.bifs[name]`
   - Context-requiring BIFs are wrapped to auto-inject ctx:
     - Network: `listen`, `accept`, `emit`
     - Persistence: `textdump`
     - Core Loading: `load_core`, `core_toobj`, `core_call`, `core_destroy`
   - Other BIFs are passed as-is
2. **$name** - Check `core.objectNames` for objects starting with `$`
3. **ctx methods** - Check ExecutionContext for builtins
   - `cget`, `cset`, `cthis`, `definer`, `caller`, `sender`, `send`, `pass`
4. **null** - Unknown imports are passed as null

## TextDump and Compiler

### TextDump Class

`TextDump` handles conversion between Core state and `.clod` format strings:

```coffee
TextDump = require './lib/text-dump'

# Parse .clod format string
dump = TextDump.fromString source

# Capture from existing Core
dump = TextDump.fromCore core

# Apply to a Core (returns {oldId: newObj} map)
refs = dump.apply core

# Serialize to .clod format
str = dump.toString()
```

### Compiler Class

`Compiler` handles method source compilation:

```coffee
Compiler = require './lib/compiler'

# Compile method source to function
fn = Compiler.compileMethod source

# Get function with metadata
result = Compiler.compileMethod source, {returnMetadata: true}
# Returns: {fn, name, using, argsRaw, disallowOverrides, source}

# Parse without compiling
metadata = Compiler.parseMethodSource source
# Returns: {name, using, argsRaw, body, disallowOverrides}
```

## .clod File Format

The `.clod` format is used for persistent storage. Files contain object definitions, methods, and state data.

### Basic Structure

```coffee
object <id>           # Create object with explicit numeric ID
object $name          # Create new object with auto-ID, or switch to existing
parent <parent_id>    # Set parent by numeric ID
parent $name          # Set parent by name
name <object_name>    # Register name for current object
default_parent $name  # Set default parent for following new objects

method <method_name>
  using <import1>, <import2>
  args <arg1>, <arg2> = <default>

  <method body>

data
  <CoffeeScript expression returning state object>
```

### Extended Syntax Features

**`object $name`** - Either creates a new object or switches to an existing one:
```coffee
object $sys          # Creates new object with auto-ID, registers name 'sys'

object $root         # Creates new object with auto-ID, registers name 'root'

object $sys          # Switches back to existing $sys
parent $root         # Now sets $sys's parent to $root

method add_obj_name  # Adds method to $sys
  # ...
```

**`default_parent $name`** - Sets the default parent for all following new objects:
```coffee
object $root

default_parent $root

object $wizard       # Automatically inherits from $root

object $player       # Also inherits from $root
```

**`$name` in data sections** - Use names instead of numeric IDs:
```coffee
object $wizard
parent $root

data
  {
    $root: {name: 'wizard'}
    $wizard: {level: 10, xp: 0}
  }
```

### Data Blocks

Data blocks contain CoffeeScript that returns an object mapping namespace IDs to state data:

**Static data (from textdump):**
```coffee
object 2
name player

data
  {
    2:
      {
          name: 'Alice',
          level: 5,
          items: [{$ref: 10}, {$ref: 11}]
        }
  }
```

**Dynamic data (hand-written):**
```coffee
object 69
name player_db

data
  {send, toobj} = ctx
  $sys = toobj '$sys'

  passwd = send $sys, 'read_file', 'etc/passwd'
  shadow = send $sys, 'read_file', 'etc/shadow'

  db = send @, 'parse_db', {passwd, shadow}

  {
    1:  {name: 'player_db'}
    69: {db}
  }
```

### Textdump BIF

```coffee
# From $sys method
method save_world
  using textdump

  textdump 'world.clod'  # Path relative to db/
```

The `textdump` BIF is $sys-only and generates a complete .clod file with:
- All objects with their parent relationships and names
- All methods with their source code
- All state data as CoffeeScript object literals
- Object references serialized as `{$ref: id}`

### Loading .clod Files

```coffee
fs       = require 'node:fs'
TextDump = require './lib/text-dump'
Core     = require './lib/core'

source = fs.readFileSync 'db/world.clod', 'utf8'
dump   = TextDump.fromString source
core   = new Core()
refs   = dump.apply core

# refs maps old object IDs to new objects
# Namespace IDs in state are automatically remapped
```

## Modular Core Loading

The Core Loading BIFs enable loading .clod files into separate, isolated Core instances. This is useful for:
- **Modules**: Load a module .clod, call its exports, apply to main core
- **Packages**: Load/unload packages that add functionality
- **Isolation**: Run untrusted or experimental code in a separate Core

### Core Loading BIFs

- `load_core(path, holder)` - Load .clod file into new Core attached to holder
- `core_toobj(holder, name)` - Look up object by name in child Core
- `core_call(holder, obj, methodName, args...)` - Call method on child Core object
- `core_destroy(holder)` - Remove child Core from holder

### Usage Example

```coffee
core.addMethod $sys, 'load_module', (load_core, core_toobj, core_call, create, $root) ->
  (ctx, args) ->
    [path] = args

    # Create holder object for the child Core
    holder = create $root

    # Load the .clod file into a new Core
    load_core path, holder

    # Look up and call the module's exports method
    $module = core_toobj holder, '$module'
    exports = core_call holder, $module, 'exports'

    # Process exports (which are plain data, not foreign objects)
    for instruction in exports
      # Apply instruction to main core...

    holder  # Return holder for future queries
```

### Key Design Points

- **Foreign Objects Stay Foreign**: Objects from child Core are NOT integrated into parent Core. They keep their original IDs and can only be called via `core_call`, not `send`.
- **Data Crossing Boundary**: Plain values (strings, numbers, arrays, objects) pass through unchanged. CoreObject references remain "foreign objects".
- **Child Core Isolation**: Child Core has its own `$sys` and `$root`. No implicit cross-core references.
- **Non-Serializable**: `_childCore` is stored directly on holder object and not persisted through freeze/thaw.

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
    (cget, send) ->
      (ctx, args) ->
        [target] = args
        damage = cget 'damage'
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
- **Methods are CoreMethod instances** - Encapsulate function, metadata, and behavior
- **Methods declare imports** - Nested function pattern `(imports...) -> (ctx, args) -> body`
- **ExecutionContext manages execution** - Call stack, builtins, definer tracking
- **Fat arrow binding** - All ExecutionContext methods use `=>` for proper binding
- **Import resolution** - Automatic resolution of BIFs, $names, and ctx methods
- **Deep serialization** - Object references handled at any depth in state
- **Data blocks** - Executable CoffeeScript in .clod files for state initialization
- **Namespace remapping** - State namespaces mapped to new object IDs during textdump loading
- **No comments in code** - Self-documenting preferred

## Current Implementation Status

- ✅ package.json configured for CoffeeScript testing
- ✅ docs/00-ObjectModel.md - v4.0 specification (current)
- ✅ docs/BIFs.md - complete BIF documentation including textdump
- ✅ lib/core-object.coffee - CoreObject with deep serialization
- ✅ lib/core-method.coffee - CoreMethod with import resolution and invoke
- ✅ lib/execution-context.coffee - ExecutionContext with cget/cset/send/pass
- ✅ lib/core.coffee - Core with toobj, add_obj_name, method management
- ✅ lib/text-dump.coffee - TextDump with fromString/fromCore/apply/toString
- ✅ lib/compiler.coffee - Compiler with compileMethod/parseMethodSource
- ✅ lib/server.coffee - Server with data block loading and namespace remapping
- ✅ lib/bifs.coffee - All 19 BIFs implemented (including core loading)
- ✅ lib/errors.coffee - Error classes
- ✅ t/core-object.coffee - CoreObject tests passing
- ✅ t/core.coffee - Core tests passing
- ✅ t/core-method.coffee - CoreMethod tests passing
- ✅ t/text-dump.coffee - TextDump tests passing
- ✅ t/compiler.coffee - Compiler tests passing
- ✅ t/persistence.coffee - freeze/thaw tests passing
- ✅ t/load-core.coffee - Core loading tests passing
- ✅ t/bifs.coffee - BIF tests passing
- ✅ 134 tests passing

## Related Documentation

Primary docs (in order of importance):
1. `docs/00-ObjectModel.md` - Current object model v4.0 (PRIMARY)
2. `docs/BIFs.md` - Built-in functions reference
3. `docs/00-ProjectVision.md` - Project goals and philosophy
4. `docs/01-Architecture.md` - Server/Core two-tier architecture (aspirational)
5. `docs/02-DesignDecisions.md` - Design rationale (aspirational)

## Project Context

Part of ClodForest ecosystem:
- **ClodForest** - MCP server infrastructure
- **ClodRiver** - This MUD server
- **Agent Calico** - Multi-agent orchestration

ClodRiver revives ColdMUD's elegance with modern LLM integration for natural language parsing, dynamic world building, and intelligent NPCs.
