# Built-In Functions (BIFs)

Built-in functions available to ClodMUD methods through the import mechanism.

## ExecutionContext Builtins

These are provided through ExecutionContext and can be imported in method definitions:

### State Access

- ✅ **`cget(key)`** - Read from definer's namespace on current object
  ```coffee
  cget: (key) =>
    @obj._state[@_definer._id]?[key]
  ```

- ✅ **`cset(data)`** - Write to definer's namespace on current object
  ```coffee
  cset: (data) =>
    @obj._state[@_definer._id] ?= {}
    Object.assign @obj._state[@_definer._id], data
    @obj
  ```

### ColdMUD Semantics

- ✅ **`cthis()`** - Get current object
  ```coffee
  cthis: => @obj
  ```

- ✅ **`definer()`** - Get object that defined current method
  ```coffee
  definer: => @_definer
  ```

- ✅ **`caller()`** - Get previous object in call stack
  ```coffee
  caller: => @parent?.obj or null
  ```

- ✅ **`sender()`** - Get previous definer in call stack
  ```coffee
  sender: => @parent?._definer or null
  ```

### Method Dispatch

- ✅ **`send(target, methodName, args...)`** - Invoke method on another object
  ```coffee
  send: (target, methodName, args...) =>
    method = @core._findMethod target, methodName
    throw new MethodNotFoundError(target._id, methodName) unless method?

    childCtx = new ExecutionContext @core, target, method, this
    method.invoke @core, target, childCtx, args
  ```

- ✅ **`pass(args...)`** - Call parent's implementation of current method
  ```coffee
  pass: (args...) =>
    parent = Object.getPrototypeOf @_definer
    throw new NoParentMethodError(@obj._id, @method.name) if parent is Object.prototype

    parentMethod = @core._findMethod parent, @method.name
    throw new NoParentMethodError(@obj._id, @method.name) unless parentMethod?

    parentCtx = new ExecutionContext @core, @obj, parentMethod, this
    parentMethod.invoke @core, @obj, parentCtx, args
  ```

### Object Imports

- ✅ **`$name` imports** - Import objects by name from `core.objectNames`
  ```coffee
  core.addMethod obj, 'test', ($sys, $root) ->
    (ctx, args) ->
      # $sys and $root are the actual objects
  ```

## Core BIFs

These are exposed from the Core class through `core.bifs`:

### Object Management

- ✅ **`create(parent)`** - Create new object
  ```coffee
  create: (parent) => @core.create parent
  ```

- ✅ **`add_method(obj, name, fn)`** - Add method to object
  ```coffee
  add_method: (obj, name, fn) => @core.addMethod obj, name, fn
  ```

- ✅ **`add_obj_name(name, obj)`** - Register object with name
  ```coffee
  add_obj_name: (name, obj) => @core.add_obj_name name, obj
  ```

- ✅ **`del_obj_name(name)`** - Remove name registration
  ```coffee
  del_obj_name: (name) => @core.del_obj_name name
  ```

- ✅ **`rm_method(obj, name)`** - Remove method from object
  ```coffee
  rm_method: (obj, name) => @core.delMethod obj, name
  ```

### Type Conversion

- ✅ **`toint(obj)`** - Get object's numeric ID
  ```coffee
  toint: (obj) => obj?._id ? null
  ```

- ✅ **`tostr(value)`** - Convert value to string
  ```coffee
  tostr: (value) =>
    return String(value) unless value?._id?
    "##{value._id}"
  ```

### Introspection

- ✅ **`children(obj)`** - Get list of direct child objects
  ```coffee
  children: (obj) =>
    result = []
    for id, candidate of @core.objectIDs
      proto = Object.getPrototypeOf candidate
      result.push candidate if proto is obj
    result
  ```

- ✅ **`lookup_method(obj, methodName)`** - Find method in prototype chain
  ```coffee
  lookup_method: (obj, methodName) =>
    current = obj
    while current? and current isnt Object.prototype
      if current[methodName] instanceof CoreMethod
        method = current[methodName]
        return {
          method:  method
          definer: method.definer
        }
      current = Object.getPrototypeOf current
    null
  ```

### Compilation

- ✅ **`compile(code)`** - Compile CoffeeScript string to function
  ```coffee
  compile: (code) =>
    jsCode = CoffeeScript.compile code, {bare: true}
    innerFn = eval(jsCode)
    -> innerFn  # Wrap in outer function for nested pattern
  ```

- ✅ **`clod_eval(code)`** - Evaluate CoffeeScript expression
  ```coffee
  clod_eval: (code) =>
    jsCode = CoffeeScript.compile code, {bare: true}
    eval(jsCode)
  ```

### Network I/O

- ✅ **`listen(ctx, listener, options)`** - Start TCP listener ($sys only)
  ```coffee
  listen: (ctx, listener, options) =>
    $sys = @core.toobj '$sys'
    throw new Error("listen() can only be called on $sys") if ctx.cthis() isnt $sys

    net = require 'node:net'
    {port = 7777, addr = 'localhost'} = options

    server = net.createServer (socket) =>
      listener._pendingSocket = socket
      socketInfo = {
        remoteAddress: socket.remoteAddress
        remotePort:    socket.remotePort
      }
      @core.callIfExists listener, 'connected', [socketInfo]

    server.listen port, addr
    listener._netServer = server
    listener
  ```

  Note: `listen` is auto-injected with ctx when imported.

- ✅ **`accept(ctx, connection)`** - Accept pending connection
  ```coffee
  accept: (ctx, connection) =>
    listener = ctx.cthis()
    unless listener._pendingSocket?
      throw new Error "accept() called on non-listener or no pending connection"

    socket = listener._pendingSocket
    delete listener._pendingSocket
    connection._socket = socket

    socket.on 'data', (buf) => @core.callIfExists connection, 'received', [buf]
    socket.on 'close', => @core.callIfExists connection, 'disconnected'
    socket.on 'error', (error) -> console.error "Socket error:", error

    @core.callIfExists connection, 'connected'
    connection
  ```

  Note: `accept` is auto-injected with ctx when imported.

- ✅ **`emit(ctx, data)`** - Send data to connection's socket
  ```coffee
  emit: (ctx, data) =>
    connection = ctx.cthis()
    unless connection._socket?
      throw new Error "emit() called on non-connection object"
    connection._socket.write data
  ```

  Note: `emit` is auto-injected with ctx when imported.

## Import Resolution

CoreMethod automatically resolves imports in this order:

1. **BIFs** - Check `core.bifs[name]`
   - Network BIFs (`listen`, `accept`, `emit`) are wrapped to auto-inject ctx
   - Other BIFs are passed as-is

2. **$name** - Check `core.objectNames` for objects starting with `$`

3. **ctx methods** - Check ExecutionContext for builtins
   - `cget`, `cset`, `cthis`, `definer`, `caller`, `sender`, `send`, `pass`

4. **null** - Unknown imports are passed as null

## Usage Examples

### Simple State Access

```coffee
core.addMethod $thing, 'get_name', (cget) ->
  (ctx, args) ->
    cget 'name'
```

### Object Creation

```coffee
core.addMethod $sys, 'create_user', (create, cset, $root) ->
  (ctx, args) ->
    [username] = args
    user = create $root
    cset {username: username, created: Date.now()}
    user
```

### Network Programming

```coffee
core.addMethod $listener, 'start', (listen) ->
  (ctx, args) ->
    listen ctx.cthis(), {port: 7777, addr: 'localhost'}

core.addMethod $connection, 'send_welcome', (emit) ->
  (ctx, args) ->
    emit "Welcome to ClodRiver!\n"
```

### Method Introspection

```coffee
core.addMethod $root, 'list_methods', (lookup_method) ->
  (ctx, args) ->
    methods = []
    for name in ['init', 'create', 'children']
      result = lookup_method ctx.cthis(), name
      if result?
        methods.push "#{name} (defined by ##{result.definer._id})"
    methods.join('\n')
```

## All Available BIFs

**Object Management:**
- `create`, `add_method`, `add_obj_name`, `del_obj_name`, `rm_method`

**Type Conversion:**
- `toint`, `tostr`

**Introspection:**
- `children`, `lookup_method`

**Compilation:**
- `compile`, `clod_eval`

**Network:**
- `listen`, `accept`, `emit`

**ExecutionContext:**
- `cget`, `cset`, `cthis`, `definer`, `caller`, `sender`, `send`, `pass`

**Object Imports:**
- Any `$name` from `core.objectNames`
