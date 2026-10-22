# LessonLens: Productization Options (Use Outside PSD)

**Context:** Industry coverage of LessonLens raised the question of whether it could be useful beyond Peninsula SD. This document compares distribution models so the *platform port* (see `CROSS_PLATFORM_PORTING_PLAN.md`) and the *distribution model* decisions can be reasoned about together.

**Status:** Exploratory. No commitment to any model. Nothing here needs deciding now; the coverage creates option value, not obligation.

---

## 1. The real problem is the trust boundary, not the OS

"Port to Windows" is mostly mechanical. "Useful outside PSD" is the bigger change because several parts of the architecture are currently hardcoded to the district, independent of operating system:

- **1.1 Identity:** OAuth is domain-restricted to the district domain (client + backend). Other orgs need their own domain or a generic sign-in.
- **1.2 Backend ownership:** The Cloud Run backend is PSD infrastructure on PSD Gemini billing. Requests from other districts would hit PSD's bill and pass through PSD servers.
- **1.3 Distribution:** Self-Service / Jamf / Intune assumes managed district devices. External users have neither.
- **1.4 Privacy posture:** The current privacy story is credible because it is one district, voluntary, and union-aware. Routing another district's teacher data through PSD's backend changes the liability and data-control picture entirely.

The hard part of going external is the trust/data/billing boundary, not the UI framework.

---

## 2. The three models at a glance

| Axis | Open-source self-hosted | Bring-your-own-key app | Hosted SaaS |
|---|---|---|---|
| You ship | Code + deploy docs | Signed app, thin/no backend | A running service |
| Who runs the backend | Each org | Nobody (or each org) | You |
| Who pays Gemini | Each org | Each user/org | You (then bill them) |
| Whose data flows through you | None | None | Everyone's |
| Reach | Technical orgs only | Solo teachers to districts | Anyone |
| Your liability | Minimal | Low | High (data processor) |
| Privacy story | Stays intact | Stays strong | Must be rebuilt |
| Ongoing burden | Low (releases) | Medium (app + key UX) | High (ops, support, billing, compliance) |

---

## 3. Open-source, self-hosted

- **3.1 Technical:** Closest to the current code. Backend is portable, prompts are shared. Work is the cross-platform client plus removing PSD-hardcoded pieces (domain restriction, infra IDs) and writing deploy docs.
- **3.2 Legal:** You publish software, not a service. No student data touches you. License choice matters (permissive vs. copyleft, plus brand/trademark protection now that the "LessonLens" name appears in articles).
- **3.3 Privacy:** Best preserved. Each org owns its data, keys, and backend. The existing union/privacy framing transfers cleanly because the trust boundary stays inside each district.
- **3.4 Tradeoff:** Only reaches orgs with IT capacity to deploy a backend and manage a Gemini project. A solo teacher in another district cannot use it.

---

## 4. Bring-your-own-key app

- **4.1 Technical:** Cross-platform client plus a first-run flow where the user supplies their own Gemini key, stored in the OS keyring. Backend shrinks to thin or zero (client calls Gemini directly, or a stateless relay that does not log). The on-device transcription decision (porting plan §4) matters most here, since there is no central server to lean on.
- **4.2 Legal:** You never see anyone's audio, transcripts, or billing. Liability stays low. Main duties are honest disclosures and not logging.
- **4.3 Privacy:** Strong, and arguably a better public story than today: the vendor literally cannot see user data because the user's own key talks straight to Google.
- **4.4 Tradeoff:** Key management is the UX hurdle. Non-technical teachers need a dead-simple way to obtain and paste a Gemini key, or the app dies on first run. Harder to enforce safe usage or push fixes to misconfigured users.

---

## 5. Hosted SaaS

- **5.1 Technical:** The biggest lift. Multi-tenancy, per-org isolation, accounts, billing/metering, abuse controls, and a backend that must become robust and observable. The current stateless single-tenant design would be substantially re-architected.
- **5.2 Legal:** You become a data processor for other people's classroom recordings. That pulls in FERPA-adjacent obligations, data processing agreements per district, breach responsibility, and retention policies. A real business with real exposure.
- **5.3 Privacy:** The current "the backend cannot see who or what" guarantee does not survive unchanged. You would design a new privacy model and defend it to many districts, not one union.
- **5.4 Tradeoff:** Easiest for end users and widest reach, but converts a side project into an operational and legal commitment.

---

## 6. How each maps to the repo decision

- **6.1 Self-hosted / BYO-key:** A clean separate public repo makes sense. De-PSD'd, neutral branding, its own license. Keep the PSD Mac app in the current repo. Optionally extract the shared backend/prompts into a small package both consume.
- **6.2 SaaS:** Definitely separate, and likely a private product repo, because the infrastructure and compliance surface should not sit next to district-internal code.
- **6.3 General:** "Useful outside PSD" points away from in-repo replacement and toward a distinct project. The earlier in-repo recommendation (in the porting plan discussion) held only for the "replace the Mac app for PSD" goal.

---

## 7. Read on the options (evidence-based, not a recommendation to act)

- The lowest-risk path that matches the existing architecture and privacy story is the **BYO-key cross-platform app**, with **self-hosted OSS** as a natural companion for districts that want their own backend.
- **SaaS** is the only model that changes what LessonLens *is*: a product and a liability, not a tool. Worth excluding early unless the intent is to build a company around it.

---

## 8. Open questions

1. Audience priority: solo teachers in other districts, whole districts, or both?
2. Is monetization on the table, or is this purely about usefulness/reach?
3. Brand/trademark: is "LessonLens" being protected before wider public release?
4. License intent if open-sourced (permissive vs. copyleft)?
5. Appetite for any ongoing operational/support burden, or strictly ship-and-forget?
