# Built-in Functions (BIFs)
# These are made available to methods through the import mechanism

CoffeeScript = require 'coffeescript'
CoreMethod   = require './core-method'
CoreObject   = require './core-object'
TextDump     = require './text-dump'

class BIFs
  constructor: (@core) ->

  # Core object management
  create: (parent) => @core.create parent

  destroy: (obj) => @core.destroy obj

  add_method: (obj, name, fn, source = null, flags = {}) =>
    @core.addMethod obj, name, fn, source, flags

  add_obj_name: (name, obj) =>
    @core.add_obj_name name, obj

  del_obj_name: (name) =>
    @core.del_obj_name name

  rm_method: (obj, name) =>
    @core.delMethod obj, name

  # Utility functions
  toint: (obj) =>
    obj?._id ? null

  toobj: (ref) =>
    @core.toobj ref

  tostr: (value) =>
    return String(value) unless value?._id?
    "##{value._id}"

  # XXX: possible scaling hotspot on large DBs?
  children: (ctx, obj = null) =>
    target = obj ? ctx.obj
    result = []

    for id, candidate of @core.objectIDs
      proto = Object.getPrototypeOf candidate
      result.push candidate if proto is target

    result

  parent: (ctx, obj = null) =>
    target = obj ? ctx.obj
    Object.getPrototypeOf target

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

  list_methods: (ctx, obj = null) =>
    # Handle direct call with CoreObject (e.g., from clod_eval)
    if ctx instanceof CoreObject
      target = ctx
    else
      target = obj ? ctx.obj
    result = []
    for name of target when target.hasOwnProperty(name) and target[name] instanceof CoreMethod
      result.push name
    result

  # Compilation
  compile: (code) =>
    jsCode = CoffeeScript.compile code, {bare: true}
    # Evaluate the compiled code to get the inner function
    innerFn = eval(jsCode)
    # Wrap in outer function (no imports) for nested pattern compatibility
    -> innerFn

  clod_eval: (code) =>
    ClodLang = require './clod-lang'

    # Use ClodLang to transform and compile
    # Note: ~id syntax replaces #id to avoid CoffeeScript comment conflict
    jsCode = ClodLang.compile code

    # Build list of imports and their values
    imports = ['toobj', '_dispatch']
    values = [
      ((ref) => @core.toobj ref),
      ((target, methodName, args...) =>
        if target instanceof CoreObject
          @core.call target, methodName, args
        else
          fn = target[methodName]
          throw new Error "No method #{methodName} on JS object" unless typeof fn is 'function'
          fn.apply target, args)
    ]

    # Auto-import BIFs that are used in the code
    for bifName in BIFs.bifNames()
      if (new RegExp("\\b#{bifName}\\b")).test jsCode
        imports.push bifName
        values.push @[bifName]

    # Create a wrapper function with imports as parameters
    wrapper = eval "(function(#{imports.join ', '}) { return #{jsCode}; })"
    wrapper.apply null, values

  # Child Core Management
  load_core: (ctx, filePath, childHolder) =>
    fs       = require 'node:fs'
    pathMod  = require 'node:path'
    Core     = require './core'

    # Load and parse the .clod file
    # Handle both absolute and relative paths
    fullPath = if pathMod.isAbsolute filePath
      filePath
    else
      pathMod.join process.cwd(), filePath
    source   = fs.readFileSync fullPath, 'utf8'
    filename = pathMod.basename fullPath
    dump     = TextDump.fromString source, filename

    # Create a new Core for the child
    childCore = new Core()
    dump.apply childCore

    # Store the child core on the holder for later access
    childHolder._childCore = childCore

    # Call accept_core on the holder to notify it (if method exists)
    @core.callIfExists childHolder, 'accept_core', []

    # Return the holder for chaining
    childHolder

  core_toobj: (ctx, ref) =>
    # Get the child core from the context's object's holder
    childCore = ctx.obj._childCore
    throw new Error "No child core found" unless childCore?
    childCore.toobj ref

  core_call: (ctx, obj, methodName, args...) =>
    childCore = ctx.obj._childCore
    throw new Error "No child core found" unless childCore?
    childCore.call obj, methodName, args

  # Persistence
  textdump: (ctx, relativePath) =>
    fs   = require 'node:fs'
    path = require 'node:path'

    $sys = @core.toobj '$sys'
    unless ctx.definer() is $sys
      throw new Error "textdump is only callable by $sys"

    dump = TextDump.fromCore @core
    content = dump.toString()

    fullPath = path.join process.cwd(), relativePath
    dirPath  = path.dirname fullPath

    fs.mkdirSync dirPath, {recursive: true} unless fs.existsSync dirPath
    fs.writeFileSync fullPath, content, 'utf8'

    fullPath

  # Network
  listen: (ctx, listener, options) =>
    # Enforce $sys-only
    $sys = @core.toobj '$sys'
    if ctx.obj isnt $sys
      throw new Error "listen() can only be called on $sys"

    net = require 'node:net'
    {port = 7777, addr = 'localhost'} = options

    server = net.createServer (socket) =>
      # Store pending socket on listener
      listener._pendingSocket = socket

      # Call listener.connected with socket info
      socketInfo = {
        remoteAddress: socket.remoteAddress
        remotePort:    socket.remotePort
      }
      @core.call listener, 'connected', [socketInfo]

    server.listen port, addr

    # Store server on listener (not in state - not serializable)
    listener._netServer = server

    listener

  accept: (ctx, connection) =>
    listener = ctx.obj

    # Check if caller has a pending socket (is a listener)
    unless listener._pendingSocket?
      throw new Error "accept() called on non-listener or no pending connection"

    socket = listener._pendingSocket
    delete listener._pendingSocket

    # Associate socket with connection object
    connection._socket = socket

    # Set up socket event handlers
    socket.on 'data', (buf) =>
      @core.callIfExists connection, 'received', [buf]

    socket.on 'close', =>
      @core.callIfExists connection, 'disconnected'

    socket.on 'error', (error) ->
      console.error "Socket error:", error

    # Call connection.connected
    @core.callIfExists connection, 'connected'

    connection

  emit: (ctx, data) =>
    connection = ctx.obj

    # Check if caller has an associated socket
    unless connection._socket?
      throw new Error "emit() called on non-connection object"

    connection._socket.write data

  emit_error: (ctx, data) =>
    connection = ctx.obj

    # Check if caller has stderr (stdio connection)
    unless connection._stderr?
      throw new Error "emit_error() called on non-stdio connection"

    connection._stderr.write data

  attach_stdio: (ctx, connection) =>
    $sys = @core.toobj '$sys'
    if ctx.obj isnt $sys
      throw new Error "attach_stdio() can only be called on $sys"

    connection._socket = process.stdout
    connection._stderr = process.stderr

    process.stdin.setEncoding 'utf8'
    process.stdin.on 'data', (data) =>
      @core.callIfExists connection, 'received', [Buffer.from(data)]

    process.stdin.on 'close', =>
      @core.callIfExists connection, 'disconnected'

    process.stdin.resume()

    @core.callIfExists connection, 'connected'

    connection

  # Node.js access ($sys only)
  require: (ctx, moduleName) =>
    $sys = @core.toobj '$sys'
    if ctx.obj isnt $sys
      throw new Error "require() can only be called on $sys"

    require moduleName

  core_destroy: (ctx, holder) =>
    delete holder._childCore
    holder

  # Get all BIF names
  @bifNames: ->
    [
      'create', 'destroy',
      'add_obj_name', 'del_obj_name',
      'toint', 'tostr',
      'children', 'parent',
      'add_method', 'rm_method', 'lookup_method', 'list_methods',
      'compile', 'clod_eval',
      'textdump',
      'listen', 'accept', 'emit', 'emit_error', 'attach_stdio',
      'require', 'load_core', 'core_toobj', 'core_call', 'core_destroy'
    ]

module.exports = BIFs
