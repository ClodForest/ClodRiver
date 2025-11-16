# Object Model Specification

**Version:** 1.0  
**Date:** November 2025  
**Status:** Specified

---

## Core Principles

### Class-Per-Instance (Pattern A)

Every object gets its own unique ES6 class. This makes all objects equivalent - any object can be a parent of another object, just like ColdMUD.

```coffeescript
# Loading a module creates a class definition
$sword = loadFromModule('./core/sword')  # Defines $sword class

# Creating an instance makes a NEW class extending $sword
excalibur = CoreAPI.create($sword)  # Creates $sword_42 extends $sword

# excalibur can itself be a parent
legendary = CoreAPI.create(excalibur.constructor)  # Creates class extending $sword_42
```

### No State Inheritance

State is **never** inherited. Each instance has its own `@_state` map, namespaced by the class that defined each property.

**Why:** Enforces open/closed principle. Prevents children from snooping on parents. Prevents surprises when intermediate object state changes.

```coffeescript
# If $sword has no $thing.displayName entry, it was never set
mySword.get($thing, 'displayName')  # undefined

# State is per-class-namespace, per-instance
mySword.get($RPG_weapon, 'damage')  # $RPG.diceExpr('d6')
mySword.get($thing, 'damage')       # undefined - not in $thing's namespace
```

**If inherited state is desired:** Implement it explicitly in the class by checking parent objects and using a sentinel value to indicate "use parent's value."

### Method Inheritance via Prototype Chain

Methods ARE inherited naturally via ES6 prototype chain. Changing a parent's method immediately affects all children.

```coffeescript
# Change parent method
$thing.prototype.description = (ctx, args) ->
  "You see #{@get($thing, 'name')} - it looks ordinary."

# ALL children immediately use new implementation
excalibur.description(ctx, [])  # Uses new $thing.description

# Override in child class
$legendary_sword.prototype.description = (ctx, args) ->
  "#{@get($thing, 'name')} glows with ethereal power!"
```

---

## CoreObject Definition

Every object inherits from CoreObject, which provides the foundation:

```coffeescript
class CoreObject
  constructor: (@_id) ->
    @_state = {}  # Namespace: classId -> {key: value}
    
  id: -> @_id
  
  get: (klass, key) ->
    @_state[klass.id()]?[key]
    
  set: (klass, props) ->
    @_state[klass.id()] ?= {}
    for key, value of props
      @_state[klass.id()][key] = value
      CoreAPI.logEvent({
        type: 'set'
        id: @id()
        class: klass.id()
        key: key
        value: CoreAPI.serializeValue(value)
        timestamp: Date.now()
      })
    @
    
  call: (method, ...args) ->
    # v1: Simplified dispatch, no caller/sender tracking
    ctx = {player: getCurrentPlayer()}
    @[method](ctx, args)
```

### Reserved Names

Objects MUST NOT define methods or properties with these names:
- `_id` - Integer object number
- `_state` - Per-class property storage  
- `id()` - Object number getter
- `get(klass, key)` - State access
- `set(klass, props)` - State mutation
- `call(method, ...args)` - Method invocation

### Method Signature

All methods follow this signature:

```coffeescript
methodName: (ctx, args) ->
  # ctx: Context object (minimal in v1, just {player})
  # args: Array of arguments
  
  [argOne, argTwo] = args
  # Method implementation
```

**Rationale:** Uniform signature makes serialization simpler, matches ColdMUD style, defers caller/sender/definer tracking to v2.

---

## Object References in State

Object references are serialized with special handling to avoid conflicts with user data.

### Serialization

```coffeescript
serializeValue: (value) ->
  if CoreAPI.isCoreRef(value)
    {$ref: value.id()}
  else if value?.$ref
    {$ref: false, value}
  else
    value
```

### Deserialization  

```coffeescript
deserializeValue: (value) ->
  if value?.$ref?
    if value.value?
      value.value
    else
      CoreAPI.toObjectRef(value.$ref)
  else
    value
```

### Cases Handled

```coffeescript
# Case 1: Actual object reference
obj42 → {$ref: 42}

# Case 2: User data with $ref key
{$ref: "user data"} → {$ref: false, value: {$ref: "user data"}}

# Case 3: Normal data  
{foo: "bar"} → {foo: "bar"}
```

---

## CoreAPI Specification

### Object Lifecycle

```coffeescript
class CoreAPI
  constructor: ->
    @objects = new Map()  # id -> object
    @nextId = 2  # #0 and #1 are bootstrap
    @$sys = null  # Set during bootstrap
    @$root = null # Set during bootstrap
    
  create: (parentClass = CoreObject) ->
    # Allocate next ID
    id = @nextId++
    
    # Create instance-specific class
    instanceClass = class extends parentClass
      constructor: -> super(id)
    
    # Instantiate
    obj = new instanceClass()
    
    # Register
    @objects.set(id, obj)
    
    # Log event
    @logEvent({
      type: 'create'
      id: id
      class: parentClass.name
      parent: Object.getPrototypeOf(parentClass.prototype)?.constructor?.name
      timestamp: Date.now()
    })
    
    obj
    
  destroy: (obj) ->
    id = obj.id()
    @objects.delete(id)
    @logEvent({type: 'destroy', id, timestamp: Date.now()})
    
  getObject: (id) ->
    @objects.get(id)
    
  isCoreRef: (value) ->
    value?.constructor?.prototype instanceof CoreObject
    
  toObjectRef: (id) ->
    obj = @getObject(id)
    throw new Error("Object ##{id} not found") unless obj
    obj
```

### Module Loading

```coffeescript
loadFromModule: (path, parentClass = CoreObject) ->
  # Clear require cache for hot reload
  delete require.cache[require.resolve(path)]
  
  # Load module - returns class definition
  mod = require(path)
  newClass = mod(@, @$sys, @$root)
  
  # Create instance with class-per-instance pattern
  id = @nextId++
  instanceClass = class extends newClass
    constructor: -> super(id)
  
  instance = new instanceClass()
  
  # Register
  @objects.set(id, instance)
  
  # Log
  @logEvent({
    type: 'create'
    id: id
    class: newClass.name
    parent: Object.getPrototypeOf(newClass.prototype)?.constructor?.name
    timestamp: Date.now()
  })
  
  instance
```

### Serialization

```coffeescript
serializeObject: (obj) ->
  # Get all methods from prototype chain
  methods = {}
  proto = obj.constructor.prototype
  
  while proto != CoreObject.prototype
    for name in Object.getOwnPropertyNames(proto)
      continue if name == 'constructor'
      continue if methods[name]?  # Don't override child methods
      
      method = proto[name]
      if typeof method == 'function'
        methods[name] = method.toString()
    
    proto = Object.getPrototypeOf(proto)
  
  {
    id: obj.id()
    class: obj.constructor.name
    parent: Object.getPrototypeOf(obj.constructor.prototype).constructor.name
    state: JSON.stringify(obj._state, (k, v) => @serializeValue(v))
    methods: methods
  }

deserializeObject: (data) ->
  # Get parent class
  parentClass = @objects.get(data.parent)?.constructor or CoreObject
  
  # Create class with methods
  objClass = class extends parentClass
    constructor: -> super(data.id)
  
  # Add methods to prototype
  for name, code of data.methods
    objClass.prototype[name] = eval("(#{code})")
  
  # Create instance
  obj = new objClass()
  obj._state = JSON.parse(data.state, (k, v) => @deserializeValue(v))
  
  @objects.set(data.id, obj)
  obj
```

---

## Event Logging

All world-mutating operations are logged for replay/recovery:

```coffeescript
# Object lifecycle
{type: 'create', id, class, parent, timestamp}
{type: 'destroy', id, timestamp}

# State changes  
{type: 'set', id, class, key, value, timestamp}

# Methods (v2)
{type: 'add_method', id, method, code, timestamp}
{type: 'del_method', id, method, timestamp}

# Naming
{type: 'set_obj_name', id, name, timestamp}
{type: 'del_obj_name', name, timestamp}
```

Events are written to `events.log` and can be replayed to rebuild world state.

---

## Bootstrap Sequence

```coffeescript
class MudServer
  bootstrap: ->
    # Create CoreAPI
    @coreAPI = new CoreAPI()
    
    # Create blank #0 and #1
    @coreAPI.nextId = 0
    $sys = new CoreObject(0)
    @coreAPI.objects.set(0, $sys)
    
    @coreAPI.nextId = 1
    $root = new CoreObject(1)
    @coreAPI.objects.set(1, $root)
    
    # Make $sys child of $root
    Object.setPrototypeOf($sys, $root)
    
    # Store for global access
    @coreAPI.$sys = $sys
    @coreAPI.$root = $root
    
    # Load $root module - binds methods to #1's prototype
    rootModule = require('./core/root')
    rootModule.call($root, @coreAPI)
    
    # Load $sys module - binds methods to #0's prototype  
    sysModule = require('./core/sys')
    sysModule.call($sys, @coreAPI)
    
    # Load rest of core - creates new objects
    for file in findCoreFiles('./core/lib')
      @coreAPI.loadFromModule(file)
    
    # Post-bootstrap initialization
    $sys.startup()
```

### Module Format

All core modules export a function that receives CoreAPI and returns a class:

```coffeescript
# core/thing.coffee
module.exports = (CoreAPI, $sys, $root) ->
  class $thing extends $root
    constructor: ->
      super arguments...
      
      @set $root,
        name: 'thing'
        
      @set $thing,
        displayName: 'a generic thing'
        description: 'You see nothing special.'
    
    look: (ctx, args) ->
      desc = @get($thing, 'description')
      CoreAPI.notify(ctx.player, desc)
  
  # Return class for instantiation
  $thing
```

---

## System BIFs ($sys-only)

These functions are only available in CoreAPI passed to `sys.coffee`:

```coffeescript
# Object lifecycle
create: (parent) -> # Returns new object
destroy: (obj) -> # Removes from world

# Naming
set_obj_name: (obj, name) -> # $sys.dollar_names.set(name, obj.id())
del_obj_name: (name) -> # $sys.dollar_names.delete(name)
lookup_obj_name: (name) -> # $sys.dollar_names.get(name)
all_obj_names: -> # Array.from($sys.dollar_names.keys())

# Network
create_server: (serverObj, port, opts) -> # Network listener
connect: (clientObj, addr, port) -> # Outbound connection
```

Multiple names can point to same object:
```coffeescript
set_obj_name(excalibur, 'excalibur')
set_obj_name(excalibur, 'legendary_sword')
set_obj_name(excalibur, 'arthurs_blade')
# All three names resolve to same object
```

---

## Root BIFs ($root-only)

These functions are only available in CoreAPI passed to `root.coffee`:

```coffeescript
# Method management (v2)
add_method: (name, code) -> # Add method to object
del_method: (name) -> # Remove method from object
```

For v1, methods are defined in module files. Dynamic method addition deferred to v2.

---

## Deferred to v2

These ColdMUD features are not implemented in v1:

1. **Caller/Sender/Definer tracking** - Security boundary enforcement
2. **Dynamic method addition** - `add_method()/del_method()` 
3. **Multiple inheritance** - Single inheritance via prototype chain only
4. **Disallow overrides** - Method finalization for security
5. **Per-instance methods** - Methods live on prototype only
6. **Permissions system** - No admin/wizard checks

**Rationale:** v1 focuses on getting LLM integration working. These features add complexity without providing immediate value for single-user development.

**Migration Path:** All state access goes through `@get/@set`, all method calls can go through `CoreAPI.call()` when we need tracking. The boundaries are clean for v2 transformation.

---

## Example Object Definition

```coffeescript
# core/sword.coffee
module.exports = (CoreAPI, $sys, $root) ->
  $thing = CoreAPI.lookup_obj_name('thing')
  $weapon = CoreAPI.lookup_obj_name('weapon')
  
  class $sword extends $weapon
    constructor: ->
      super arguments...
      
      @set $thing,
        displayName: 'a sword'
        
      @set $weapon,
        damage: {dice: '1d6', bonus: 0}
        
      @set $sword,
        blade_length: 30  # inches
        
    swing: (ctx, args) ->
      [target] = args
      damage = @get($weapon, 'damage')
      
      # Attack logic here
      roll = CoreAPI.rollDice(damage.dice)
      total = roll + damage.bonus
      
      CoreAPI.call(target, 'takeDamage', ctx, [total])
      
  $sword
```

---

## Summary

The object model balances:
- **ColdMUD semantics** - Class-per-instance, no state inheritance
- **ES6 pragmatism** - Use prototype chain naturally
- **v2 migration** - Clean boundaries via CoreAPI
- **Simplicity** - Defer complexity to v2

Every object is equivalent. Any object can be a parent. State is private per-class-namespace. Methods are inherited and can be hot-reloaded.

This gives us the power of ColdMUD's model while shipping v1 quickly.
