fs           = require 'node:fs'
path         = require 'node:path'

Core         = require './core'
TextDump     = require './text-dump'
sourceMaps   = require './source-maps'

sourceMaps.install()

class Server
  constructor: ->
    @core   = new Core()
    @server = null

  loadCore: (corePath) ->
    source   = fs.readFileSync corePath, 'utf8'
    filename = path.basename corePath
    dump     = TextDump.fromString source, filename
    dump.apply @core
    @core

  start: (port = 7777, addr = '127.0.0.1') ->
    # Call $sys.startup which will use listen BIF to create the TCP server
    $sys = @core.toobj '$sys'
    @core.call $sys, 'startup', [{port, addr}]
    console.log "ClodRiver started via $sys.startup on #{addr}:#{port}"

  stop: ->
    # TODO: implement graceful shutdown via $sys.shutdown
    console.log "Server stop requested"

module.exports = Server
