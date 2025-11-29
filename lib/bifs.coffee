# Built-in Functions (BIFs)
# These are made available to methods through the import mechanism

CoffeeScript = require 'coffeescript'
CoreMethod   = require './core-method'
TextDump     = require './text-dump'

class BIFs
  constructor: (@core) ->

  # Core object management
  create: (parent) =>
    @core.create parent

  add_method: (obj, name, fn) =>
    @core.addMethod obj, name, fn

  add_obj_name: (name, obj) =>
    @core.add_obj_name name, obj

  del_obj_name: (name) =>
    @core.del_obj_name name

  rm_method: (obj, name) =>
    @core.delMethod obj, name

  # Utility functions
  toint: (obj) =>
    obj?._id ? null

  tostr: (value) =>
    return String(value) unless value?._id?
    "##{value._id}"

  # Introspection
  children: (obj) =>
    result = []
    for id, candidate of @core.objectIDs
      proto = Object.getPrototypeOf candidate
      result.push candidate if proto is obj
    result

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

  # Compilation
  compile: (code) =>
    jsCode = CoffeeScript.compile code, {bare: true}
    # Evaluate the compiled code to get the inner function
    innerFn = eval(jsCode)
    # Wrap in outer function (no imports) for nested pattern compatibility
    -> innerFn

  clod_eval: (code) =>
    jsCode = CoffeeScript.compile code, {bare: true}
    # Use eval directly to execute and return the result
    eval(jsCode)

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
    if ctx.cthis() isnt $sys
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
    listener = ctx.cthis()

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
    connection = ctx.cthis()

    # Check if caller has an associated socket
    unless connection._socket?
      throw new Error "emit() called on non-connection object"

    connection._socket.write data

  # Get all BIF names
  @bifNames: ->
    [
      'create', 'add_method', 'add_obj_name', 'del_obj_name', 'rm_method',
      'toint', 'tostr',
      'children', 'lookup_method',
      'compile', 'clod_eval',
      'textdump',
      'listen', 'accept', 'emit'
    ]

module.exports = BIFs
