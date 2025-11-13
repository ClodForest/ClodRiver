# Intelligent Systems Architecture for ClodRiver

**Date:** November 2025  
**Status:** Design Phase

This document captures architectural designs for three intelligent systems that work together to create compelling AI-driven experiences in LambdaMOO environments.

## Table of Contents

1. [NPC Relevance Scoring System](#npc-relevance-scoring-system)
2. [LLM-Fronted Parser and Prose Enhancement](#llm-fronted-parser-and-prose-enhancement)
3. [Dynamic World Building](#dynamic-world-building)
4. [Integration Architecture](#integration-architecture)

---

## NPC Relevance Scoring System

### Problem Statement

Traditional chatbot interfaces operate on explicit prompt-response cycles, making them poorly suited for multi-user virtual environments. NPCs need to participate naturally by:

- Responding when addressed or when dramatically relevant
- Remaining silent during unrelated conversations
- Processing continuous event streams without responding to every event
- Making contextually appropriate decisions about when to interject

### Solution: Tiered Relevance Scoring

#### Tier 0: Deterministic Pattern Matching (0-5ms)

Fast keyword and structural checks that immediately identify high-priority events:

```javascript
// Instant score 10 triggers
- NPC name mentioned in speech
- "say to [NPC]" verb used
- NPC is direct/indirect object of command
- Violence/danger keywords with NPC in same room

// Instant score 0 triggers  
- Events in different rooms
- System messages
- OOC (out of character) communication
```

**Implementation:** Simple regex/string matching in NodeJS bridge before invoking any LLM.

#### Tier 1: Lightweight LLM Scoring (100-200ms)

For events that pass Tier 0 but aren't immediately obvious, use a small local model (1.5B-3B parameters) for semantic relevance scoring.

**Model Options:**
- Qwen2.5-1.5B-Instruct (excellent instruction following, fast)
- Phi-3-mini 3.8B (strong reasoning for size)
- Llama-3.2-3B-Instruct (solid general performance)

**Resource Requirements:** 2-4GB VRAM with Q4/Q5 quantization, leaving 40GB+ for main response model.

**Prompt Structure:**

```
System: You are a relevance detector for an NPC. Output ONLY a JSON object.

NPC Profile:
- Name: Elara the Wise
- Role: Elderly wizard, keeper of arcane knowledge
- Current activity: Reading ancient tome in her study
- Personality: Helpful but easily distracted, values genuine curiosity

Recent Memory (last 5 minutes):
- Helped PlayerA with portal spell yesterday
- Currently researching planar rifts
- Annoyed by PlayerB's constant interruptions earlier

Recent Events (last 30 seconds):
- PlayerA enters from west
- PlayerA: "look"
- PlayerA: "wow, lots of books"
- PlayerC (in different room): "anyone seen a wizard?"

New Events (trigger for this check):
- PlayerA: "I've heard legends about this library"
- PlayerB enters from east

Scoring Guidelines:
- 0-2: Completely irrelevant to NPC
- 3-4: Peripherally relevant but no response warranted
- 5-6: Relevant to NPC's domain but response optional
- 7-8: Response appropriate if NPC is engaged
- 9-10: Response strongly warranted or expected

Output format:
{
  "score": 0-10,
  "reason": "brief explanation of scoring rationale",
  "suggested_response_type": "speech|emote|action|null"
}
```

**Response Threshold:** If score ≥ 7, invoke main Response LLM.

#### Tier 2: Full Response Generation

When relevance score crosses threshold, invoke the primary model (e.g., 27B parameter model at 6bpw quantization with 32K context) to generate actual NPC response.

### Context Management

The Observer LLM maintains rolling context but doesn't need complete world state:

**What the LLM Context Includes:**
- NPC's current state and recent activities
- Events in NPC's current location (last 2-5 minutes)
- Recent interactions with specific players
- Active goals or ongoing activities

**What Lives in MOO/Databases:**
- Complete world geography and object properties
- Long-term NPC memories (vector DB)
- Player character details and history
- Skill checks, combat mechanics, etc.

The MOO server dynamically constructs context from these sources when queried, keeping LLM context focused and efficient.

### Training Considerations

**Initial Approach: Prompt Engineering**
- Start with structured prompts and JSON mode
- Faster iteration than training
- Works well with 1.5B-3B models

**Future Enhancement: Specialized Model**
After accumulating 1000+ scored interactions:
- Train lightweight classifier on (events, context, score) tuples
- Potential for even faster and more accurate scoring
- Would reduce latency from 100-200ms to 50-100ms

**Training Data Sources:**
- MUD/MOO chat logs (NPCs naturally silent most of the time)
- Discord/IRC logs with bots
- Multi-party conversation logs with participation patterns

### Implementation Phases

**Phase 1: Single-tier LLM scoring**
- Implement Tier 1 only with lightweight model
- Log all (events, score, did_respond, outcome) tuples
- Establish baseline performance metrics

**Phase 2: Add Tier 0 optimization**
- Implement deterministic pattern matching
- Reduce unnecessary LLM calls by 60-80%
- Improve response latency for obvious cases

**Phase 3: Evaluate training**
- Analyze logged data for patterns
- Determine if custom-trained model would improve accuracy/speed
- Consider fine-tuning if clear benefit exists

---

## LLM-Fronted Parser and Prose Enhancement

### Problem Statement

Traditional MUD parsers like LambdaMOO's have significant limitations:

- **No context awareness:** "look again" doesn't remember what you looked at
- **Rigid syntax:** Commands must match exact verb patterns
- **Limited natural language:** Can't interpret "is the vase a mimic?" as a knowledge check
- **Repetitive output:** Same exact text for repeated commands
- **Brittle disambiguation:** The :oops system is a hack taken to its limits

Meanwhile, LLMs excel at exactly these problems: understanding context, interpreting intent, and generating varied natural language.

### Solution: Bidirectional Translation Layer

```
Player Natural Language Input
         ↓
[Context-aware Parser LLM]
         ↓
MOO Commands + Annotations
         ↓
MOO Execution (game mechanics)
         ↓
Raw MOO Output + Game State
         ↓
[Prose Enhancement LLM]
         ↓
Natural, Contextual Response
```

### Parser LLM: Natural Language → MOO Commands

#### Core Responsibilities

1. **Intent Recognition:** Understand what the player wants to do
2. **Context Tracking:** Remember recent actions and references ("it", "again", "there")
3. **Verb Translation:** Convert natural language to appropriate MOO verbs
4. **Disambiguation:** Handle unclear references intelligently
5. **Graceful Fallback:** Pass through to traditional parser when uncertain

#### Example Translations

```
Input: "look vase"
Output: {"command": "look vase", "context": {"target": "vase", "action": "examine"}}

Input: "look again"
Context: Last command was "look vase"
Output: {"command": "look vase", "context": {"repeated_action": true, "count": 2}}

Input: "keep looking"
Context: Looked at vase twice already
Output: {"command": "look vase", "context": {"repeated_action": true, "count": 3}}

Input: "is the vase a mimic?"
Analysis: Question format + monster type = knowledge check
Output: {"command": "check-skill survival vase-is-mimic difficulty:medium", 
         "context": {"type": "knowledge_check", "about": "vase"}}

Input: "reach inside the vase"
Output: {"command": "search vase", "context": {"method": "reaching_inside"}}
```

#### Parser Prompt Template

```
You are a command parser for LambdaMOO. Convert natural language to MOO commands.

Available Verbs: {verb_list_from_help_system}

Recent Session Context:
- Commands issued: {last_5_commands}
- Current room: {room_name}
- Objects in room: {visible_objects}
- Recent conversation: {last_3_speech_acts}
- Active target: {last_examined_object}

Player Input: "{player_text}"

Output JSON format:
{
  "command": "exact MOO command to execute",
  "context": {
    "action_type": "examine|interact|communicate|movement|skill_check",
    "target": "primary object of action",
    "repeated_action": boolean,
    "repetition_count": number,
    "confidence": 0.0-1.0
  },
  "fallback_to_moo_parser": boolean
}

If you cannot confidently parse the input, set fallback_to_moo_parser to true.
```

#### Verb Discovery and Help Integration

**Problem:** The parser needs to know what verbs exist and how to use them.

**Solution: Dynamic Help System Integration**

```javascript
// On startup and periodically (daily, or when verbs change)
async function updateVerbKnowledge() {
  const verbs = await moo.execute("@verbs");
  const helpText = await Promise.all(
    verbs.map(v => moo.execute(`help ${v}`))
  );
  
  // Construct LLM-friendly verb reference
  const verbReference = buildVerbReference(verbs, helpText);
  
  // Store in parser's system prompt or as retrievable context
  await updateParserContext(verbReference);
}

// Check if help needs updating
async function shouldUpdateVerbs() {
  const lastUpdate = await getLastVerbUpdate();
  const verbsModified = await moo.execute("@verbs-last-modified");
  
  return verbsModified > lastUpdate;
}
```

**Verb Reference Format:**

```
Verb: look
Usage: look [object]
Description: Examine an object or room in detail
Examples:
  - look vase
  - look around
  - look at wizard

Verb: check-skill
Usage: check-skill <skill-name> [difficulty]
Description: Test character's proficiency in a skill
Available skills: survival, arcana, perception, athletics, stealth
Difficulties: trivial, easy, medium, hard, extreme
Examples:
  - check-skill survival medium
  - check-skill perception
```

### Prose Enhancement LLM: MOO Output → Natural Language

#### Core Responsibilities

1. **Repetition Awareness:** Vary descriptions for repeated actions
2. **Context Integration:** Reference recent events naturally
3. **Tone Consistency:** Match world's voice and player expectations
4. **Mechanical Translation:** Convert dice rolls and stats to narrative
5. **Environmental Awareness:** Include relevant ambient details

#### Example Enhancements

```
Raw MOO Output:
"You see nothing special about the vase. [look #3]"

Enhanced Output:
"The vase is inert. It's just... sitting there, doing vase things, 
thinking vase thoughts. Other people in the room may have noticed 
you looking at the vase."

---

Raw MOO Output:
"Skill check: survival vs DC 12. Rolled 5+3=8. FAIL."

Enhanced Output:
"[rolled 5 + 3 = 8 survival]
You have no reason to suspect the vase of being a mimic."

---

Raw MOO Output:
"INITIATIVE ROLLED. Vase gets surprise round. 
Attack: 1d20+4=18 vs AC 15. HIT. Damage: 1d6+1=2.
Vase has grappled player."

Enhanced Output:
"The vase bites your arm and won't let go."
```

#### Prose Enhancement Prompt Template

```
You are a prose enhancement system for a MUD. Convert technical game output 
to engaging, context-aware narrative.

World Setting: {setting_description}
Tone Guidelines: {tone_preferences}

Current Scene Context:
- Location: {room_description}
- Present: {characters_present}
- Recent events: {last_3_events}
- Player's recent actions: {player_action_history}

Technical Game Output:
{raw_moo_output}

Metadata:
{
  "action_type": "skill_check|combat|examination|social",
  "repetition_count": 3,
  "dramatic_moment": true,
  "objects_involved": ["vase"],
  "mechanical_details": {"roll": "5+3=8", "dc": 12}
}

Guidelines:
1. Maintain world consistency and tone
2. If this is a repeated action (count > 1), vary the description
3. Convert mechanical details to natural language where appropriate
4. Reference environmental context naturally
5. Build dramatic tension for significant moments
6. Keep it concise - 1-3 sentences for most actions

Enhanced Output:
```

### Model Selection and Resource Allocation

**Option 1: Separate Models**
- Parser: Qwen2.5-7B (low temperature, ~4GB VRAM)
- Prose: Mistral-27B-6bpw (higher temperature, ~32GB VRAM)
- Total: ~36GB VRAM

**Option 2: Single Model, Dual Purpose**
- Use same 27B model for both with different system prompts
- Parser calls: temperature 0.3, JSON mode
- Prose calls: temperature 0.8, creative mode
- Total: ~32GB VRAM
- Benefit: Simpler architecture, shared context understanding

**Recommendation:** Start with Option 2 for simplicity, split later if performance requires.

### The Complete Flow: A Detailed Example

**Player Input:** "is the vase a mimic?"

**Step 1: Parser LLM Processing**
```json
{
  "command": "check-skill survival vase-is-mimic difficulty:medium",
  "context": {
    "action_type": "skill_check",
    "target": "vase",
    "skill": "survival",
    "about": "determining if object is a mimic"
  }
}
```

**Step 2: MOO Execution**
```
> check-skill survival vase-is-mimic medium
Roll: 1d20+3 = 5+3 = 8
DC: 12
Result: FAILURE
Output: "You cannot determine if the vase is a mimic."
```

**Step 3: Prose Enhancement**
```
Input to Prose LLM:
- Raw output: "You cannot determine if the vase is a mimic."
- Mechanical details: {"roll": "5+3=8", "dc": 12, "result": "fail"}
- Context: Player has examined vase 3 times already, showing paranoia

Enhanced output:
"[rolled 5 + 3 = 8 survival]
You have no reason to suspect the vase of being a mimic."
```

**Player Input:** "reach inside the vase"

**Step 1: Parser LLM Processing**
```json
{
  "command": "search vase",
  "context": {
    "action_type": "interact",
    "target": "vase", 
    "method": "reaching_inside",
    "potentially_dangerous": true
  }
}
```

**Step 2: MOO Execution (Mimic Reveal!)**
```
> search vase
INITIATIVE: Vase rolls 18, Player rolls 12
SURPRISE ROUND: Vase attacks
Attack roll: 18 vs AC 15 - HIT
Damage: 2 piercing
Status: Player is GRAPPLED by vase
Output: "The vase transforms and bites you! It has your arm grappled."
```

**Step 3: Prose Enhancement**
```
Input to Prose LLM:
- Raw: "The vase transforms and bites you! It has your arm grappled."
- Context: Player specifically tried to reach inside, triggering trap
- Dramatic moment: TRUE (mimic reveal after paranoid checking)

Enhanced output:
"The vase bites your arm and won't let go."
```

### Safety and Fallback Mechanisms

**Parser Failures:**
```javascript
if (parserOutput.confidence < 0.7 || parserOutput.fallback_to_moo_parser) {
  // Pass raw input to traditional MOO parser
  return moo.execute(playerInput);
}
```

**Prose Enhancement Issues:**
```javascript
if (proseEnhancement.length > rawOutput.length * 3) {
  // LLM got too creative, use raw output
  return rawOutput;
}

if (proseEnhancement.includes('[UNCERTAIN]') || 
    proseEnhancement.includes('[ERROR]')) {
  // Enhancement failed, use raw output
  return rawOutput;
}
```

**Logging for Improvement:**
```javascript
// Log all translations for analysis
await logParserDecision({
  input: playerInput,
  parsedCommand: parserOutput.command,
  mooResponse: rawOutput,
  enhancedResponse: proseOutput,
  playerFeedback: null, // filled in if player reports issue
  timestamp: Date.now()
});
```

---

## Dynamic World Building

### Vision

Instead of NPCs merely describing places, they can **manifest them into existence** when narratively appropriate. This goes beyond dialogue to actual world generation.

### Example Scenario

```
Player: "open the mystical door"
NPC Wizard: "Very well... behold!"

Behind the scenes:
1. NPC generates room description
2. System creates actual LambdaMOO room object
3. Creates exit from current room to new room
4. Populates room with objects based on description
5. Player can now 'go mystical-door' and enter real, persistent place
```

### Architecture

**Phase 1: Description Generation**

NPC Response LLM generates:
```json
{
  "response_type": "world_building",
  "dialogue": "Very well... behold!",
  "world_creation": {
    "room": {
      "name": "Mystical Landscape",
      "description": "Shimmering auroras dance across a purple sky...",
      "exits": ["back to wizard's tower"],
      "objects": [
        {"name": "crystal formation", "description": "..."},
        {"name": "floating orb", "description": "...", "interactive": true}
      ]
    }
  }
}
```

**Phase 2: MOO Object Creation**

NodeJS bridge translates to MOO commands:
```javascript
async function manifestRoom(worldCreation) {
  // Create room
  const roomId = await moo.execute(`@create $room named "${name}"`);
  await moo.execute(`@describe ${roomId} as "${description}"`);
  
  // Create exit from current location
  const exitId = await moo.execute(`@dig ${name} to ${roomId}`);
  
  // Create objects in room
  for (const obj of worldCreation.room.objects) {
    const objId = await moo.execute(`@create $thing named "${obj.name}"`);
    await moo.execute(`@describe ${objId} as "${obj.description}"`);
    await moo.execute(`@move ${objId} to ${roomId}`);
    
    if (obj.interactive) {
      await addInteractiveVerbs(objId, obj);
    }
  }
  
  return roomId;
}
```

**Phase 3: Persistence and Cleanup**

Dynamically generated content needs lifecycle management:

```javascript
// Tag generated content
await moo.setProperty(roomId, 'generated', {
  timestamp: Date.now(),
  generator: 'wizard-npc',
  session: sessionId,
  persistence: 'temporary' // or 'permanent'
});

// Cleanup policy
if (worldCreation.persistence === 'temporary') {
  setTimeout(() => {
    cleanupGeneratedRoom(roomId);
  }, 2 * 60 * 60 * 1000); // 2 hours
}
```

### Use Cases

1. **Quest Locations:** NPC quest-givers create dungeons/locations dynamically
2. **Player Housing:** Wizards conjure personalized spaces
3. **Random Encounters:** Traveling NPCs create temporary meeting places
4. **Dream Sequences:** Characters enter dynamically generated mindscapes
5. **Procedural Dungeons:** Infinite dungeon generation on demand

### Constraints and Safeguards

**Resource Limits:**
```javascript
const LIMITS = {
  maxRoomsPerSession: 5,
  maxObjectsPerRoom: 20,
  maxExitsPerRoom: 6,
  descriptionMaxLength: 2000
};
```

**Content Validation:**
```javascript
async function validateGeneration(worldCreation) {
  // Check for inappropriate content
  // Verify MOO property limits
  // Ensure no conflicts with existing geography
  // Validate object descriptions are reasonable
  return validationResult;
}
```

**Player Permissions:**
```javascript
// Only certain NPCs or in certain contexts
if (!npc.hasPermission('world_builder')) {
  return generateDialogueOnly(npcResponse);
}

// Or player must have certain quest status
if (!player.hasQuest('reality_bending')) {
  return "I cannot show you that which you are not ready to see.";
}
```

---

## Integration Architecture

### System Components

```
┌─────────────────────────────────────────────────────────┐
│                    NodeJS Bridge                         │
│  - Event stream management                               │
│  - Context aggregation                                   │
│  - Command execution                                     │
│  - LLM API coordination                                  │
└────────┬────────────────────────────────────────────┬───┘
         │                                             │
    ┌────▼─────┐                                  ┌───▼────────┐
    │  Parser  │                                  │ NPC System │
    │   LLM    │                                  │            │
    │          │                                  │ ┌────────┐ │
    │ Natural  │                                  │ │Relevance││
    │ Language │                                  │ │Scorer  ││
    │    to    │                                  │ └────┬───┘ │
    │   MOO    │                                  │      │     │
    │ Commands │                                  │ ┌────▼───┐ │
    └────┬─────┘                                  │ │Observer│ │
         │                                        │ │  LLM   │ │
         │                                        │ └────┬───┘ │
         │                                        │      │     │
    ┌────▼──────────────────────────────┐        │ ┌────▼───┐ │
    │     LambdaMOO Server              │        │ │Response│ │
    │                                   │        │ │  LLM   │ │
    │  - Game mechanics                 │        │ └────────┘ │
    │  - Object persistence             │        └─────┬──────┘
    │  - Verb execution                 │              │
    │  - World state                    │              │
    └────┬──────────────────────────────┘              │
         │                                             │
    ┌────▼─────┐                                  ┌───▼────────┐
    │  Prose   │                                  │  Vector    │
    │Enhancement│                                  │  Database  │
    │   LLM    │                                  │            │
    │          │                                  │  (NPC      │
    │   MOO    │                                  │  Memories) │
    │  Output  │                                  │            │
    │   to     │                                  └────────────┘
    │ Natural  │
    │ Language │
    └──────────┘
```

### Data Flow Example

**Scenario:** Player examines vase repeatedly, asks if it's a mimic, reaches inside

```
1. Player types: "look vase"
   ├─> Parser LLM: "look vase" → {command: "look vase", target: "vase"}
   ├─> MOO executes: Returns description
   └─> Prose LLM: Enhances description
   
2. Player types: "look again"
   ├─> Parser LLM (with context): Remembers vase → {command: "look vase", repeated: true}
   ├─> MOO executes: Returns same description
   └─> Prose LLM: Generates varied text noting repetition
   
3. Player types: "keep looking"
   ├─> Parser LLM (with context): Third time → {command: "look vase", repeated: 3}
   ├─> MOO executes: Returns description
   └─> Prose LLM: Humorous response about obsessive examination
   
4. Player types: "is the vase a mimic?"
   ├─> Parser LLM: Recognizes knowledge check → {command: "check-skill survival"}
   ├─> MOO executes: Rolls dice, returns failure
   └─> Prose LLM: "You have no reason to suspect..."
   
5. Player types: "reach inside the vase"
   ├─> Parser LLM: Dangerous interaction → {command: "search vase"}
   ├─> MOO executes: MIMIC REVEAL! Combat begins
   └─> Prose LLM: "The vase bites your arm and won't let go."
   
6. Meanwhile, NPC in room observing:
   ├─> Observer LLM processing events continuously
   ├─> Relevance Scorer: Events 1-4 score low (player examining vase)
   ├─> Event 5: "reach inside vase" → Mimic attacks player
   ├─> Relevance Scorer: SCORE 9 (combat initiated, player in danger)
   └─> Response LLM: NPC shouts warning or casts protection spell
```

### Performance Considerations

**Latency Budget:**
- Tier 0 relevance check: <5ms (deterministic)
- Tier 1 relevance check: 100-200ms (small LLM)
- Parser LLM: 200-500ms (7B model)
- Prose LLM: 300-800ms (27B model)
- Response LLM (NPC): 500-1500ms (27B model)

**Parallelization Opportunities:**
```javascript
// Parser and NPC relevance scoring can run in parallel
const [parsedCommand, relevanceScore] = await Promise.all([
  parsePlayerInput(input),
  scoreRelevanceForNPCs(input, context)
]);

// If NPC response warranted, generate in parallel with prose enhancement
if (relevanceScore >= 7) {
  const [enhancedProse, npcResponse] = await Promise.all([
    enhanceProse(mooOutput),
    generateNPCResponse(context)
  ]);
}
```

**Resource Management:**
```javascript
// Model loading strategy
const modelPool = {
  relevanceScorer: loadModel('qwen2.5-1.5b-q5'),  // Always loaded
  parser: shareWith('main'), // Share main model
  prose: shareWith('main'),  // Share main model  
  npc: loadModel('mistral-27b-6bpw')  // Main model, always loaded
};

// Context window management
const MAX_CONTEXT = {
  parser: 8192,      // Short-term command context
  prose: 4096,       // Just recent events for enhancement
  relevance: 4096,   // Rolling window of room events
  npcObserver: 32768 // Full session context with pruning
};
```

### Configuration and Tuning

**Settings File Structure:**
```json
{
  "models": {
    "relevance_scorer": {
      "model": "qwen2.5-1.5b-instruct-q5",
      "max_tokens": 100,
      "temperature": 0.3,
      "threshold": 7
    },
    "parser": {
      "model": "shared",
      "max_tokens": 200,
      "temperature": 0.3,
      "confidence_threshold": 0.7
    },
    "prose": {
      "model": "shared",
      "max_tokens": 500,
      "temperature": 0.8,
      "repetition_penalty": 1.2
    },
    "npc_response": {
      "model": "mistral-27b-6bpw",
      "max_tokens": 1000,
      "temperature": 0.9,
      "top_p": 0.95
    }
  },
  "performance": {
    "parallel_processing": true,
    "max_concurrent_llm_calls": 3,
    "parser_cache_size": 1000,
    "context_pruning_strategy": "sliding_window"
  },
  "features": {
    "world_building_enabled": true,
    "max_generated_rooms_per_session": 5,
    "temporary_room_lifetime_hours": 2
  }
}
```

### Monitoring and Debugging

**Metrics to Track:**
```javascript
const metrics = {
  relevanceScoring: {
    avgLatency: 0,
    falsePositives: 0,  // Score high but response not needed
    falseNegatives: 0,  // Score low but should have responded
    tierDistribution: {0: 0, 1: 0}  // How often each tier used
  },
  parser: {
    avgLatency: 0,
    fallbackRate: 0,  // How often falls back to traditional parser
    avgConfidence: 0,
    errorsPerHour: 0
  },
  prose: {
    avgLatency: 0,
    avgLengthRatio: 0,  // Enhanced length / raw length
    playerFeedback: {positive: 0, negative: 0}
  },
  overall: {
    endToEndLatency: 0,
    playerSatisfaction: 0,
    npcEngagement: 0
  }
};
```

**Debug Logging:**
```javascript
// Detailed logging for development
logger.debug({
  event: 'player_command',
  input: playerInput,
  parsed: {
    command: parsedCommand,
    confidence: confidence,
    context: parserContext
  },
  moo: {
    command: mooCommand,
    output: rawMooOutput,
    executionTime: mooLatency
  },
  prose: {
    enhanced: enhancedOutput,
    generationTime: proseLatency
  },
  npc: {
    relevanceScore: score,
    responded: npcDidRespond,
    response: npcResponse
  },
  totalLatency: endToEndLatency
});
```

---

## Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)
- [ ] Set up NodeJS bridge with basic MOO connection
- [ ] Implement Tier 1 relevance scoring with lightweight LLM
- [ ] Create simple NPC that responds to high-relevance events
- [ ] Basic logging and metrics collection

### Phase 2: Parser System (Weeks 3-4)
- [ ] Implement Parser LLM with context tracking
- [ ] Integrate MOO help system for verb discovery
- [ ] Add fallback to traditional parser
- [ ] Test with 20+ example commands

### Phase 3: Prose Enhancement (Weeks 5-6)
- [ ] Implement prose enhancement LLM
- [ ] Handle repetition awareness
- [ ] Convert mechanical output to narrative
- [ ] A/B test enhanced vs raw output with users

### Phase 4: Optimization (Weeks 7-8)
- [ ] Add Tier 0 deterministic relevance checks
- [ ] Implement parallel processing where possible
- [ ] Optimize context window usage
- [ ] Performance tuning and caching

### Phase 5: World Building (Weeks 9-12)
- [ ] NPC world-building response generation
- [ ] MOO object creation from descriptions
- [ ] Persistence and cleanup systems
- [ ] Safeguards and validation

### Phase 6: Polish and Production (Weeks 13-16)
- [ ] Comprehensive testing with multiple NPCs
- [ ] User feedback integration
- [ ] Documentation and configuration tools
- [ ] Deployment to production environment

---

## Open Questions and Future Research

1. **Relevance Scoring Accuracy**
   - What is acceptable false positive/negative rate?
   - How does scoring quality degrade with model size?
   - Can we achieve <100ms with acceptable accuracy?

2. **Context Window Strategies**
   - What pruning strategies best maintain coherence?
   - How much context do different LLM tasks actually need?
   - Can we dynamically adjust context based on complexity?

3. **Multi-NPC Coordination**
   - How do multiple NPCs avoid stepping on each other?
   - Should there be a "conversation manager" for group scenes?
   - How to handle NPCs with conflicting goals?

4. **World Building Quality**
   - How do we ensure generated locations are interesting?
   - What constraints prevent degenerate or boring generation?
   - Can NPCs collaboratively build complex locations?

5. **Player Experience**
   - Do players prefer enhanced prose or traditional output?
   - Does natural language input reduce frustration?
   - How do we balance "magic" with player agency?

6. **Training and Fine-tuning**
   - Would purpose-trained models significantly outperform prompted ones?
   - What would optimal training data look like?
   - Is the effort worth the improvement?

---

## Conclusion

This architecture represents a significant evolution beyond traditional MUD systems and simple chatbot integrations. By combining:

- **Intelligent relevance scoring** for natural NPC participation
- **Context-aware parsing** for flexible player input
- **Prose enhancement** for engaging, varied output  
- **Dynamic world building** for emergent storytelling

...we create a system where AI agents genuinely participate in virtual worlds rather than merely responding to prompts. The key insight is that each component handles the task it's best suited for:

- Small, fast models for relevance scoring and pattern matching
- Medium models for parsing and prose enhancement
- Large models for creative generation and NPC personality
- MOO for game mechanics, persistence, and world state
- Vector databases for long-term memory
- Graph databases for relationships and knowledge

The result is a system that feels magical to players while remaining technically grounded and performant. NPCs that seem alive, commands that "just work," and a world that responds and grows with player actions.

## Next Steps

Get some sleep, then start with Phase 1 implementation during the day. The foundation is solid, the vision is clear, and the technology is ready. Time to build something genuinely new in the MUD space.
