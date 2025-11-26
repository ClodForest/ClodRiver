# Built-In Functions (BIFs)

Status of built-in functions needed by core.clod.

## Already Available via ExecutionContext

These are provided through the import mechanism in method definitions:

- ✅ `get(key)` - Read from definer's namespace
- ✅ `set(data)` - Write to definer's namespace
- ✅ `send(target, method, ...args)` - Method dispatch
- ✅ `this()` - Get current object (also available as `@`)
- ✅ `definer()` - Get definer object
- ✅ `caller()` - Get calling object
- ✅ `sender()` - Get sender object
- ✅ `$name` imports - Object lookup by name (e.g., `$sys`, `$root`)

## Need Core API Exposure

These exist in Core but need to be exposed as importable BIFs:

- ✅ `create(parent)` - Core.create
- ✅ `add_method(obj, name, fn)` - Core.addMethod
- ✅ `add_obj_name(name, obj)` - Core.add_obj_name
- ✅ `del_obj_name(name)` - Core.del_obj_name
- ❌ `rm_method(obj, name)` - Core.delMethod (but called `rm_method` in core.clod)

## Need Implementation

### Compilation BIFs

- ❌ `compile(code)` - Compile CoffeeScript string to function
  - Used in: `root.eval_on:68`
  - Should return a function that can be added as a method
  - Function should be compilable by CoffeeScript.compile

- ❌ `clod_eval(code)` - Evaluate CoffeeScript with null context
  - Used in: `admin.receive_line:189`
  - Evaluates code as if definer and this were both null
  - Used for REPL-style interaction

### Network BIFs

- ❌ `listen(listenerObj, {port, addr})` - Start TCP listener
  - Used in: `sys.spawn_listener:58`
  - Should bind to port/addr
  - Call listenerObj's methods when connections arrive
  - Store server handle in listenerObj's state

- ❌ `emit(data)` - Send data to socket
  - Used in: `connection.emit:179`, `admin.notify:197`
  - Should write to the socket associated with connection object
  - Need to store socket reference in connection's state

### Introspection BIFs

- ❌ `toint(obj)` - Get object's numeric ID
  - Used in: `root.init:121`, `root.root_name:145`
  - Returns obj._id

- ❌ `tostr(value)` - Convert value to string
  - Used in: `admin.receive_line:190`
  - Smart stringification (handle objects, functions, etc.)

- ❌ `children()` - Get list of child objects
  - Used in: `root.children:89`, `root.descendents:95`
  - Returns array of objects that have this as parent
  - Requires walking objectIDs and checking prototypes

- ❌ `lookup_method(methodName, startAncestor)` - Find method in chain
  - Used in: `root.lookup_method:102`, `root.init:117`
  - Walk prototype chain from startAncestor looking for method
  - Return {method, definer} or null

## Implementation Priority

1. **Core API exposure** - Wire up existing Core methods (create, add_method, etc.)
2. **Basic utilities** - toint, tostr (simple to implement)
3. **Introspection** - children, lookup_method (need Core traversal)
4. **Compilation** - compile, clod_eval (need CoffeeScript integration)
5. **Network** - listen, emit (need Server integration, socket management)

## Notes

- BIFs are made available through the import mechanism in method definitions
- The `using` clause declares which BIFs a method needs
- ExecutionContext provides these via the nested function pattern
- Network BIFs will need tight integration with Server.coffee
