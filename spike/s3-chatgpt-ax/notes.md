# S3 — ChatGPT Desktop AX

## Status: 🟢 MOSTLY PASS (current version, 2026-06-08) — single-version, so formally PARTIAL
Tested ChatGPT Desktop **1.2026.119** (`com.openai.chat`). Accessibility granted to Terminal.

### Key findings
1. **⚠️ ChatGPT exposes NOTHING via AX until you opt in.** A naive probe sees only an
   `AXHostingView` group with 3 unnamed buttons — no input, no messages. After setting
   **`AXManualAccessibility` + `AXEnhancedUserInterface`** = true on the app element (the same
   trick that revealed Chromium content in S6), the full tree appears.
2. **Input is locatable + stable anchors.** With the opt-in, the input is an `AXTextArea` at
   `AXApplication → AXWindow → AXHostingView → AXSplitGroup → AXHostingView → AXScrollArea →
   AXTextArea`. The send button has a STABLE identifier:
   `MessageInputPrimaryButtonContainerPart.PrimaryButton` (good anchor for locating the input
   region deterministically, rather than "first AXTextArea").
3. **Two text-injection methods both work:**
   - **AX set-value** (`kAXValueAttribute`) — ✅ reliable, no clipboard, no keystrokes
     (readback confirmed). **Recommended primary path.**
   - **Synthetic Cmd+V paste** — ✅ works once the input is truly focused; ❌ failed on a
     cold first attempt (focus race). Needs a frontmost+focus wait, like S6/S4.
4. **Clipboard restore works** (baseline clipboard verified intact after the paste test).
5. **Submit NOT tested** — sending a message is an outward action; per spec §10 ChatGPT must
   not auto-press Enter anyway. Send button id is known for a future user-confirmed click.

### Evidence
`ax_tree_current.txt` (pre-opt-in, sparse), `ax_tree_optin.txt` (post-opt-in, full tree).

## Hypothesis
ChatGPT Desktop's input AX path is stable enough that "find input → paste → submit" is
reliable across the current + previous stable versions.

## Pass criterion
Input element locatable deterministically in current version; same path confirmed in the
previous build (or Accessibility Inspector snapshot if no archived installer).

## Versions tested
- Current: <fill>
- Previous: <fill or "not available">

## Input element path
- Current: <fill>
- Previous: <fill or n/a>

## Paste experiment
- Text appeared in input: ?
- Clipboard restored: ?

## Conclusion
[x] **PARTIAL → trending PASS.** Current version: input is reliably locatable (with the
`AXManualAccessibility` opt-in) and text injection works (AX set-value preferred; Cmd+V as
fallback). Formally PARTIAL only because **multi-version stability was not tested** (single
installed version 1.2026.119 — no previous build to diff). ChatGPT delivery does NOT need to be
clipboard-only; AX injection is viable.

## Spec patch
- §7.5: ChatGPT delivery = **AX injection viable** (not clipboard-only). MUST set
  `AXManualAccessibility`/`AXEnhancedUserInterface` on the app first, else the input is invisible.
  Primary inject = `kAXValueAttribute` set-value; Cmd+V is a fallback needing a focus wait.
  Locate the input via the stable send-button id `MessageInputPrimaryButtonContainerPart.PrimaryButton`,
  not "first AXTextArea". Do NOT auto-submit (per §10) — leave the user to press Enter.
- §6.2 / Compatibility Matrix: ChatGPT `com.openai.chat` 1.2026.119 — AX requires opt-in;
  input = AXTextArea; confidence = medium (one version tested).
- §14.1 S3: RESULT = PARTIAL/PASS (single-version); multi-version diff deferred.

## Follow-ups
- Re-probe after a ChatGPT update to confirm the AXTextArea path + send-button id are stable
  across versions (the actual S3 hypothesis). Until then, confidence is single-version.
