#!/usr/bin/env coffee

fs       = require 'node:fs'
path     = require 'node:path'
readline = require 'node:readline'
MudGame  = require '../lib/mud-game'

rl = readline.createInterface
  input: process.stdin
  output: process.stdout

inputQueue = []
nextEntityId = 100

sessionsDir = path.join __dirname, '../sessions'
fs.mkdirSync sessionsDir, {recursive: true}
timestamp = new Date().toISOString().replace(/[:.]/g, '-')
logFile = path.join sessionsDir, "#{timestamp}.jsonl"

spinner = do ->
  frames = [' ', '.', 'o', 'O', 'o', '.']
  index = 0
  interval = null

  start: ->
    index = 0
    interval = setInterval (->
      process.stdout.write "\r#{frames[index]}"
      index = (index + 1) % frames.length
    ), 150

  stop: ->
    if interval?
      clearInterval interval
      interval = null
      process.stdout.write "\r \r"

print = (text) -> console.log text

printNarrative = (text) ->
  console.log ""
  console.log "─".repeat 60
  console.log text
  console.log "─".repeat 60
  console.log ""

game = new MudGame
  logFile: logFile

  onNarrative: (text) ->
    spinner.stop()
    printNarrative text

  onError: (error) ->
    spinner.stop()
    if error is 'system_down'
      print ""
      print "┌─────────────────────────────────────────┐"
      print "│       The system... is down.            │"
      print "└─────────────────────────────────────────┘"
      print ""
    else if error is 'not_understood'
      print "\nI don't understand that."
    else
      print "\n⚠ #{error}"

  onReady: ->
    processQueue()

  onLook: ->
    spinner.stop()
    describeRoom()

worldFile = process.argv[2] ? path.join(__dirname, '../worlds/tavern.coffee')
game.loadWorld worldFile

describeRoom = ->
  location = game.getPlayerLocation()
  return print "You are nowhere." unless location?

  name = game.getFact location, 'name'
  desc = game.getFact location, 'description'

  print ""
  print "═".repeat 60
  print "  #{name?.toUpperCase() ? location}"
  print "═".repeat 60
  print ""
  print desc if desc?

  things = game.getEntitiesAt location
  items = things.filter (t) ->
    t isnt '$player' and
    game.getFact(t, 'type') in ['item', 'weapon', 'container', 'treasure']

  creatures = things.filter (t) ->
    t isnt '$player' and
    game.getFact(t, 'type') is 'creature'

  if items.length > 0
    print ""
    print "You see:"
    for item in items
      itemName = game.getFact item, 'name'
      print "  - #{itemName ? item}"

  if creatures.length > 0
    print ""
    print "Present:"
    for creature in creatures
      creatureName = game.getFact creature, 'name'
      hostileFacts = game.getFactsAbout creature
      hostile = hostileFacts.some (f) -> f.predicate is 'hostile' and f.object is 'true'
      suffix = if hostile then " [hostile]" else ""
      print "  - #{creatureName ? creature}#{suffix}"

  exits = []
  for dir in ['north', 'south', 'east', 'west', 'up', 'down']
    dest = game.getFact location, dir
    exits.push dir if dest?

  if exits.length > 0
    print ""
    print "Exits: #{exits.join ', '}"

  print ""

showStats = ->
  hp     = game.getFact '$player', 'hp'
  max_hp = game.getFact '$player', 'max_hp'
  ac     = game.getFact '$player', 'ac'

  inventory = game.getEntitiesAt '$player'
  heldFacts = game.getFactsAbout '$player'
  held = heldFacts.filter((f) -> f.predicate is 'held_by').map((f) -> f.subject)
  items = [...new Set([...inventory, ...held])]

  print ""
  print "HP: #{hp}/#{max_hp}  AC: #{ac}"
  if items.length > 0
    itemNames = items.map (i) -> game.getFact i, 'name'
    print "Carrying: #{itemNames.join ', '}"
  print ""

resolveEntity = (name) ->
  return name if not name or name.startsWith '$'
  return '$player' if name is 'me'
  return game.getPlayerLocation() if name is 'here'
  "$#{name}"

creativeCommands =
  inspect:
    help: """
      /inspect <entity>

      Shows all raw facts about an entity. The $ prefix is optional.

      Examples:
        /inspect player     - show player stats and properties
        /inspect $tavern    - show room facts
        /inspect dagger     - show item properties
    """
    impl: (parts) ->
      target = parts[1]
      return print "Usage: /inspect <entity>" unless target?

      target = resolveEntity target
      target_facts = game.getFactsAbout target

      if target_facts.length is 0
        return print "\nNo facts found for #{target}"

      print "\n=== #{target} ==="
      for fact in target_facts
        print "  #{fact.subject} #{fact.predicate} #{fact.object}"
      print ""

  create:
    help: """
      /create <type> <name or args>

      Types:
        room <name>              - create a disconnected room
        exit <dir> <destination> - create bidirectional exit
        npc <name>               - create creature in current room
        item <name>              - create portable item here
        weapon <name>            - create weapon here (1d6 slashing default)

      Examples:
        /create room Dark Cavern
        /create exit north $room_100
        /create npc grumpy wizard
        /create item silver key
        /create weapon enchanted sword

      After creating a room, use /create exit to connect it.
    """
    impl: (parts) ->
      subcommand = parts[1]
      return print "Usage: /create <room|npc|item|weapon|exit> <name>" unless subcommand

      location = game.getPlayerLocation()
      facts = game.facts
      core = game.core

      switch subcommand
        when 'room'
          name = parts.slice(2).join(' ')
          return print "Usage: /create room <name>" unless name
          entityId = "$room_#{nextEntityId++}"
          core.call facts, 'assert', [entityId, 'type', 'location']
          core.call facts, 'assert', [entityId, 'name', name]
          print "\nCreated room #{entityId} \"#{name}\""
          print "Use /create exit <direction> #{entityId} to connect it"

        when 'npc'
          name = parts.slice(2).join(' ')
          return print "Usage: /create npc <name>" unless name
          entityId = "$npc_#{nextEntityId++}"
          core.call facts, 'assert', [entityId, 'type', 'creature']
          core.call facts, 'assert', [entityId, 'name', name]
          core.call facts, 'assert', [entityId, 'location', location]
          for prop in ['hp', 'max_hp', 'ac', 'level']
            core.call facts, 'set', [entityId, prop, '10']
          print "\nCreated NPC #{entityId} \"#{name}\" in current room"

        when 'item'
          name = parts.slice(2).join(' ')
          return print "Usage: /create item <name>" unless name
          entityId = "$item_#{nextEntityId++}"
          core.call facts, 'assert', [entityId, 'type', 'item']
          core.call facts, 'assert', [entityId, 'name', name]
          core.call facts, 'assert', [entityId, 'portable', 'true']
          core.call facts, 'assert', [entityId, 'location', location]
          print "\nCreated item #{entityId} \"#{name}\" in current room"

        when 'weapon'
          name = parts.slice(2).join(' ')
          return print "Usage: /create weapon <name>" unless name
          entityId = "$weapon_#{nextEntityId++}"
          core.call facts, 'assert', [entityId, 'type', 'weapon']
          core.call facts, 'assert', [entityId, 'name', name]
          core.call facts, 'assert', [entityId, 'portable', 'true']
          core.call facts, 'assert', [entityId, 'location', location]
          core.call facts, 'set', [entityId, 'damage', '1d6']
          core.call facts, 'set', [entityId, 'damage_type', 'slashing']
          print "\nCreated weapon #{entityId} \"#{name}\" (1d6 slashing)"
          print "Use /set #{entityId} damage <dice> to change damage"

        when 'exit'
          direction = parts[2]
          destination = parts[3]
          return print "Usage: /create exit <direction> <destination>" unless direction and destination
          destination = resolveEntity destination
          core.call facts, 'assert', [location, direction, destination]
          print "\nCreated exit #{direction} from #{location} to #{destination}"

          opposite = {north: 'south', south: 'north', east: 'west', west: 'east', up: 'down', down: 'up'}[direction]
          if opposite?
            core.call facts, 'assert', [destination, opposite, location]
            print "Created return exit #{opposite} from #{destination} to #{location}"

        else
          print "Unknown create type: #{subcommand}"
          print "Valid types: room, npc, item, weapon, exit"

  set:
    help: """
      /set <entity> <property> <value>

      Sets a property on an entity. The $ prefix is optional.

      Common properties:
        name, description, type, location
        hp, max_hp, ac, level (for creatures)
        str, dex, con, int, wis, cha (ability scores)
        damage, damage_type (for weapons)
        hostile (true/false for NPCs)
        portable (true/false for items)

      Examples:
        /set wizard hp 50
        /set sword damage 2d6
        /set sword damage_type fire
        /set thug hostile true
    """
    impl: (parts) ->
      entity = parts[1]
      prop = parts[2]
      value = parts.slice(3).join(' ')
      return print "Usage: /set <entity> <property> <value>" unless entity and prop and value

      entity = resolveEntity entity
      game.core.call game.facts, 'set', [entity, prop, value]
      print "\nSet #{entity}.#{prop} = #{value}"

  describe:
    help: """
      /describe <entity> <description text>

      Sets the description shown when examining something.

      Examples:
        /describe tavern A cozy tavern with a roaring fireplace.
        /describe sword The blade glows with an eerie blue light.
    """
    impl: (parts) ->
      entity = parts[1]
      description = parts.slice(2).join(' ')
      return print "Usage: /describe <entity> <description text>" unless entity and description

      entity = resolveEntity entity
      game.core.call game.facts, 'set', [entity, 'description', description]
      print "\nSet description for #{entity}"

  delete:
    help: """
      /delete <entity>

      Removes an entity and all its facts from the world.

      Examples:
        /delete npc_100
        /delete $item_101

      Warning: This cannot be undone!
    """
    impl: (parts) ->
      entity = parts[1]
      return print "Usage: /delete <entity>" unless entity

      entity = resolveEntity entity
      entity_facts = game.getFactsAbout entity

      if entity_facts.length is 0
        return print "\nNo entity #{entity} found"

      for fact in entity_facts
        game.core.call game.facts, 'retract', [fact.subject, fact.predicate, fact.object]

      print "\nDeleted #{entity} (#{entity_facts.length} facts removed)"

  facts:
    help: """
      /facts

      Dumps all facts in the world as subject-predicate-object triples.
      Useful for debugging and understanding world state.
    """
    impl: (parts) ->
      print "\n=== World State ==="
      print game.core.call game.facts, 'dump'
      print ""

  help:
    help: """
      /help [command]

      Shows help for creative mode commands.
      Use /help <command> for detailed help on a specific command.
    """
    impl: (parts) ->
      topic = parts[1]

      unless topic
        print "\n  Creative Mode Commands:"
        for name, cmd of creativeCommands
          continue if name is 'help'
          firstLine = cmd.help.trim().split('\n')[0]
          print "    #{firstLine}"
        print "\n  Use /help <command> for detailed help.\n"
        return

      if creativeCommands[topic]?
        print "\n#{creativeCommands[topic].help}\n"
      else
        print "\nNo help available for '#{topic}'"
        print "Available: #{Object.keys(creativeCommands).join ', '}"

handleCreativeCommand = (cmd) ->
  parts = cmd.split /\s+/
  command = parts[0]

  if creativeCommands[command]?
    creativeCommands[command].impl parts
  else
    print "Unknown creative command: /#{command}"
    print "Try /help for available commands"

processQueue = ->
  return if game.isWaiting()
  if inputQueue.length is 0
    prompt()
    return

  input = inputQueue.shift()

  if input is 'quit' or input is 'exit'
    print "\nFarewell, adventurer.\n"
    process.exit 0

  if input is 'stats' or input is 'status'
    showStats()
    processQueue()
    return

  if input is 'help'
    print """

    Commands:
      look          - describe your surroundings
      look <thing>  - examine something
      take <thing>  - pick something up
      drop <thing>  - put something down
      go <dir>      - move (north, south, east, west, up, down)
      attack <who>  - attack a creature
      talk <who>    - talk to someone
      stats         - show your status
      quit          - leave the game

    Creative Mode: type /help for world-building commands.

    """
    processQueue()
    return

  if input.startsWith '/'
    handleCreativeCommand input.slice(1)
    processQueue()
    return

  # Quote shorthand: "hello" -> say "hello"
  if match = input.match /^"(.*)$/
    input = "say \"#{match[1]}"

  spinner.start()
  game.processInput input

prompt = ->
  rl.question '> ', (input) ->
    input = input.trim().toLowerCase()
    return prompt() if input is ''

    inputQueue.push input
    processQueue()

print """

╔══════════════════════════════════════════════════════════════╗
║                      CLODMUD                                  ║
║              A semantic adventure game                        ║
╚══════════════════════════════════════════════════════════════╝

Type 'help' for commands, 'quit' to exit.
Session log: #{logFile}

"""

describeRoom()
prompt()
