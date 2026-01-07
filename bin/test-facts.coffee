#!/usr/bin/env coffee

fs       = require 'node:fs'
Core     = require '../lib/core'
TextDump = require '../lib/text-dump'

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

factsSource = fs.readFileSync 'clod/core/facts/index.clod', 'utf8'
factsDump   = TextDump.fromString factsSource, 'facts.clod'
factsDump.apply core

$facts_proto = core.toobj '$facts'
facts = core.call $facts_proto, 'spawn'

console.log "=== Triple Store Test ==="
console.log ""

console.log "Asserting facts..."
core.call facts, 'assert', ['$sword', 'location', '$room']
core.call facts, 'assert', ['$sword', 'type', 'weapon']
core.call facts, 'assert', ['$sword', 'name', 'rusty sword']
core.call facts, 'assert', ['$player', 'location', '$room']
core.call facts, 'assert', ['$player', 'type', 'person']
core.call facts, 'assert', ['$room', 'type', 'location']
core.call facts, 'assert', ['$room', 'name', 'dusty cellar']

console.log "Total facts: #{core.call facts, 'count'}"
console.log ""

console.log "Query: about $sword"
for fact in core.call facts, 'about', ['$sword']
  console.log "  #{fact.subject} #{fact.predicate} #{fact.object}"
console.log ""

console.log "Query: get $sword location"
loc = core.call facts, 'get', ['$sword', 'location']
console.log "  #{loc}"
console.log ""

console.log "Query: subjects_where type = weapon"
weapons = core.call facts, 'subjects_where', ['type', 'weapon']
console.log "  #{weapons.join ', '}"
console.log ""

console.log "Query: everything in $room"
inRoom = core.call facts, 'subjects_where', ['location', '$room']
console.log "  #{inRoom.join ', '}"
console.log ""

console.log "Simulating 'take sword' - changing location..."
core.call facts, 'retract', ['$sword', 'location', '$room']
core.call facts, 'assert', ['$sword', 'location', '$player']
core.call facts, 'assert', ['$sword', 'held_by', '$player']

console.log ""
console.log "After take:"
console.log "  sword location: #{core.call facts, 'get', ['$sword', 'location']}"
console.log "  sword held_by: #{core.call facts, 'get', ['$sword', 'held_by']}"
console.log "  things in room: #{core.call(facts, 'subjects_where', ['location', '$room']).join ', '}"
console.log "  things on player: #{core.call(facts, 'subjects_where', ['location', '$player']).join ', '}"
console.log ""

console.log "=== Full dump ==="
console.log core.call facts, 'dump'
