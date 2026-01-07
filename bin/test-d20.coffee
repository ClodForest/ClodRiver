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

loadModule = (path) ->
  source = fs.readFileSync path, 'utf8'
  dump   = TextDump.fromString source, path
  dump.apply core

loadModule 'clod/core/facts/index.clod'
loadModule 'clod/core/d20/index.clod'

$facts_proto = core.toobj '$facts'
$d20_proto   = core.toobj '$d20'
$dice        = core.toobj '$dice'

facts = core.call $facts_proto, 'spawn'
d20   = core.call $d20_proto, 'spawn'

core.call d20, 'configure', [{facts}]

console.log "=== D20 Module Test ===\n"

console.log "--- Dice Rolling ---"
for expr in ['d20', '2d6', 'd8+3', '4d6']
  result = core.call $dice, 'roll', [expr]
  console.log "#{expr}: #{result.value} (rolls: #{result.rolls.join ', '})"

console.log "\n--- Advantage/Disadvantage ---"
for type in ['advantage', 'disadvantage']
  opts = {}
  opts[type] = true
  result = core.call $dice, 'roll', ['d20', opts]
  console.log "d20 #{type}: #{result.value} from [#{result.rolls.join ', '}]"

console.log "\n--- Setting up a character ---"
core.call facts, 'assert', ['$fighter', 'type', 'creature']
core.call facts, 'assert', ['$fighter', 'name', 'Gronk the Fighter']
core.call facts, 'set', ['$fighter', 'str', '16']
core.call facts, 'set', ['$fighter', 'dex', '12']
core.call facts, 'set', ['$fighter', 'con', '14']
core.call facts, 'set', ['$fighter', 'int', '8']
core.call facts, 'set', ['$fighter', 'wis', '10']
core.call facts, 'set', ['$fighter', 'cha', '10']
core.call facts, 'set', ['$fighter', 'level', '3']
core.call facts, 'set', ['$fighter', 'hp', '28']
core.call facts, 'set', ['$fighter', 'max_hp', '28']
core.call facts, 'set', ['$fighter', 'ac', '16']
core.call facts, 'assert', ['$fighter', 'proficiency', 'athletics']
core.call facts, 'assert', ['$fighter', 'proficiency', 'perception']
core.call facts, 'assert', ['$fighter', 'proficiency', 'martial_weapons']
core.call facts, 'assert', ['$fighter', 'save_proficiency', 'str']
core.call facts, 'assert', ['$fighter', 'save_proficiency', 'con']

console.log "STR modifier: #{core.call d20, 'get_modifier', ['$fighter', 'str']}"
console.log "Athletics (proficient): +#{core.call d20, 'get_skill_modifier', ['$fighter', 'athletics']}"
console.log "Stealth (not proficient): +#{core.call d20, 'get_skill_modifier', ['$fighter', 'stealth']}"

console.log "\n--- Skill Checks ---"
for dc in [10, 15, 20]
  result = core.call d20, 'check', ['$fighter', 'athletics', dc]
  status = if result.success then 'SUCCESS' else 'FAIL'
  console.log "Athletics vs DC #{dc}: #{result.roll}+#{result.modifier}=#{result.total} [#{status}]"

console.log "\n--- Saving Throws ---"
result = core.call d20, 'save', ['$fighter', 'str', 15]
console.log "STR save vs DC 15 (proficient): #{result.roll}+#{result.modifier}=#{result.total}"
result = core.call d20, 'save', ['$fighter', 'wis', 15]
console.log "WIS save vs DC 15 (not proficient): #{result.roll}+#{result.modifier}=#{result.total}"

console.log "\n--- Setting up enemy ---"
core.call facts, 'assert', ['$goblin', 'type', 'creature']
core.call facts, 'assert', ['$goblin', 'name', 'Sneaky Goblin']
core.call facts, 'set', ['$goblin', 'str', '8']
core.call facts, 'set', ['$goblin', 'dex', '14']
core.call facts, 'set', ['$goblin', 'con', '10']
core.call facts, 'set', ['$goblin', 'hp', '7']
core.call facts, 'set', ['$goblin', 'max_hp', '7']
core.call facts, 'set', ['$goblin', 'ac', '13']
core.call facts, 'set', ['$goblin', 'level', '1']

console.log "\n--- Setting up weapon ---"
core.call facts, 'assert', ['$longsword', 'type', 'weapon']
core.call facts, 'assert', ['$longsword', 'name', 'Longsword']
core.call facts, 'set', ['$longsword', 'damage', '1d8']
core.call facts, 'set', ['$longsword', 'damage_type', 'slashing']

console.log "\n--- Combat ---"
for i in [1..3]
  console.log "\nRound #{i}:"

  attack = core.call d20, 'attack', ['$fighter', '$goblin', '$longsword']
  if attack.hit
    hitType = if attack.critical then 'CRITICAL HIT' else 'HIT'
    console.log "  Attack: #{attack.attack_roll}+#{attack.attack_mod}=#{attack.attack_total} vs AC #{attack.target_ac} - #{hitType}!"
    console.log "  Damage: #{attack.damage} #{attack.damage_type} (rolls: #{attack.damage_rolls.join ', '})"

    dmg = core.call d20, 'apply_damage', ['$goblin', attack.damage, attack.damage_type]
    console.log "  Goblin HP: #{dmg.previous_hp} -> #{dmg.current_hp}"

    if dmg.unconscious
      console.log "  The goblin falls unconscious!"
      break
  else
    missType = if attack.fumble then 'FUMBLE' else 'MISS'
    console.log "  Attack: #{attack.attack_roll}+#{attack.attack_mod}=#{attack.attack_total} vs AC #{attack.target_ac} - #{missType}"

console.log "\n--- Conditions ---"
core.call d20, 'apply_condition', ['$fighter', 'poisoned']
console.log "Applied poisoned condition"

result = core.call d20, 'check', ['$fighter', 'athletics', 15]
console.log "Athletics check while poisoned (disadvantage): #{result.type}"
console.log "  Rolls: [#{result.rolls.join ', '}] -> #{result.roll}"

core.call d20, 'remove_condition', ['$fighter', 'poisoned']
console.log "Removed poisoned condition"

console.log "\n--- Contested Check ---"
contest = core.call d20, 'contest', ['$fighter', 'athletics', '$goblin', 'acrobatics']
winner_name = core.call facts, 'get', [contest.winner, 'name']
console.log "Grapple attempt: Fighter #{contest.actor_total} vs Goblin #{contest.target_total}"
console.log "  Winner: #{winner_name} (margin: #{contest.margin})"

console.log "\n=== Test Complete ==="
