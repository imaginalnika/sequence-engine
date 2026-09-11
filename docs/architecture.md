# Runtime and graph format

`graph_sequence.gd` owns state and evaluates conditions and turns. `graph_validator.gd` checks graph structure before replacement. `question_runner.gd` adds the lazy async judging loop without tying it to a specific LLM.

Input: `{start, nodes, edges, variables}`. Node IDs are strings. Each node is an object with optional `title`, `direction`, `first_message`, and `type` (`terminal` or `script`). Edges contain `from`, `to`, optional numeric `priority` (lower first), and optional `condition_ast`.

Supported expressions:

| Expression | Meaning |
| --- | --- |
| `null` | Unconditional |
| `["and", ...]`, `["or", ...]`, `["not", expression]` | Boolean composition |
| `["var", "name"]` | Declared boolean or question-backed variable |
| `["q", "question"]` | Caller-supplied boolean answer |
| `["action", "name"]` | `action_query` callback |
| `["turn", ">=", 2]` | Current/pending turn count |
| `["visit", ">=", 2, "node_id"]` | Per-node visit count |

Variables may be `{name: bool|string|{type, value}}` or an array of `{name, type, value}`. Strings describe questions rather than arbitrary string-comparison values. Comparison operators are `>=`, `<=`, `>`, `<`, `=`, and `==`.

Arrival counts as turn 1. `begin_turn()` prepares the following turn number. `queue_transition()` prepares a destination. `commit_pending()` applies state; `clear_pending()` discards the work. `snapshot()` returns a deep copy. `restore()` falls back to the start node if a saved node no longer exists. The host decides whether to resume a terminal node or reset it.

Signals: `transitioned(previous, current)`, `state_changed(snapshot)`, `terminal_reached(node)`.

The host owns persistence, timeouts for its judge callback, and presentation. Do not share one engine between simultaneous conversations. The question runner's generation counter ignores late answers after cancellation.
