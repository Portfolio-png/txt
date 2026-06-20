# Parallel Branching UX Backlog

## Context
During the shift to a Multi-Pipeline Horizontal Canvas view (stacking multiple pipeline runs into rows for a single order), we recognized that **parallel branching** (splits and merges in a pipeline) presents a UX challenge.

## Current State
The multi-pipeline layout renders nodes horizontally based on their `stageIndex`. To accommodate parallel routes, nodes with the same `stageIndex` but different `laneIndex` are stacked vertically within that specific stage column.

## Problem
While this layout preserves the functionality, the learning curve for users to understand "stacked" nodes as parallel routes (as opposed to sequential routes) is steep without clear, explicit UI cues (like bezier curves that were present in the 2D canvas). 

## Action Items
1. **Design a better visual cue** for parallel splits/merges in a linear list view.
2. **Implement an onboarding/learning curve** feature (e.g., tooltips, guided tours) to explain parallel routing when a user first encounters it.
3. Explore if parallel branching should be simplified or if the "stacked" UI can be enhanced with clearer connecting lines.
