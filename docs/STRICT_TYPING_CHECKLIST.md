# Strict typing checklist (Tamaroyn)

Some Godot setups treat GDScript warnings as errors. To keep builds runnable, follow this checklist when editing or adding scripts.

## 1) Always declare return types
- ✅ `func foo() -> int:`
- ✅ `static func bar(name: String) -> PackedVector3Array:`

If a function omits a return type, callers can end up with **Variant** inference warnings.

## 2) Prefer explicit types over `:=` when the RHS might be Variant
Risky RHS examples:
- `Dictionary[...]` indexing or `dict.get(...)`
- `get_node_or_null(...)`
- `load(...)` (often returns `Resource`)
- Any function without an explicit return type

Safer patterns:
- ✅ `var n: Node = get_node_or_null("Foo")`
- ✅ `var tex: Texture2D = load(path)` (or check `ResourceLoader.exists(...)` first)
- ✅ `var id: int = int(d.get("id", -1))`

## 3) Type your arrays/dictionaries when they are long-lived
- ✅ `var ids: Array[int] = []`
- ✅ `var by_id: Dictionary[int, Node3D] = {}`

(Short-lived locals are less important, but still ok.)

## 4) Don’t return values pulled directly from an untyped Dictionary
Instead, convert/cast into a typed local and return the typed local.

## 5) Keep Wulfram import/parsing scripts extra strict
Binary parsing is a common source of Variant drift.

- Always type offsets/counters as `int`.
- Keep helper “result” structs/classes typed (e.g., `CStringReadResult`).
- Cache parsed results in typed containers where possible.
