net        = require 'node:net'
fs         = require 'node:fs'
CoffeeScript = require 'coffeescript'

Core       = require './core'
Compiler   = require './compiler'

class Server
  constructor: ->
    @core     = new Core()
    @compiler = new Compiler @core
    @server   = null

  loadCore: (corePath) ->
    source = fs.readFileSync corePath, 'utf8'

    @compiler.compile source
    operations = @compiler.getOperations()

    objRefs = {}

    for op in operations
      try
        switch op.type
          when 'create_object'
            parent = if op.parent? then objRefs[op.parent] else null
            obj = @core.create parent, op.name
            objRefs[op.id] = obj
            @core.objectIDs[op.id] = obj

          when 'add_method'
            obj = objRefs[op.objectId]
            unless obj?
              throw new Error "Object #{op.objectId} not found"

            flags = if op.disallowOverrides then {disallowOverrides: true} else {}
            @core.addMethod obj, op.methodName, op.fn, op.source, flags

          else
            throw new Error "Unknown operation type: #{op.type}"

      catch error
        console.error "\nError at line #{op.lineNum} in #{corePath}:"
        console.error "  Operation: #{op.type}"
        if op.type is 'create_object'
          console.error "  Object: ##{op.id} (#{op.name or 'unnamed'})"
        else if op.type is 'add_method'
          console.error "  Method: ##{op.objectId}.#{op.methodName}"
        console.error "  Error: #{error.message}"
        console.error ""
        throw error

    @core

  start: (port = 7777, addr = 'localhost') ->
    @server = net.createServer (socket) =>
      @handleConnection socket

    @server.listen port, addr, =>
      console.log "ClodRiver listening on #{addr}:#{port}"

  handleConnection: (socket) ->
    $connection = @core.toobj '$connection'
    unless $connection?
      socket.end "Server error: $connection not found\n"
      return

    connection = @core.call $connection, 'spawn'
    unless connection?
      socket.end "Server error: failed to spawn connection\n"
      return

    socket.on 'data', (buf) =>
      try
        @core.call connection, 'data', [buf]
      catch error
        console.error "Error handling data:", error
        socket.end "Server error\n"

    socket.on 'error', (error) ->
      console.error "Socket error:", error

    socket.on 'close', ->
      console.log "Connection closed"

  stop: ->
    @server?.close()

module.exports = Server
