# pstack model configuration. One line per role. Delete a line to fall back to the skill default.
# `inherit-parent` or `auto` as a value: the role runs on the parent chat model (omit Agent `model`). Alias entries in a panel list still count toward its fan-out.
# budget: medium (high)
feature, refactoring: inherit-parent
bug-fix: inherit-parent
perf-issue: inherit-parent
hillclimb: inherit-parent
judgment and prose: fable high
hardest tasks: fable high
how explorer: inherit-parent
how explainer: fable high
why investigators: inherit-parent
why synthesizer: fable high
reflect tooling: inherit-parent
reflect judgment, divergent, synthesizer: fable high
arena runners: fable high, opus high
arena cross-judge pool: fable high, opus high
swarm workers: inherit-parent
architect runners: fable high, opus high
interrogate reviewers: fable high, opus high
