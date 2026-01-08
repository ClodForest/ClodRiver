fs           = require 'node:fs'
path         = require 'node:path'
net          = require 'node:net'

MudGame      = require './mud-game'
sourceMaps   = require './source-maps'

sourceMaps.install()

class Server
  constructor: (options = {}) ->
    @port = options.port ? 7777
    @addr = options.addr ? '127.0.0.1'
    @worldPath = options.worldPath ? path.join(__dirname, '../worlds/tavern.coffee')
    @llmConfig = options.llmConfig ? null

    @sessions = new Map()  # socket -> MudGame
    @server = null

  start: ->
    @server = net.createServer (socket) =>
      @_handleConnection socket

    @server.listen @port, @addr, =>
      console.log "ClodRiver listening on #{@addr}:#{@port}"

  stop: ->
    @server?.close()
    for [socket, game] from @sessions
      socket.end()
    @sessions.clear()
    console.log "Server stopped"

  _handleConnection: (socket) ->
    gameOptions = {}
    gameOptions.llmConfig = @llmConfig if @llmConfig?

    gameOptions.onNarrative = (text) ->
      socket.write "\r\n"
      socket.write "─".repeat(60) + "\r\n"
      socket.write text + "\r\n"
      socket.write "─".repeat(60) + "\r\n"
      socket.write "\r\n> "

    gameOptions.onError = (error) ->
      if error is 'system_down'
        socket.write "\r\nThe system... is down.\r\n> "
      else if error is 'not_understood'
        socket.write "\r\nI don't understand that.\r\n> "
      else
        socket.write "\r\n⚠ #{error}\r\n> "

    gameOptions.onReady = ->
      socket.write "> "

    gameOptions.onLook = =>
      game = @sessions.get socket
      @_sendRoomDescription socket, game

    game = new MudGame gameOptions
    game.loadWorld @worldPath
    @sessions.set socket, game

    socket.write "\r\nWelcome to ClodMUD!\r\n\r\n"
    @_sendRoomDescription socket, game
    socket.write "> "

    buffer = ''
    socket.on 'data', (data) =>
      buffer += data.toString()
      while (idx = buffer.indexOf('\n')) >= 0
        line = buffer.slice(0, idx).replace(/\r/g, '').trim()
        buffer = buffer.slice(idx + 1)
        @_handleInput socket, line if line

    socket.on 'close', =>
      @sessions.delete socket

    socket.on 'error', (err) =>
      console.error "Socket error: #{err.message}"
      @sessions.delete socket

  _handleInput: (socket, input) ->
    game = @sessions.get socket
    return unless game?

    input = input.toLowerCase()

    if input is 'quit' or input is 'exit'
      socket.write "\r\nFarewell, adventurer.\r\n"
      socket.end()
      return

    if input is 'look'
      @_sendRoomDescription socket, game
      socket.write "> "
      return

    game.processInput input

  _sendRoomDescription: (socket, game) ->
    location = game.getPlayerLocation()
    unless location?
      socket.write "You are nowhere.\r\n"
      return

    name = game.getFact location, 'name'
    desc = game.getFact location, 'description'

    socket.write "\r\n"
    socket.write "═".repeat(60) + "\r\n"
    socket.write "  #{name?.toUpperCase() ? location}\r\n"
    socket.write "═".repeat(60) + "\r\n"
    socket.write "\r\n"
    socket.write desc + "\r\n" if desc?

    things = game.getEntitiesAt location
    items = things.filter (t) ->
      t isnt '$player' and
      game.getFact(t, 'type') in ['item', 'weapon', 'container', 'treasure']

    creatures = things.filter (t) ->
      t isnt '$player' and
      game.getFact(t, 'type') is 'creature'

    if items.length > 0
      socket.write "\r\nYou see:\r\n"
      for item in items
        itemName = game.getFact item, 'name'
        socket.write "  - #{itemName ? item}\r\n"

    if creatures.length > 0
      socket.write "\r\nPresent:\r\n"
      for creature in creatures
        creatureName = game.getFact creature, 'name'
        socket.write "  - #{creatureName ? creature}\r\n"

    exits = []
    for dir in ['north', 'south', 'east', 'west', 'up', 'down']
      dest = game.getFact location, dir
      exits.push dir if dest?

    if exits.length > 0
      socket.write "\r\nExits: #{exits.join ', '}\r\n"

    socket.write "\r\n"

module.exports = Server
