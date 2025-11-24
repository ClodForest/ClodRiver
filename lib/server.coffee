net      = require 'node:net'
fs       = require 'node:fs'

Core     = require './core'
Compiler = require './compiler'

class Server
  constructor: ->
    @core     = new Core()
    @compiler = new Compiler @core
    @server   = null

  loadCore: (corePath) ->
    source = fs.readFileSync corePath, 'utf8'

    @compiler.compile source
    code = @compiler.generate()

    bootstrapFn = new Function 'core', code
    bootstrapFn.call @core, @core

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
