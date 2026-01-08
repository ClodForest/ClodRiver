# Tavern starting world for ClodMUD

module.exports = (facts, core) ->

  room = (id, name, description, exits = {}) ->
    core.call facts, 'assert', [id, 'type', 'location']
    core.call facts, 'assert', [id, 'name', name]
    core.call facts, 'assert', [id, 'description', description] if description
    for dir, dest of exits
      core.call facts, 'assert', [id, dir, dest]

  creature = (id, name, location, stats = {}) ->
    core.call facts, 'assert', [id, 'type', 'creature']
    core.call facts, 'assert', [id, 'name', name]
    core.call facts, 'assert', [id, 'location', location]
    defaults = {hp: 10, max_hp: 10, ac: 10, level: 1, str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
    for prop, val of {...defaults, ...stats}
      core.call facts, 'set', [id, prop, val.toString()]

  item = (id, name, location, props = {}) ->
    core.call facts, 'assert', [id, 'type', props.type ? 'item']
    core.call facts, 'assert', [id, 'name', name]
    core.call facts, 'assert', [id, 'location', location]
    core.call facts, 'assert', [id, 'portable', props.portable ? 'true']
    for prop, val of props when prop not in ['type', 'portable']
      core.call facts, 'set', [id, prop, val.toString()]

  weapon = (id, name, location, damage = '1d6', damage_type = 'slashing', props = {}) ->
    item id, name, location, {type: 'weapon', damage, damage_type, ...props}

  room '$tavern', 'The Rusty Flagon',
    'A dimly lit tavern with low wooden beams and the smell of ale',
    {north: '$street'}

  room '$street', 'Cobblestone Street',
    'A narrow street between timber-framed buildings',
    {south: '$tavern', east: '$alley'}

  room '$alley', 'Dark Alley',
    'A shadowy passage between buildings, refuse piled against the walls',
    {west: '$street'}

  creature '$player', 'adventurer', '$tavern',
    {str: 14, dex: 12, con: 13, int: 10, wis: 11, cha: 10, level: 2, hp: 18, max_hp: 18, ac: 14}

  core.call facts, 'assert', ['$player', 'proficiency', 'perception']
  core.call facts, 'assert', ['$player', 'proficiency', 'athletics']
  core.call facts, 'assert', ['$player', 'proficiency', 'martial_weapons']

  creature '$barkeep', 'gruff barkeep', '$tavern',
    {str: 14, dex: 10, con: 12, int: 10, wis: 12, cha: 8, hp: 22, max_hp: 22}

  creature '$thug', 'hooded thug', '$alley',
    {str: 15, dex: 12, con: 12, int: 9, wis: 10, cha: 9, hp: 15, max_hp: 15, ac: 12}
  core.call facts, 'assert', ['$thug', 'hostile', 'true']

  weapon '$dagger', 'rusty dagger', '$tavern', '1d4', 'piercing'
  core.call facts, 'assert', ['$dagger', 'property', 'finesse']

  weapon '$club', 'heavy club', '$alley', '1d6', 'bludgeoning'
  core.call facts, 'assert', ['$club', 'held_by', '$thug']

  item '$mug', 'half-empty mug of ale', '$tavern'

  item '$pouch', 'leather pouch', '$alley', {type: 'container'}

  item '$coins', 'handful of gold coins', '$pouch', {type: 'treasure'}
  core.call facts, 'retract', ['$coins', 'location', '$pouch']
  core.call facts, 'assert', ['$coins', 'inside', '$pouch']
