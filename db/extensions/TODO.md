# Minimal Core TODO

## Issues to Resolve

### 1. Connection Reference in $admin
**Problem**: `$admin.notify()` needs to get its connection via `get 'connection'`, but how does the connection get stored?

**Options**:
- A. Store during $connection.spawn: new connection sets itself as $admin's connection
- B. Pass as parameter: $connection.data passes itself to $admin.receive_line
- C. Use sender(): $admin can get sender() to find calling connection

**Current approach**: Uses `get 'connection'`, so needs to be set during spawn/init

### 2. Buffer Constructor
**Problem**: Using `new Buffer` which is deprecated in Node.js

**Fix needed**: Change to `Buffer.alloc(0)` or `Buffer.from('')`

### 3. BIFs to Implement

**Core management**:
- `create(parent)` - Wrapper for core.create
- `add_obj_name(name, obj)` - Wrapper for core.add_obj_name
- `del_obj_name(name)` - Wrapper for core.del_obj_name

**Method resolution**:
- `lookup_method(methodName, starting_ancestor)` - Find method in prototype chain

**Type conversion**:
- `toint(obj)` - Convert to integer or get object ID
- `stringify(value)` - JSON.stringify wrapper

**Context builtins**:
- `sender()` - Get calling object's definer

**Network**:
- `listen(connection, {port, addr})` - Start listening on port
- `emit(data)` - Send data to network client

**Code evaluation**:
- `eval(code)` - Evaluate CoffeeScript with core and ctx in scope

### 4. @ Binding
**Status**: Parser doesn't yet transform `@` to `ctx.this()`

**Needed**:
- Transform `@` in method bodies to use ctx.this()
- Handle `@property` and `@method()` syntax
- Distinguish from JavaScript method calls like `(new Buffer).toString()`

### 5. Method Indentation
**Issue**: Body lines need proper indentation handling for nested structures (loops, conditionals)

**Current**: Just prepends 4 spaces to all body lines
**Needed**: Smart indentation that preserves CoffeeScript structure

## Next Steps

1. Implement basic BIFs in `lib/builtins.coffee`
2. Update compiler to handle `@` binding
3. Fix Buffer constructor usage
4. Create bootstrap script to load and execute core
5. Test basic object creation and method calling
