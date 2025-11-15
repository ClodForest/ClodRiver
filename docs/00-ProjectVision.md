# ClodRiver Project Vision

**Version:** 2.0 (From Scratch)  
**Date:** November 2025  
**Status:** Specification Phase

## Executive Summary

ClodRiver is a modern MUD (Multi-User Dungeon) server written in Node.js/CoffeeScript that integrates Large Language Models for natural language parsing, dynamic world building, and intelligent NPC behavior. This "from scratch" version takes a pragmatic approach to ship v1 quickly while maintaining a clear path to a more ambitious v2 that revives ColdMUD's elegant design.

## Core Philosophy

### The Two-Version Strategy

**Version 1: Pragmatic Foundation**
- Maximum pragmatism, minimal reinvention
- Use ES6/CoffeeScript features naturally
- Get LLM integration working ASAP
- Prove the concept with real users

**Version 2: ColdMUD Revival**
- Full separation of server and core
- Custom object model with ColdMUD semantics
- Syntactic sugar for natural MUD programming
- Complete sandboxing via IPC

**Migration Path:** v1 code written with v2 in mind. All state access goes through CoreAPI, making transformation automatable.

### What Makes ClodRiver Different

1. **LLM Integration Throughout**
   - Natural language command parsing
   - Dynamic world generation
   - Context-aware prose enhancement
   - Intelligent NPC participation

2. **Modern Architecture**
   - Event sourcing for persistence
   - Git-friendly text dumps
   - Hot-reloadable core code
   - Full TypeScript/CoffeeScript tooling

3. **ColdMUD-Inspired Design**
   - Clean server/core separation
   - Methods are separate from verbs
   - No hardcoded player/wizard concepts
   - Delegation-based connection handling

## Three Interconnected Systems

ClodRiver builds on previous work to create a complete AI-powered MUD experience:

### 1. NPC Relevance Scoring (from IntelligentSystems.md)
NPCs observe continuous event streams and decide when to participate:
- Tier 0: Deterministic pattern matching (<5ms)
- Tier 1: Lightweight LLM semantic scoring (100-200ms)
- Tier 2: Full response generation when relevant (500-1500ms)

**Result:** NPCs that feel alive, speaking when appropriate rather than on every event.

### 2. LLM-Fronted Parser (from IntelligentSystems.md)
Natural language commands translated to game actions:
- Context-aware parsing ("look again" remembers what you looked at)
- Intent recognition ("is the vase a mimic?" → skill check)
- Prose enhancement (repetitive output becomes engaging narrative)

**Result:** Players interact naturally without memorizing command syntax.

### 3. Dynamic World Building (from IntelligentSystems.md)
NPCs don't just describe locations—they manifest them:
- Generate room descriptions on demand
- Create actual LambdaMOO objects and exits
- Populate with interactive objects
- Persistent or temporary based on context

**Result:** Infinite procedural content that feels hand-crafted.

## Technical Foundation

### Server Responsibilities
- Network layer (telnet, eventually SSH/HTTPS)
- Session management
- Object lifecycle (create, load, save, destroy)
- Method dispatch with ColdMUD semantics
- Persistence (event log + snapshots + text dumps)
- LLM integration (parser, NPC scorer, prose enhancer)

### Core Responsibilities
- World logic and game rules
- Object definitions (rooms, players, things)
- Verb system (command → method mapping)
- Content (descriptions, interactions, quests)

### CoreAPI Contract
The clean boundary between server and core:
- Object management (create, get, destroy)
- State access (get/set with event logging)
- Method dispatch (with definer/caller/sender context)
- Communication (notify, broadcast)
- Queries (location, contents, search)

## Why CoffeeScript?

CoffeeScript provides:
1. **Readable class syntax** - natural for MUD object definitions
2. **@ sugar** - `@name` instead of `this.name`
3. **Implicit returns** - cleaner code
4. **Comprehensions** - better than `.map()` for readability
5. **Significant whitespace** - enforces clean structure

Most importantly: it compiles to readable ES6, making debugging easier than direct JS.

## Success Criteria

### Version 1 (3-4 months)
- [ ] Telnet server with session management
- [ ] Object system with persistence
- [ ] Basic LLM parser integration
- [ ] 5-10 connected rooms with objects
- [ ] 2-3 NPCs with relevance scoring
- [ ] Hot-reloadable core code
- [ ] Text dumps for version control

### Version 2 (6-12 months)
- [ ] IPC-based sandboxing
- [ ] ColdMUD object model semantics
- [ ] Syntactic sugar transpiler
- [ ] Multi-server operation
- [ ] Full dynamic world building
- [ ] 50+ NPCs with rich behavior
- [ ] Public beta with real users

## Why This Matters

MUDs were the original metaverse—persistent virtual worlds where players created stories together. But they died out because:
1. Rigid command parsers frustrated new players
2. Static worlds felt lifeless
3. NPCs were obviously robots
4. Creating content required learning arcane syntax

LLMs solve all four problems. ClodRiver proves it's possible to:
- Parse natural language intuitively
- Generate dynamic, responsive worlds
- Create NPCs that feel genuinely alive
- Let creators write in modern languages with full tooling

This isn't just nostalgia—it's showing what collaborative virtual worlds can be when modern AI meets proven MUD design.

## Related Projects

- **ClodForest** - MCP server infrastructure
- **ClodHearth** - (previous project context)
- **Agent Calico** - Multi-agent orchestration

ClodRiver brings together lessons learned from all three to create something genuinely new.

## Next Steps

1. Complete architecture specification
2. Define CoreAPI contract
3. Implement minimal server (telnet + objects + persistence)
4. Create minimal core (bootstrap objects)
5. Integrate LLM parser
6. Add first NPCs with relevance scoring
7. Iterate based on real usage

---

*"The best way to predict the future is to build it."* - Alan Kay

Let's build the future of virtual worlds.
