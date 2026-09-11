# sequence-engine

A Godot runtime for conditional, turn-aware dialogue graphs.

Load JSON graphs, evaluate conditions, ask only the questions needed to resolve a branch, and commit transitions when a conversation turn completes. The runtime has no editor, account system, model dependency, or project autoload requirement.

## Features

- Boolean variables, question-backed variables, action predicates, and nested conditions.
- Priority-ordered edges, turn/visit counters, and silence-aware branching.
- Prepare/commit/cancel transitions for interruptible conversations.
- Serializable state and host-supplied persistence.
- Optional asynchronous question judging through a `Callable`.

## Quick start

Tested with Godot 4.7.1. From this repository:

```sh
godot --headless --path . --script examples/demo.gd
python3 tools/verify.py
```

Copy `addons/sequence_engine` into a Godot project. No plugin activation is required.

```gdscript
var engine = preload("res://addons/sequence_engine/graph_sequence.gd").new()
var errors = engine.configure(graph_dictionary)
if errors.is_empty():
    engine.begin_turn()
    var edge = engine.select_edge({"Is the visitor ready?": true})
    if not edge.is_empty(): engine.queue_transition(edge["to"])
    engine.commit_pending()
```

Use `question_runner.gd` if the host needs to obtain question answers asynchronously. It prepares a transition; the host commits after the corresponding response completes. Cancelling must invalidate the runner and clear pending state.

## Documentation

The engine consumes JSON graphs. Graph authoring, presentation, and persistence are handled by the host application.

See [architecture and graph format](docs/architecture.md) and [security](SECURITY.md).

## License

Apache-2.0; see [LICENSE](LICENSE) and [NOTICE](NOTICE). Godot is a separate MIT-licensed dependency.
