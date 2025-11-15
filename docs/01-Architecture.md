# Architecture Specification

**Version:** 1.0 (Pragmatic)  
**Last Updated:** November 2025

## Overview

ClodRiver uses a clean separation between server (system interface) and core (world logic). The server provides infrastructure while the core provides content and behavior.

```
┌─────────────────────────────────────────────────────────┐
│                    Server (Node.js)                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │ Network  │  │ Session  │  │  Object  │  │  Event  │ │
│  │  Layer   │─▶│ Manager  │─▶│ Registry │─▶│   Log   │ │
│  └──────────┘  └──────────┘  └──────────┘  └─────────┘ │
│         │                           │                    │
│         └───────────┬───────────────┘                    │
│                     │                                    │
│              ┌──────▼───────┐                            │
│              │   CoreAPI    │  ◀── Contract boundary     │
│              └──────┬───────┘                            │
└─────────────────────┼────────────────────────────────────┘
                      │
┌─────────────────────▼────────────────────────────────────┐
│                Core (CoffeeScript)                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │  $sys    │  │  $root   │  │  $thing  │  │ $player │ │
│  │   (#0)   │─▶│   (#1)   │─▶│          │  │         │ │
│  └──────────┘  └──────────┘  └──────────┘  └─────────┘ │
│                                                          │
│  All world logic, content, and behavior lives here       │
└──────────────────────────────────────────────────────────┘
```

## Server Components

### 1. Network Layer

**Responsibility:** Accept connections and manage raw I/O

```coffeescript
class TelnetServer
  constructor: (@port = 7777) ->
    @server = net.createServer @handleConnection
    
  handleConnection: (socket) =>
    session = new Session(socket)
    CoreAPI.handleNewConnection(session)
    
  start: -> @server.listen @port
  stop: -> @server.close()
```

**Protocols:**
- v1: Telnet only (simple, works with TinyFugue)
- v2: Add SSH (security)
- v3: Add HTTPS+WebSocket (modern clients)

**Rationale:** Start simple, add protocols as needed.

### 2. Session Management

**Responsibility:** Buffer input, manage player state, handle disconnections

```coffeescript
class Session
  constructor: (@socket) ->
    @buffer = ''
    @player = null
    @socket.on 'data', @handleData
    @socket.on 'close', @handleClose
    
  handleData: (data) =>
    @buffer += data.toString()
    while (line = @readLine())?
      @handleLine(line)
      
  handleLine: (line) ->
    if @player
      CoreAPI.handleInput(@player, line)
    else
      CoreAPI.handleLogin(this, line)
      
  emit: (text) -> 
    @socket.write(text)
    
  readLine: ->
    idx = @buffer.indexOf('\n')
    return null if idx is -1
    line = @buffer[0...idx].trim()
    @buffer = @buffer[idx+1..]
    line
    
  handleClose: =>
    CoreAPI.handleDisconnect(@player) if @player
```

**Login Protocol:**
```
Client: "login Robert myPassword"
Server: "Login failure." OR greeting data
```

**Rationale:** Single-line login is simple and can be enhanced by core later (challenge-response, etc.)

### 3. Object Registry

**Responsibility:** Manage object lifecycle, provide lookup by ID and name

```coffeescript
class ObjectRegistry
  constructor: ->
    @objects = new Map()          # id -> object
    @nameIndex = new Map()         # name -> id
    @nextId = 1
    
  create: (className, parent = null) ->
    id = @nextId++
    klass = CoreAPI.$[className]
    throw "Unknown class: #{className}" unless klass
    
    obj = new klass(id, parent)
    @objects.set(id, obj)
    
    # Log creation event
    eventLog.log {
      type: 'create'
      id: id
      class: className
      parent: parent?.id
      timestamp: Date.now()
    }
    
    obj
    
  get: (id) -> 
    @objects.get(id)
    
  destroy: (id) ->
    obj = @objects.get(id)
    return unless obj
    
    # Remove from indexes
    @objects.delete(id)
    @nameIndex.delete(obj.get('name')) if obj.get('name')
    
    # Log destruction
    eventLog.log {
      type: 'destroy'
      id: id
      timestamp: Date.now()
    }
    
  # Dollar-sign namespace (#0 manages this)
  setName: (id, name) ->
    @nameIndex.set(name, id)
    
  getByName: (name) ->
    id = @nameIndex.get(name)
    @get(id) if id
    
  resolve: (ref) ->
    if ref.startsWith('$')
      @getByName(ref.slice(1))
    else if ref.startsWith('#')
      @get(parseInt(ref.slice(1)))
    else
      null
```

**Bootstrap:**
```coffeescript
# Server creates minimal #0 and #1 on startup
$sys = registry.create('SystemObject', null)  # id=0
$root = registry.create('RootObject', null)    # id=1

# Then loads core modules which extend these
CoreAPI.loadCoreObject('./core/sys.coffee')
CoreAPI.loadCoreObject('./core/root.coffee')
```

### 4. Method Dispatcher

**Responsibility:** Execute object methods with ColdMUD-style context

```coffeescript
class MethodDispatcher
  execute: (obj, methodName, args) ->
    # Find method (walk prototype chain)
    definer = @findDefiner(obj, methodName)
    return null unless definer
    
    method = definer[methodName]
    return null unless method
    
    # Build context with ColdMUD semantics
    context = {
      player: args.player
      args: args.data
      _caller: args.caller
      _sender: args.sender
      
      # ColdMUD built-ins as functions
      this: -> obj
      definer: -> definer
      caller: -> context._caller
      sender: -> context._sender
    }
    
    # Execute with proper this binding
    try
      result = method.call(obj, context)
      result
    catch error
      @handleError(obj, methodName, error)
      
  findDefiner: (obj, methodName) ->
    current = obj
    while current
      return current if current[methodName]
      current = Object.getPrototypeOf(current)
    null
    
  handleError: (obj, methodName, error) ->
    console.error "Error in #{obj.id}.#{methodName}:", error
    eventLog.log {
      type: 'error'
      object: obj.id
      method: methodName
      error: error.message
      stack: error.stack
      timestamp: Date.now()
    }
```

**Why method dispatch matters:**
- Provides ColdMUD semantics (definer/caller/sender)
- Enables method replacement without object recreation
- Logs errors for debugging
- Foundation for v2 sandboxing

### 5. Event Log

**Responsibility:** Persist all database changes for replay and audit

```coffeescript
class EventLog
  constructor: (@filename = 'events.log') ->
    @stream = fs.createWriteStream(@filename, flags: 'a')
    @eventCount = 0
    @lastSnapshot = 0
    
  log: (event) ->
    event.seq = @eventCount++
    @stream.write(JSON.stringify(event) + '\n')
    
    # Periodic snapshots
    if @eventCount - @lastSnapshot > 10000
      @snapshot()
      
  snapshot: ->
    # Write current state to SQLite
    db = new sqlite3.Database('snapshot.db')
    
    # Serialize all objects
    for [id, obj] from registry.objects
      db.run '''
        INSERT OR REPLACE INTO objects 
        (id, class, parent, state) 
        VALUES (?, ?, ?, ?)
      ''', [
        id
        obj.constructor.name
        obj.parent?.id
        JSON.stringify(obj.serialize())
      ]
    
    @lastSnapshot = @eventCount
    
  replay: (registry) ->
    # Read events from log
    lines = fs.readFileSync(@filename, 'utf8').split('\n')
    
    for line in lines when line
      event = JSON.parse(line)
      @applyEvent(registry, event)
      
  applyEvent: (registry, event) ->
    switch event.type
      when 'create'
        registry.create(event.class, event.parent)
        
      when 'set'
        obj = registry.get(event.id)
        obj?.set(event.key, event.value, skipLog: true)
        
      when 'destroy'
        registry.destroy(event.id)
        
      when 'method'
        # Method definition changes (v2)
        obj = registry.get(event.id)
        obj?.defineMethod(event.name, event.code)
```

**Event Types:**
- `create` - Object creation
- `set` - Property change
- `destroy` - Object destruction
- `method` - Method definition (v2)
- `error` - Runtime errors
- `input` - User input (optional, for validation)
- `timer` - Timer events (optional)

**Replay Modes:**
- Fast: Apply database events only
- Slow: Re-run all code (v2, for validation)
- Validate: Compare DB events to code execution

### 6. Text Dump

**Responsibility:** Export objects as git-friendly CoffeeScript files

```coffeescript
class TextDump
  dump: (directory = './core/objects') ->
    fs.mkdirSync(directory, recursive: true)
    
    for [id, obj] from registry.objects
      @dumpObject(obj, directory)
      
  dumpObject: (obj, directory) ->
    path = "#{directory}/#{obj.id}.coffee"
    
    code = """
    # Object ##{obj.id}: #{obj.get('name') or 'unnamed'}
    # Class: #{obj.constructor.name}
    # Parent: ##{obj.parent?.id or 'none'}
    
    module.exports = (CoreAPI) ->
      CoreAPI.objectData({
        "\\##{obj.parent?.id or 1}": #{@serializeState(obj.parent)}
        "\\##{obj.id}": #{@serializeState(obj)}
      })
    """
    
    fs.writeFileSync(path, code)
    
  serializeState: (obj) ->
    return '{}' unless obj
    
    state = {}
    for [key, value] from obj._state
      state[key] = @serializeValue(value)
      
    JSON.stringify(state, null, 2)
    
  serializeValue: (value) ->
    if value?.id?  # Object reference
      {$ref: value.id}
    else
      value
      
  load: (directory) ->
    files = fs.readdirSync(directory)
    
    for file in files when file.endsWith('.coffee')
      objectDef = require("#{directory}/#{file}")
      objectDef(CoreAPI)
```

**Text dump format:**
```coffeescript
# objects/42.coffee
module.exports = (CoreAPI) ->
  CoreAPI.objectData({
    "#1": {
      name: 'player_Robert'
    }
    "#42": {
      name: 'Robert'
      gender: {$ref: 6}
      location: {$ref: 100}
      description: 'A thoughtful programmer'
    }
  })
```

**Benefits:**
- Git-friendly (one file per object)
- Readable and editable
- Preserves inheritance chain
- Easy to merge changes

## Core Components

### Base Object Classes

```coffeescript
# GameObject - base class for all objects
class GameObject
  constructor: (@id, @parent = null) ->
    @_state = new Map()
    
  get: (key) -> 
    @_state.get(key)
    
  set: (key, value, options = {}) -> 
    @_state.set(key, value)
    
    unless options.skipLog
      eventLog.log {
        type: 'set'
        id: @id
        key: key
        value: @serializeValue(value)
        timestamp: Date.now()
      }
      
  serialize: ->
    obj = {}
    for [key, value] from @_state
      obj[key] = @serializeValue(value)
    obj
    
  serializeValue: (value) ->
    if value?.id?
      {$ref: value.id}
    else
      value
```

### Core Module Structure

```coffeescript
# core/thing.coffee
module.exports = (CoreAPI, $sys, $root) ->
  class $thing extends $root
    constructor: (id, parent) ->
      super(id, parent)
      @set('description', '')
      @set('location', null)
      
    look: (ctx) ->
      desc = @get('description')
      CoreAPI.notify(ctx.player, desc)
      
    take: (ctx) ->
      player = ctx.player
      
      # Check if takeable
      return CoreAPI.notify(player, "You can't take that.") unless @canTake()
      
      # Move to player's inventory
      @set('location', player)
      CoreAPI.notify(player, "You take the #{@get('name')}.")
      
    canTake: ->
      !@get('fixed')
      
  # Register with system
  CoreAPI.call($sys, 'set_my_name', 'thing')
  
  # Return class
  $thing
```

## CoreAPI Contract

This is the complete interface between server and core.

```coffeescript
class CoreAPI
  # Object management
  @create: (className, parent) -> # Returns object
  @get: (id) ->                   # Returns object or null
  @destroy: (id) ->               # Destroys object
  
  # Method execution
  @call: (obj, methodName, args) -> # Returns method result
  
  # State access (used internally by GameObject)
  # Objects use @get/@set which call these
  
  # Communication
  @notify: (player, message) ->
  @broadcast: (room, message, options) ->
  
  # Queries
  @getLocation: (obj) ->
  @getContents: (obj) ->
  
  # Core module loading
  @loadCoreObject: (path) ->
  @registerDollar: (name, id) ->
  
  # Dollar-sign namespace
  @$: {}  # Contains $sys, $root, $thing, etc.
  
  # Session handling (delegated to core)
  @handleNewConnection: (session) ->
  @handleLogin: (session, line) ->
  @handleInput: (player, line) ->
  @handleDisconnect: (player) ->
```

## Object Model Details

### Inheritance

Uses JavaScript prototype chain naturally:

```coffeescript
$root = CoreAPI.$.$root
class $container extends $root
class $chest extends $container

# Method lookup walks prototype chain
chest = new $chest(100)
chest.look()  # Finds look() in $root
```

### State vs Methods

- **State:** Lives in `@_state` Map, serializable
- **Methods:** Live as class methods, not serialized

```coffeescript
class $player
  constructor: (id) ->
    super(id)
    # State
    @set('name', 'Anonymous')
    @set('location', null)
    
  # Method (not in state)
  look: (ctx) ->
    # implementation
```

### Object References

Always serialize as IDs, resolve on access:

```coffeescript
# Setting
@set('location', someRoom)  # Serializes as {$ref: 100}

# Getting
location = @get('location')  # Returns the actual object
```

## Data Flow Examples

### Player Login

```
1. Client connects → TelnetServer creates Session
2. Session → CoreAPI.handleNewConnection(session)
3. Core's $connection object created
4. Client sends "login Robert password"
5. Session → CoreAPI.handleLogin(session, line)
6. Core validates, creates/loads $player
7. Session.player = player object
8. Server sends greeting via CoreAPI.notify()
```

### Command Execution

```
1. Client sends "look sword"
2. Session → CoreAPI.handleInput(player, "look sword")
3. Core's verb system parses command
4. Core identifies target object (sword)
5. Core → CoreAPI.call(sword, 'look', {player})
6. MethodDispatcher executes sword.look(context)
7. Method calls CoreAPI.notify(player, description)
8. Server sends description via Session.emit()
```

### Object Creation

```
1. Core calls CoreAPI.create('$thing', parent)
2. Registry.create():
   - Assigns ID
   - Instantiates class
   - Logs 'create' event
   - Indexes object
3. Returns new object to core
4. Core can call methods on it
```

## Migration Path to v2

All v1 code written to make v2 easy:

**v1 Code:**
```coffeescript
@set('name', 'Robert')
desc = @get('description')
CoreAPI.call(obj, 'look', args)
```

**v2 Code (after transformation):**
```coffeescript
name = 'Robert'              # Syntactic sugar
desc = description           # Direct access
@look()                      # Natural method call
```

**How transformation works:**
1. Parse v1 CoffeeScript to AST
2. Transform API calls to sugar
3. Generate v2 CoffeeScript
4. All logic stays the same

This is feasible because v1 uses a clean API boundary.

## Performance Considerations

### Memory
- Each object: ~1-5KB (state + overhead)
- 10,000 objects: ~50MB
- Reasonable for modern systems

### Latency
- Method dispatch: <1ms
- Event logging: <1ms (async)
- Text dump: seconds (offline)
- Snapshot: 1-5s for 10k objects (background)

### Scalability
- Single server: 100-1000 concurrent users
- Event log: Gb of history before rotation
- Snapshots prevent replay from getting slow

## Error Handling

### Runtime Errors
```coffeescript
try
  result = method.call(obj, context)
catch error
  # Log to event log
  eventLog.log {type: 'error', ...}
  
  # Notify player
  CoreAPI.notify(context.player, "An error occurred.")
  
  # Don't crash server
```

### Invalid References
```coffeescript
obj = CoreAPI.get(999)
return unless obj  # Graceful handling
```

### Permissions (v2)
```coffeescript
canModify: (actor) ->
  actor.isWizard() or actor.id == @get('owner')
```

## Testing Strategy

### Unit Tests (Core without Server)
```coffeescript
MockCoreAPI = {
  notify: (player, msg) -> console.log(msg)
  # ... other methods
}

$thing = (require './core/thing')(MockCoreAPI)

describe '$thing', ->
  it 'has description', ->
    thing = new $thing(1)
    thing.set('description', 'test')
    expect(thing.get('description')).toBe('test')
```

### Integration Tests (Full Stack)
```coffeescript
server = new Server()
server.loadCore()

mockSocket = new MockSocket()
session = new Session(mockSocket)

session.receive("login test password\n")
expect(mockSocket.sent).toContain('Welcome')
```

## Summary

This architecture provides:
- ✅ Clean separation of concerns
- ✅ Hot-reloadable core code
- ✅ Git-friendly persistence
- ✅ Event sourcing for debugging
- ✅ ColdMUD-style semantics
- ✅ Clear path to v2 sandboxing
- ✅ Testable components
- ✅ Room for LLM integration

Next: Complete CoreAPI specification with all methods and parameters.
