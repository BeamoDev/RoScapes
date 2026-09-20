# Src Notes

See the repo-root `AGENTS.md` for the main project guide.

Extra note for work inside `src/`:
- Normal levels are generated from template letters, not stored as fixed crossword layouts.
- If a report mentions a numbered level, verify whether it maps to a sparse `LevelTemplate` key before assuming the template ID matches the displayed level number.
