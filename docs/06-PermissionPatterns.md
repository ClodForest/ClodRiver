# Permission Pattern Sugar

**Status:** Future analysis needed

## Goal

Develop succinct header declarations for common permission checks in methods.

## Preliminary Ideas

| Declaration | Expansion | Use Case |
|-------------|-----------|----------|
| `private` | `caller() is definer()` | Internal helper methods |
| `only $sys` | `sender() is $sys` | System-only operations |
| `only $sys, $admin` | `sender() in [$sys, $admin]` | Privileged operations |
| `self` | `sender() is this` | Self-modification only |

## TODO

1. Analyze `db/minimal/core.clod` for permission patterns
2. Analyze `db/extensions/*.clod` for additional patterns
3. Identify most common patterns
4. Design header syntax that integrates with existing `using`, `args`, `vars`
5. Implement in Compiler/TextDump

## Notes

- ColdMUD used `caller() == definer()` frequently
- Consider whether these should throw errors or return silently
- Consider integration with a proper permissions system later

## Examples to Look For

```
# Pattern: only allow $sys to call this
if sender() isnt $sys
  throw "perm"

# Pattern: internal method
if caller() isnt definer()
  throw "perm"

# Pattern: self-only
if sender() isnt @
  throw "perm"

# Pattern: allow list
if sender() not in [$sys, $admin, @]
  throw "perm"
```
