#!/usr/bin/env coffee

fs       = require 'node:fs'
readline = require 'node:readline'
Core     = require '../lib/core'
TextDump = require '../lib/text-dump'

LLM_CONFIG =
  baseURL: process.env.LLM_URL ? 'http://localhost:11435/v1'
  model:   process.env.LLM_MODEL ? 'hf.co/bartowski/TheDrummer_Precog-24B-v1-GGUF:Q6_K_L'

core = new Core()

$sys  = core.toobj '$sys'
$root = core.toobj '$root'

core.addMethod $root, 'spawn', (create) ->
  (ctx, args) ->
    newObj = create @
    newObj.init?()
    newObj

core.addMethod $root, 'init', ->
  (ctx, args) ->

loadModule = (path) ->
  source = fs.readFileSync path, 'utf8'
  dump   = TextDump.fromString source, path
  dump.apply core

loadModule 'clod/core/facts/index.clod'
loadModule 'clod/core/intent/index.clod'
loadModule 'clod/core/action/index.clod'
loadModule 'clod/core/render/index.clod'
loadModule 'clod/core/d20/index.clod'

$facts_proto    = core.toobj '$facts'
$parser_proto   = core.toobj '$intent_parser'
$action_proto   = core.toobj '$action_interpreter'
$renderer_proto = core.toobj '$renderer'
$d20_proto      = core.toobj '$d20'
$dice           = core.toobj '$dice'

facts    = core.call $facts_proto, 'spawn'
parser   = core.call $parser_proto, 'spawn'
action   = core.call $action_proto, 'spawn'
renderer = core.call $renderer_proto, 'spawn'
d20      = core.call $d20_proto, 'spawn'

core.addMethod $sys, 'setup', (connect_llm, send) ->
  (ctx, args) ->
    connect_llm parser, LLM_CONFIG
    connect_llm action, LLM_CONFIG
    connect_llm renderer, LLM_CONFIG

    send parser, 'configure', {
      available_verbs: [
        'look', 'examine', 'take', 'drop', 'go', 'open', 'close',
        'attack', 'cast', 'use', 'give', 'put', 'talk', 'search',
        'hide', 'sneak', 'climb', 'jump', 'push', 'pull', 'listen'
      ]
    }

    send action, 'configure', {facts, d20}
    send renderer, 'configure', {facts, style: 'classic'}
    send d20, 'configure', {facts}

core.call $sys, 'setup'

setupWorld = ->
  core.call facts, 'assert', ['$tavern', 'type', 'location']
  core.call facts, 'assert', ['$tavern', 'name', 'The Rusty Flagon']
  core.call facts, 'assert', ['$tavern', 'description', 'A dimly lit tavern with low wooden beams and the smell of ale']
  core.call facts, 'assert', ['$tavern', 'north', '$street']

  core.call facts, 'assert', ['$street', 'type', 'location']
  core.call facts, 'assert', ['$street', 'name', 'Cobblestone Street']
  core.call facts, 'assert', ['$street', 'description', 'A narrow street between timber-framed buildings']
  core.call facts, 'assert', ['$street', 'south', '$tavern']
  core.call facts, 'assert', ['$street', 'east', '$alley']

  core.call facts, 'assert', ['$alley', 'type', 'location']
  core.call facts, 'assert', ['$alley', 'name', 'Dark Alley']
  core.call facts, 'assert', ['$alley', 'description', 'A shadowy passage between buildings, refuse piled against the walls']
  core.call facts, 'assert', ['$alley', 'west', '$street']

  core.call facts, 'assert', ['$player', 'type', 'creature']
  core.call facts, 'assert', ['$player', 'name', 'adventurer']
  core.call facts, 'assert', ['$player', 'location', '$tavern']
  core.call facts, 'set', ['$player', 'str', '14']
  core.call facts, 'set', ['$player', 'dex', '12']
  core.call facts, 'set', ['$player', 'con', '13']
  core.call facts, 'set', ['$player', 'int', '10']
  core.call facts, 'set', ['$player', 'wis', '11']
  core.call facts, 'set', ['$player', 'cha', '10']
  core.call facts, 'set', ['$player', 'level', '2']
  core.call facts, 'set', ['$player', 'hp', '18']
  core.call facts, 'set', ['$player', 'max_hp', '18']
  core.call facts, 'set', ['$player', 'ac', '14']
  core.call facts, 'assert', ['$player', 'proficiency', 'perception']
  core.call facts, 'assert', ['$player', 'proficiency', 'athletics']
  core.call facts, 'assert', ['$player', 'proficiency', 'martial_weapons']

  core.call facts, 'assert', ['$dagger', 'type', 'weapon']
  core.call facts, 'assert', ['$dagger', 'name', 'rusty dagger']
  core.call facts, 'assert', ['$dagger', 'portable', 'true']
  core.call facts, 'set', ['$dagger', 'damage', '1d4']
  core.call facts, 'set', ['$dagger', 'damage_type', 'piercing']
  core.call facts, 'assert', ['$dagger', 'property', 'finesse']
  core.call facts, 'assert', ['$dagger', 'location', '$tavern']

  core.call facts, 'assert', ['$mug', 'type', 'item']
  core.call facts, 'assert', ['$mug', 'name', 'half-empty mug of ale']
  core.call facts, 'assert', ['$mug', 'portable', 'true']
  core.call facts, 'assert', ['$mug', 'location', '$tavern']

  core.call facts, 'assert', ['$barkeep', 'type', 'creature']
  core.call facts, 'assert', ['$barkeep', 'name', 'gruff barkeep']
  core.call facts, 'assert', ['$barkeep', 'location', '$tavern']
  core.call facts, 'set', ['$barkeep', 'str', '14']
  core.call facts, 'set', ['$barkeep', 'dex', '10']
  core.call facts, 'set', ['$barkeep', 'con', '12']
  core.call facts, 'set', ['$barkeep', 'int', '10']
  core.call facts, 'set', ['$barkeep', 'wis', '12']
  core.call facts, 'set', ['$barkeep', 'cha', '8']
  core.call facts, 'set', ['$barkeep', 'hp', '22']
  core.call facts, 'set', ['$barkeep', 'max_hp', '22']
  core.call facts, 'set', ['$barkeep', 'ac', '10']
  core.call facts, 'set', ['$barkeep', 'level', '2']

  core.call facts, 'assert', ['$thug', 'type', 'creature']
  core.call facts, 'assert', ['$thug', 'name', 'hooded thug']
  core.call facts, 'assert', ['$thug', 'hostile', 'true']
  core.call facts, 'assert', ['$thug', 'location', '$alley']
  core.call facts, 'set', ['$thug', 'str', '15']
  core.call facts, 'set', ['$thug', 'dex', '12']
  core.call facts, 'set', ['$thug', 'con', '12']
  core.call facts, 'set', ['$thug', 'int', '9']
  core.call facts, 'set', ['$thug', 'wis', '10']
  core.call facts, 'set', ['$thug', 'cha', '9']
  core.call facts, 'set', ['$thug', 'hp', '15']
  core.call facts, 'set', ['$thug', 'max_hp', '15']
  core.call facts, 'set', ['$thug', 'ac', '12']
  core.call facts, 'set', ['$thug', 'level', '2']

  core.call facts, 'assert', ['$club', 'type', 'weapon']
  core.call facts, 'assert', ['$club', 'name', 'heavy club']
  core.call facts, 'set', ['$club', 'damage', '1d6']
  core.call facts, 'set', ['$club', 'damage_type', 'bludgeoning']
  core.call facts, 'assert', ['$club', 'held_by', '$thug']

  core.call facts, 'assert', ['$pouch', 'type', 'container']
  core.call facts, 'assert', ['$pouch', 'name', 'leather pouch']
  core.call facts, 'assert', ['$pouch', 'portable', 'true']
  core.call facts, 'assert', ['$pouch', 'location', '$alley']

  core.call facts, 'assert', ['$coins', 'type', 'treasure']
  core.call facts, 'assert', ['$coins', 'name', 'handful of gold coins']
  core.call facts, 'assert', ['$coins', 'portable', 'true']
  core.call facts, 'assert', ['$coins', 'inside', '$pouch']

setupWorld()

rl = readline.createInterface
  input: process.stdin
  output: process.stdout

waiting = false
inputQueue = []

print = (text) ->
  console.log text

printNarrative = (text) ->
  console.log ""
  console.log "─".repeat 60
  console.log text
  console.log "─".repeat 60
  console.log ""

describeRoom = ->
  location = core.call facts, 'get', ['$player', 'location']
  return print "You are nowhere." unless location?

  name = core.call facts, 'get', [location, 'name']
  desc = core.call facts, 'get', [location, 'description']

  print ""
  print "═".repeat 60
  print "  #{name?.toUpperCase() ? location}"
  print "═".repeat 60
  print ""
  print desc if desc?

  things = core.call facts, 'subjects_where', ['location', location]
  items = things.filter (t) ->
    t isnt '$player' and
    core.call(facts, 'get', [t, 'type']) in ['item', 'weapon', 'container', 'treasure']

  creatures = things.filter (t) ->
    t isnt '$player' and
    core.call(facts, 'get', [t, 'type']) is 'creature'

  if items.length > 0
    print ""
    print "You see:"
    for item in items
      itemName = core.call facts, 'get', [item, 'name']
      print "  - #{itemName ? item}"

  if creatures.length > 0
    print ""
    print "Present:"
    for creature in creatures
      creatureName = core.call facts, 'get', [creature, 'name']
      hostile = core.call facts, 'has', [creature, 'hostile', 'true']
      suffix = if hostile then " [hostile]" else ""
      print "  - #{creatureName ? creature}#{suffix}"

  exits = []
  for dir in ['north', 'south', 'east', 'west', 'up', 'down']
    dest = core.call facts, 'get', [location, dir]
    exits.push dir if dest?

  if exits.length > 0
    print ""
    print "Exits: #{exits.join ', '}"

  print ""

showStats = ->
  hp     = core.call facts, 'get', ['$player', 'hp']
  max_hp = core.call facts, 'get', ['$player', 'max_hp']
  ac     = core.call facts, 'get', ['$player', 'ac']

  inventory = core.call facts, 'subjects_where', ['location', '$player']
  held      = core.call facts, 'subjects_where', ['held_by', '$player']
  items     = [...new Set([...inventory, ...held])]

  print ""
  print "HP: #{hp}/#{max_hp}  AC: #{ac}"
  if items.length > 0
    itemNames = items.map (i) -> core.call facts, 'get', [i, 'name']
    print "Carrying: #{itemNames.join ', '}"
  print ""

narrativeHandler = core.create $root
core.addMethod narrativeHandler, 'receive_narrative', ->
  (ctx, args) ->
    [narrative] = args
    printNarrative narrative.text
    waiting = false
    processQueue()

resultHandler = core.create $root
core.addMethod resultHandler, 'action_completed', (send) ->
  (ctx, args) ->
    [result] = args
    send renderer, 'render', result, result.subject

core.call renderer, 'configure', [{narrative_handler: narrativeHandler}]
core.call action, 'configure', [{result_handler: resultHandler}]

intentHandler = core.create $root
core.addMethod intentHandler, 'receive_intent', (send) ->
  (ctx, args) ->
    [intent, subject] = args

    if intent.type is 'unknown'
      print "\nI don't understand that."
      waiting = false
      processQueue()
      return

    if intent.verb is 'look' and not intent.object? and not intent.target?
      describeRoom()
      waiting = false
      processQueue()
      return

    send action, 'execute', intent, subject

core.call parser, 'configure', [{intent_handler: intentHandler}]

processQueue = ->
  return if waiting
  return if inputQueue.length is 0

  input = inputQueue.shift()

  if input is 'quit' or input is 'exit'
    print "\nFarewell, adventurer.\n"
    process.exit 0

  if input is 'stats' or input is 'status'
    showStats()
    prompt()
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
      facts         - dump world state (debug)
      quit          - leave the game

    """
    prompt()
    return

  if input is 'facts'
    print "\n=== World State ==="
    print core.call facts, 'dump'
    print ""
    prompt()
    return

  waiting = true
  core.call parser, 'parse', [input, '$player']

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

"""

describeRoom()
prompt()
