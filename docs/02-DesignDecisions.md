# Design Decisions Log

**Purpose:** Record key decisions, their rationale, and alternatives considered.

---

## Network Protocol: Telnet First

**Decision:** Use telnet for v1, add SSH/HTTPS later

**Rationale:**
- Simplest to implement (`net.createServer()`)
- Works with TinyFugue (Robert's preferred client)
- Easy to test with basic `telnet localhost 7777`
- Transport is orthogonal to game logic
- Can add other protocols without changing core

**Alternatives Considered:**
- SSH: More secure but requires complex library or bridge
- HTTPS+HTML: Modern but hard to use in terminal
- All three at once: Over-engineering for v1

**Migration Path:** Network layer is isolated, adding protocols is straightforward.

---

## Sandboxing: Deferred to v2

**Decision:** No sandboxing in v1, plan for IPC-based sandboxing in v2

**Rationale:**
- v1 is single-user/trusted users only
- Clean CoreAPI boundary makes retrofit easy
- IPC provides real OS-level isolation
- Avoids rabbit holes (isolated-vm, QuickJS, etc.)
- Focus on novel features (LLM integration) not infrastructure

**How to Avoid Dependency:**
1. Always call core code through CoreAPI
2. Never let core access Node internals directly
3. All I/O goes through server-provided APIs

**v2 Approach:**
```coffeescript
# Per-user process with IPC
class UserProcess
  constructor: (@userId) ->
    @process = fork('./user-sandbox.js')
    
  executeMethod: (obj, method, context) ->
    @send({type: 'execute', obj, method, context})
    await @receive()
```

**Alternatives Considered:**
- isolated-vm: Incomplete, still allows resource exhaustion
- Worker threads: Can't prevent resource exhaustion without killing
- QuickJS: Huge rabbit hole to embed different engine
- Chroot jail: Heavy-weight, OS-specific

---

## Object Model: ES6 Classes with API Layer

**Decision:** Core objects are ES6 classes, state access goes through API

**Rationale:**
- Natural CoffeeScript syntax
- Use prototype chain for inheritance
- Can hot-reload methods (replace prototype)
- CoreAPI layer enables v2 transformation
- Testable without full server

**Why Not Pure ColdMUD Model in v1:**
- Would require reimplementing inheritance
- Would require custom property system
- Would require syntactic sugar transpiler
- Delays getting to LLM integration
- Can be added in v2 with transformation

**The Compromise:**
```coffeescript
# v1: Use ES6 naturally, access through API
class $thing extends $root
  look: (ctx) ->
    desc = @get('description')  # API call
    CoreAPI.notify(ctx.player, desc)

# v2: Transform to natural syntax
class $thing extends $root
  look: (ctx) ->
    desc = description  # Direct access
    :notify player, desc  # Built-in function
```

**Migration:**
All API calls (`@get`, `@set`, `CoreAPI.call`) are easily identified and transformed.

---

## State Storage: Map with Serialization

**Decision:** Instance state in `@_state` Map, serialized to JSON

**Rationale:**
- Separates state from methods
- Easy to serialize (just the Map)
- Can track changes for event log
- Object references handled specially (`{$ref: id}`)
- Clear what gets persisted vs what doesn't

**Why Not ES6 Properties:**
```coffeescript
# Bad: Can't distinguish state from methods
class Thing
  constructor: ->
    @name = 'thing'        # Is this state?
    @look = -> 'Looking'   # Or this?
    
# Good: Clear separation
class Thing
  constructor: ->
    @set('name', 'thing')  # State
  look: -> 'Looking'       # Method
```

**Serialization:**
```javascript
{
  id: 42,
  class: '$thing',
  state: {
    name: 'sword',
    location: {$ref: 100},  // Object reference
    weight: 5
  }
}
```

---

## Inheritance: JavaScript Prototypes

**Decision:** Use ES6 prototype chain, don't implement custom inheritance

**Rationale:**
- Leverage mature, debuggable technology
- Natural CoffeeScript `class X extends Y`
- Method lookup is built-in
- Can use all ES6 tools and debuggers
- v2 can add custom semantics on top

**ColdMUD Difference:**
ColdMUD has no distinction between class and instance. Every object is an instance that can be a parent. 

**Why We Don't Need This in v1:**
- ES6 classes work fine for game objects
- Can still have object-as-parent in v2
- Core defines classes, server instantiates them
- Prototype chain provides inheritance

**What We Preserve:**
- definer/caller/sender semantics (via MethodDispatcher)
- Method replacement without object recreation
- State is not inherited (only in `@_state`)

---

## Persistence: Event Sourcing + Snapshots

**Decision:** Log all changes, periodic SQLite snapshots, git-friendly text dumps

**Rationale:**
- **Event log:** Complete audit trail, can replay/fix exploits
- **Snapshots:** Fast startup, prevent unbounded replay
- **Text dumps:** Version control, readable, editable

**Three Storage Formats:**

1. **Event Log (runtime):**
```javascript
{type: 'create', id: 1, class: '$thing', timestamp: ...}
{type: 'set', id: 1, key: 'name', value: 'sword', timestamp: ...}
```

2. **Snapshot (fast startup):**
```sql
CREATE TABLE objects (
  id INTEGER PRIMARY KEY,
  class TEXT,
  parent INTEGER,
  state TEXT  -- JSON
);
```

3. **Text Dump (git):**
```coffeescript
# objects/42.coffee
module.exports = (CoreAPI) ->
  CoreAPI.objectData({
    "#42": {name: 'Robert', ...}
  })
```

**Boot Process:**
1. Load latest snapshot (if exists)
2. Replay events since snapshot
3. Continue logging new events
4. Text dump on demand (`@dump` command)

**Exploit Recovery:**
```bash
# Someone did: ;@player.wizard = 1
$ grep "wizard.*true" events.log
# Find the line, edit it to false
$ rm snapshot.db
$ node server.js --replay  # Rebuild from edited log
```

**Alternatives Considered:**
- JSON.stringify of world: Doesn't handle object references well
- Just SQLite: Not human-editable
- Just text dumps: Slow to load large worlds
- ColdMUD binary format: Not human-readable

---

## Login: Single-line Protocol

**Decision:** Client sends `login username password` in one line

**Rationale:**
- Simple to implement
- Works with basic telnet
- Core can enhance later (challenge-response, etc.)
- Server just passes to core for handling

**Protocol:**
```
Client: login Robert myPassword
Server: Login failure.

OR

Server: Welcome back, Robert!
Server: Last login: 2 hours ago
Server: You are in the Library.
```

**Core Handles:**
- Username/password validation
- Player object loading/creation  
- Welcome message generation
- Session setup

**Server Handles:**
- Buffering input until newline
- Creating Session object
- Passing to CoreAPI.handleLogin()

**Future Enhancement:**
Core can implement multi-step login, CAPTCHA, two-factor, etc. Server doesn't need to change.

---

## Dollar-Sign Namespace: #0 Manages

**Decision:** Object #0 ($sys) manages dollar-sign to ID mapping

**Rationale:**
- ColdMUD model: System object controls namespace
- Core defines access control policy
- Server just provides registry lookup
- Flexible: Core can implement any naming scheme

**How It Works:**
```coffeescript
# Core module registers itself
module.exports = (CoreAPI, $sys, $root) ->
  class $thing extends $root
    # ...
    
  # Calls $sys.set_my_name('thing')
  CoreAPI.call($sys, 'set_my_name', 'thing')
  
  $thing
```

**System Object:**
```coffeescript
class $sys
  constructor: ->
    @set('dollar_names', new Map())
    
  set_my_name: (ctx) ->
    name = ctx.args
    caller = ctx.caller()
    
    # Store mapping
    names = @get('dollar_names')
    names.set(name, caller.id)
    
    # Also set object's name property
    caller.set('name', name)
```

**Resolution:**
```coffeescript
CoreAPI.resolve('$thing')   # → object #5
CoreAPI.resolve('#5')       # → object #5
CoreAPI.$.$thing           # → class $thing
```

**Alternatives:**
- Server manages namespace: Less flexible, harder to customize
- Hardcoded mappings: Not extensible
- No namespace: Confusing IDs everywhere

---

## Method Dispatch: Context Object

**Decision:** Pass context object with ColdMUD semantics to methods

**Context Structure:**
```coffeescript
context = {
  player: playerObject      # Who initiated action
  args: 'parsed arguments'  # Method arguments
  _caller: callerObject     # Previous frame
  _sender: senderObject     # Previous definer
  
  # Built-in functions
  this: -> targetObject
  definer: -> definerObject
  caller: -> context._caller
  sender: -> context._sender
}
```

**Usage in Core:**
```coffeescript
class $thing
  take: (ctx) ->
    player = ctx.player
    this_obj = ctx.this()
    
    return CoreAPI.notify(player, "You can't take that.") unless @canTake()
    
    @set('location', player)
    CoreAPI.notify(player, "Taken.")
```

**Why Functions for this/definer/caller/sender:**
Matches ColdMUD semantics where these are built-in functions, not variables.

**Why Context Object:**
- Can add fields without breaking signatures
- Clear what's available to methods
- Easy to mock for testing
- Provides future extensibility

**Alternative Considered:**
```coffeescript
# Individual parameters
take: (player, args, caller, sender) ->
```
This breaks when adding new context fields.

---

## Verb System: Deferred to Core

**Decision:** Server provides raw input, core implements verb parsing/dispatch

**Rationale:**
- Core defines game commands
- LLM parser lives in core layer
- Server is just I/O and persistence
- Maximum flexibility for game design

**Server Role:**
```coffeescript
handleLine: (line) ->
  if @player
    CoreAPI.handleInput(@player, line)
  else
    CoreAPI.handleLogin(@session, line)
```

**Core Role:**
```coffeescript
# $player.handleInput or global verb handler
handleInput: (ctx) ->
  line = ctx.args
  
  # Parse command (could use LLM here)
  {verb, target, args} = parseCommand(line)
  
  # Find target object
  obj = findObject(target, ctx.this())
  
  # Execute verb
  CoreAPI.call(obj, verb, {player: ctx.this(), args})
```

**Benefits:**
- LLM integration happens in core
- Natural language parsing in core
- Verb aliasing in core
- Game-specific commands in core
- Server knows nothing about game rules

---

## Testing: Two-Tier Strategy

**Decision:** Unit tests for core (mock CoreAPI), integration tests for full stack

**Unit Tests:**
```coffeescript
# test/thing.test.coffee
MockCoreAPI = {
  notify: sinon.stub()
  call: sinon.stub()
}

$thing = (require '../core/thing')(MockCoreAPI)

describe '$thing', ->
  it 'can be taken', ->
    thing = new $thing(1)
    ctx = {player: mockPlayer, args: null}
    thing.take(ctx)
    expect(MockCoreAPI.notify).called
```

**Integration Tests:**
```coffeescript
# test/integration.test.coffee
describe 'Login flow', ->
  beforeEach ->
    @server = new Server()
    @server.loadCore()
    @client = new MockClient()
    
  it 'accepts valid login', ->
    @client.send("login test password\n")
    expect(@client.received).toMatch(/Welcome/)
```

**Why Two Tiers:**
- Unit tests are fast, focused on logic
- Integration tests catch wiring issues
- Both are needed for confidence

**What We Test:**
- Core objects: Logic, state management
- Server components: Network, persistence
- Integration: Full command flow

---

## CoffeeScript: Official Language

**Decision:** Use CoffeeScript for all core and server code

**Rationale:**
- Readable class syntax
- `@` sugar for `this.`
- Implicit returns
- Significant whitespace
- Compiles to readable ES6
- Robert prefers it
- Good for MUD code (similar to Ruby)

**Example:**
```coffeescript
# CoffeeScript
class $player extends $root
  look: (ctx) ->
    location = @get('location')
    desc = location.describe(ctx.this())
    CoreAPI.notify ctx.player, desc

# Compiles to readable JS
class $player extends $root {
  look(ctx) {
    const location = this.get('location');
    const desc = location.describe(ctx.this());
    return CoreAPI.notify(ctx.player, desc);
  }
}
```

**Alternative Considered:**
- Pure JavaScript: More mainstream but verbose
- TypeScript: Type safety but added complexity for v1

**Migration Path:**
v2 can add type definitions without changing syntax.

---

## Hot Reload: Replace Prototypes

**Decision:** Reload core modules by replacing prototype methods

**Implementation:**
```coffeescript
# Server command: @reload thing
reload: (className) ->
  # Clear require cache
  modulePath = "./core/#{className}.coffee"
  delete require.cache[require.resolve(modulePath)]
  
  # Reload module
  newClass = require(modulePath)(CoreAPI)
  
  # Replace methods on existing class
  oldClass = CoreAPI.$[className]
  for key, value of newClass.prototype
    oldClass.prototype[key] = value
    
  # Existing instances now use new methods!
```

**Why This Works:**
- JS prototype chain is live
- All instances share the prototype
- Changing prototype affects all instances
- State (in `@_state`) is untouched

**What Gets Updated:**
- Method implementations
- Method signatures
- New methods added

**What Doesn't:**
- Existing object state
- Object IDs
- References to objects
- Constructor (instances already created)

**Limitation:**
Can't change constructor or class structure. For that, need full rebuild (v2 feature).

---

## Module Format: Function with CoreAPI

**Decision:** Core modules export function that receives CoreAPI

**Format:**
```coffeescript
# core/thing.coffee
module.exports = (CoreAPI, $sys, $root) ->
  class $thing extends $root
    # Implementation
    
  # Self-registration
  CoreAPI.call($sys, 'set_my_name', 'thing')
  
  # Return class
  $thing
```

**Why:**
- Explicit dependencies ($sys, $root)
- CoreAPI is injected (easy to mock)
- Self-registration keeps server simple
- Testable (pass mock CoreAPI)
- Clear initialization order

**Loading:**
```coffeescript
CoreAPI.loadCoreObject('./core/sys.coffee')
CoreAPI.loadCoreObject('./core/root.coffee')  
CoreAPI.loadCoreObject('./core/thing.coffee')
```

**Bootstrap:**
Server creates minimal #0 and #1, then core modules can extend them.

---

## Summary

These decisions form a coherent architecture:
- Pragmatic v1 that ships quickly
- Clean boundaries for v2 transformation
- Leverage ES6 where helpful
- Defer complexity where possible
- Keep focus on novel features (LLM integration)

Next steps:
1. Complete CoreAPI specification
2. Define bootstrap sequence
3. Specify minimal core objects
4. Begin implementation
