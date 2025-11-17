$excalibur                        =    @call $sword, 'spawn'

$sword    ._id                    === 41
$excalibur._id                    === 42
$excalibur.swing                  === $sword.swing
$excalibur.constructor.name       === ''
$excalibur.prototype              === $sword

$sword.constructor.name           === ''
$sword.prototype                  === $thing
$sword.prototype._id              === 6
$sword.prototype.prototype        === $root
$sword.prototype.prototype._id    === 1
$sword._state[1].name             === '$sword'
$sword._state[6].name             === 'sword'
$sword._state[41].dmg             === 'd6'

$excalibur._state[1].name         === '$sword_42'

@call $excalibur, 'set_weapon_dmg', '3d12 + 10'
@call $excalibur, 'set_thing_name', 'Excalibur'
@call $excalibur, 'set_thing_descrtiption', 'a sword pulled from a stone'


