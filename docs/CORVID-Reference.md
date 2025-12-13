# CORVID Reference (Condensed)

Consolidated from https://github.com/ProjectCORVID/CORVID/wiki

## Philosophy

CORVID models **perception and narrative, not reality**. Key tenets:
- Believability over realism
- Self-consistent worlds
- Text-based interaction only

## Architecture Layers

| Layer | Purpose |
|-------|---------|
| **Engine** | Auth, persistence, network, referent semantics |
| **Core** | Entities, relationships, contexts, agents, grouping, containment, transformations |
| **System** | Abstract definitions (locations, skills, actions) - like RPG systems |
| **Setting** | Template with maps and NPCs |
| **World** | Instantiated system/setting users interact with |
| **Client** | User connection interfaces |

## Core Concepts

### Referent
The fundamental unit - anything that can be discussed or referred to. Anchor points for discourse.

### Entity
Fundamental unit of existence. Entities are:
- Members of Groups
- Sources of Events (Actors)
- Listeners for Events (Observers)

Can represent physical objects, abstract concepts, social groups, or locations.

### Observation (6-tuple)
An assertion capturing what someone perceives:
1. **Observer** - who is recording
2. **Context** - snapshot of event propagation extent
3. **Subject** - source of the event
4. **Relationship** - what differential was observed
5. **Object** - what subject acts upon
6. **Details** - parameters to the relationship (N times more/less, etc.)

### Event
An Observation in motion. Structure:
- Subject (source/initiator)
- Object (target)
- Relation (nature of interaction)
- Degree (specific details)
- Indirect Object (optional modifier)

Example: "Alice entered the room via the doorway"
→ subject(Alice) relation(entered) object(theRoom) indirectObject(theDoorway)

### Event Lifecycle
1. Agent creates event via Dispatcher
2. Dispatcher sends to relevant Listeners
3. Listeners match against Behaviors
4. Behaviors can reject (unwind) or accept (generate Changes)
5. If accepted: add to History, broadcast to Network

Events must degrade in significance to prevent infinite loops.

### Behavior
Container for locally trusted code. Has:
- Input parameters (names with defaults)
- State management (local, argument-based, or object-based)
- Output channels (callbacks)
- Message bindings for routing

State is saved atomically when behavior concludes.

### Group
Addressable collection of Entities.

### Transformations
Three fundamental changes:
1. **Morph** - adjust parameters within relationships
2. **Associate/Dissociate** - create or break connections
3. **Destroy/Create** - convert entities between states

## Key Terminology

| Term | Definition |
|------|-----------|
| **Domain** | Collection of servers and policies |
| **Policy** | Rule about relationships between Referents from different Domains |
| **Object** | Member of a Domain (cannot leave, but Referents may) |
| **Message** | Sole communication method between Objects |
| **User** | Account within a Domain; Objects have User owners |
| **Agent** | Source of Events |
| **Avatar** | Agent motivated by User or AI |
| **Character** | Constrained Avatar (restricted actions) |
| **Question** | Observation with unbound variables |

## Observation Types

- **Derivations** - computed from other observations
- **Declarations** - builder-authored facts
- **Queries** - observations with unbound elements
- **Hypotheticals** - non-canonical (what-ifs)

## Dictionary

Maps referents to text across multiple levels:
- System (generic)
- Setting (template-specific)
- World (instance-specific)
- Avatar (character-specific)
- User (player-specific)

---

## Implementation Notes for ClodRiver

The experimental modules in `clod/experimental/` map to CORVID concepts:
- `entity.clod` → Core Entity
- `observation.clod` → Observation model
- `relation.clod` → Relationships/Referents
- `semantic.clod` → Dictionary/meaning
- `llm.clod` → AI-driven behaviors
- `perms.clod` → Policy framework
- `vr.clod` → Spatial/world representation
