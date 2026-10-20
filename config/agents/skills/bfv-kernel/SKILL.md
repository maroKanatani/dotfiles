---
name: bfv-kernel
description: "依頼に「BFV Kernelを適用して」と明記されたときだけ使用する。Contract(Objective、Acceptance Criteria、Constraints、Non-goals)を定義し、各ClaimにDeletion Testを課して必要な作業だけで成果契約を証明し、Fixed Pointで停止する作業規律。明記のない通常の依頼には使用しない。"
---

# BFV Kernel

必要な作業だけで成果契約を証明し、Fixed Pointで停止するために以下を適用する。

## Contract

- 実装前に、Objective、Acceptance Criteria、Constraints、Non-goalsを定義する。ここで、Contractは必要な成果の下限であり、作業範囲の上限でもある。
- 曖昧さは利用者へ確認する。確認できない場合は、依頼と既知の文脈に整合する最も狭い解釈を採用し、推測でContractを広げない。

## ClaimとDeletion Test

- 計画、変更、テスト、調査、リファクタリング、文書化、追加検証、新たな発見をClaimとして列挙する。
- 各Claimの実行前に「これを削除しても、現在の入力と環境でContractを証明できるか」を問う。証明できるなら棄却する。
- 証明できない場合は、破綻するAcceptance Criterion、観測可能な失敗、必要なEvidence、失敗を防ぐ最小形を明らかにし、最小形だけを採用する。
- 報告済み、重大、有用、着手済み、時間を費やしたという理由だけでは、Claimを必要とみなさない。

## Executionと新たなClaim

- Contract定義、Claim列挙、Deletion Test、採用Claimの実行、全Acceptance Criteriaの検証、新たなClaimの評価、Fixed Point判定の順で進める。
- 新たな発見は自動的に作業へ加えない。未解決のままでは現在のContractを証明できない場合だけ、影響するAcceptance Criterionと最小形を示して採用する。

## Evidenceと現在条件

- Acceptance CriterionごとにEvidence、再現方法、関連する入力・状態・設定・実行環境、`PROVEN`または`UNPROVEN`の状態を示す。
- テスト、ログ、計測、調査もClaimである。省くとContractを証明できない場合だけ追加し、証拠量そのものを目的にしない。
- 必要性は現在の入力と環境で起きる観測可能な失敗に結び付ける。理論上の可能性だけで作業を増やさない。

## Limits、Rounds、Fuse

- 利用者、対象仕様、適用される方針、またはContractの証明に必要な計測に根拠がない数値上限、閾値、タイムアウト、再試行回数などを作らない。
- 1 Roundは、Claim列挙、Deletion Test、実行、Contract再検証、新たなClaim収集で構成する。外部安全機構であるFuseの最大は3 Roundsとする。
- 3 RoundsでFixed Pointに達しなければ停止し、未解決のClaimを報告する。`FUSE_STOPPED`を完了として扱わない。

## Fixed Pointと完了報告

- Contractが証明され、残るClaimが一つもDeletion Testを通過しない状態をFixed Pointとする。到達したら、より広く、きれいに、将来向けにできるという理由で続行しない。
- 完了報告はOutcome、各Acceptance CriterionとEvidence、利用者が知る実益のあるRejected Claims、Fuse停止時のOpen Items、`COMPLETED`または`FUSE_STOPPED`のStatusに限定する。
- 推測による完了、Evidenceなしの完了、目的外の改善、便乗リファクタリング、証拠の水増し、着手済みClaimの惰性維持、Fixed Point後の追加レビューを禁止する。
