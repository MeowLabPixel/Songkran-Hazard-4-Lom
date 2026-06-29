# Project Rules

- **CRITICAL**: Never modify, rewrite, or touch any `animationTree` `.tres` files (e.g., `animation_tree.tres` or similar animation tree resource files). Editing or replacing these files causes them to malfunction in Godot. Always inspect and edit these resources only through the Godot editor UI or via alternative safe methods, but never direct file writes/modifications.

- **Godot Editor Operations**: If a task requires modifying scene layouts, attaching scripts in scenes, or configuring inspector values, do NOT write external scripts (like Python or GDScript run scripts) or try complex scene-file hacks to automate it. Instead, **directly describe the steps and instruct the user to make the modification manually in the Godot Editor UI** to conserve token/quota usage.

