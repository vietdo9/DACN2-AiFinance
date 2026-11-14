# DACN2 agent workflow

Follow the project guidelines in `.agents/rules/finwise_development_guidelines.md`.

## User's model preference

- For project work, delegate implementation to GPT-6 Luna (`gpt-6-luna`). When selecting this model, spawn with `fork_turns="none"` and supply the relevant task context and project instructions explicitly.
- The coordinating Sol agent reviews Luna's work, checks correctness and relevant validation, and reports the result to the user.
- Send implementation corrections back to Luna; the coordinating agent should focus on review rather than writing the implementation itself.
- Do not silently substitute a different implementation model if Luna is unavailable; explain the limitation to the user.
