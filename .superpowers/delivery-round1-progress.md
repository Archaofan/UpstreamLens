# SDD ledger — plan: docs/plans/2026-09-29-delivery-round1.md

Pre-flight: T2→T5 (models consumed by AppModel), T3/T4→T6 (engine+client consumed by UI), T5→T6 (probe closures). No conflicts found: closures injected with defaults keep test call sites compiling.

Ruling (process): 本机无 Xcode，无法本地跑测试 — TDD 红绿循环改为"同批提交代码+测试，推送分支后以 Actions 单测为红绿门"；每批 commit 对应一个任务，Actions 红则修复回归。
Task T1-T8, T9: code+tests+README committed in one batch — Ruling: 无本地 Xcode，无法逐任务本地跑测试，红绿门统一由 Actions 承担（见计划 Global constraints）。
