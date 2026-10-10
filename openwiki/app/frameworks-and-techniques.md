---
type: Domain Model
title: Teaching frameworks and techniques catalog
description: The seven research-based frameworks bundled in the app, how techniques are defined in code (id, category, look-fors, exemplar phrases), how the registry and TechniqueService select them for analysis, and the stability rules for technique ids.
tags: [frameworks, techniques, tlac, danielson, rosenshine, avid, nbpts, psd-essentials, behavior-support]
openwiki:
  roles: [domain]
  change_kinds: [content, data-model]
  source_paths:
    - LessonLens/LessonLens/Core/Models/TeachingFramework.swift
    - LessonLens/LessonLens/Core/Models/Technique.swift
    - LessonLens/LessonLens/Features/Techniques/FrameworkRegistry.swift
    - LessonLens/LessonLens/Features/Techniques/TechniqueService.swift
    - LessonLens/LessonLens/Features/Techniques/Frameworks/TLACTechniques.swift
    - LessonLens/LessonLens/Features/Techniques/Views/FrameworkSelectionView.swift
    - LessonLens/LessonLens/Features/Analysis/AnalysisConfigurationSheet.swift
  symbols: [TeachingFramework, Technique, TechniqueCategory, FrameworkRegistry.techniques, TechniqueService.getEnabledTechniques, TechniqueService.migrateIncompleteTeechniqueNames]
  invariants:
    - Technique.id is the join key between prompts, backend replies, TechniqueEvaluation and Reflection self-ratings; it must stay stable and unique across frameworks.
    - Framework definitions are compiled into the app; the backend treats techniques as opaque input (max 20 per request).
  validation_commands:
    - xcodebuild -project LessonLens/LessonLens.xcodeproj -scheme LessonLens -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
---

# Teaching frameworks and techniques

## What is shipped

`TeachingFramework` (a `String` enum, raw value stored in `Analysis.frameworkId`) has seven cases, each with `displayName`, `shortName`, `description` and `learnMoreURL`:

| Case | Source file | Notes |
|---|---|---|
| `tlac` | `Frameworks/TLACTechniques.swift` | Curated subset (comment: the 10 techniques most identifiable from dialogue) of Lemov's Teach Like a Champion |
| `danielson` | `DanielsonTechniques.swift` | Domains 2 and 3 components |
| `rosenshine` | `RosenshineTechniques.swift` | Principles of Instruction |
| `avid` | `AVIDTechniques.swift` | WICOR |
| `nationalBoard` | `NationalBoardTechniques.swift` | Five Core Propositions |
| `psdEssentials` | `PSDEssentialsTechniques.swift` | ids prefixed `psd-` (e.g. `psd-formative-assessment-feedback`) |
| `behaviorSupport` | `BehaviorSupportTechniques.swift` | proactive/responsive behaviour strategies |

The product-facing description and attribution (trademarks are owned by the framework originators; the app is not affiliated) are in the root `README.md`.

## How a technique is defined

Each framework file exposes `static func createTechniques() -> [Technique]`. A `Technique` is a SwiftData `@Model` with `id` (unique, e.g. `no-opt-out`), `name`, `category` (`TechniqueCategory`: questioning, engagement, feedback, management, instruction, differentiation), `descriptionText`, `frameworkId`, `sortOrder`, and JSON-backed `lookFors` / `exemplarPhrases`. These last two are exactly what the prompt builder prints for the model ([shared prompts](../backend/shared-prompts.md)), so their wording is prompt content.

## Selection path

`FrameworkRegistry` (pure static switch over the enum) is the single place mapping a framework to its technique list; it also offers `allTechniques()`, `techniquesByCategory`, `defaultEnabledIds` (all ids) and lookup by id. `TechniqueService` (held by the [service container](overview.md)) caches per-framework lists and provides `getEnabledTechniques(for:enabledIds:)`, which is what the [lesson workflow](lesson-workflow.md) passes to `AnalysisService`/`VideoAnalysisService`. The user picks framework and techniques in `AnalysisConfigurationSheet` / `FrameworkSelectionView` / `TechniqueChecklistView` (last choices persisted via `UserSettings`). `FrameworkExplorerView` is the read-only browser. The [Growth dashboard](growth-dashboard.md) filters completed analyses by `Analysis.frameworkId`.

`TechniqueService.initializeTechniquesInDatabase` seeds built-in techniques into SwiftData once (called from `ContentView.onAppear`), and `migrateIncompleteTeechniqueNames` (typo is in the symbol name) is a one-time `UserDefaults`-guarded fix that replaces evaluation names that stored only a code like `3b` with the full technique name.

## Change recipes

- **Add or edit a technique**: edit the framework file; keep `id` unchanged for existing techniques (saved `TechniqueEvaluation.techniqueId`, `Reflection.selfRatings` and `focusTechniqueIds` reference it); set `frameworkId` and a unique `sortOrder`. Because the seeding in SwiftData only runs when no built-in rows exist, edits to existing rows do not rewrite stored `Technique` records, but analysis uses the registry (code) definitions, not the stored rows.
- **Add a framework**: add a `TeachingFramework` case with all five computed properties, a `*Techniques.swift` file, a case in `FrameworkRegistry.techniques(for:)`; then check exhaustive `switch` sites compile (build). Update the README framework list and `docs/help` content if user-visible.
- Keep the 20-technique request cap in mind (`CloudRunBackend/src/routes/analyze.ts`); a framework with more enabled techniques than that would be rejected with HTTP 400.
- No unit tests cover the catalog; validation is a build plus manual check in the Framework Explorer.
