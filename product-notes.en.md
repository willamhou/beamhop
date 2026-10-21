# Get the handoff right.

Beamhop product discussion and decisions · October 19, 2026

Someone finds evidence on a web page, thinks of work already underway, sends it over, and keeps reading. If that action feels easy enough, Beamhop has a reason to exist.

These notes collect the ideas, corrections, and product suggestions from this conversation. They retain the force of the judgments made in the discussion while distinguishing agreed product boundaries from design hypotheses that still need testing. The two interactive essays are [“Send the information. Stay where you are.”](./handoff.en.html) and [“Work can branch. Keep your train of thought.”](./work-in-hand.en.html).

## Start with one handoff

Beamhop’s main action is to select material in the current app and send it, with its source and any necessary instructions, to an external agent session already at work. The reader should be able to keep their place and train of thought as far as possible.

There are two searches to reduce: finding the destination before sending, and recovering the train of thought afterward. Adding context should not require managing a workspace first.

An earlier demo had Beamhop generate suggestions and edit drafts directly. We pulled back from that direction: reasoning, execution, and results should remain in external tools such as Codex. Beamhop needs to handle capture, provenance, destinations, instructions, handoff status, and recovery from failure.

Likewise, showing a few ready-made target documents did not explain why destinations are hard to find. The product must help people recognize the right work and spend less time finding it again once they have confirmed it.

## Borrow from familiar human actions

The discussion began with newspaper clippings, but there is more to borrow than cutting and pasting. People point, hold a few sheets, stack related material, leave a note in a margin, and set unfinished work aside on the desk.

These actions are useful because they retain both content and intent.

- **Point.** The selection says “this”; the confirmed destination says “there.” A complete prompt need not precede every handoff.
- **Hold.** Keep the original and its source while someone is still deciding how to use them.
- **Stack.** Send several pieces together, retaining their order. The grouping itself says that they should be understood together.
- **Leave a note.** An unsent instruction can preserve where a thought left off.
- **Set down and pick up.** After another task interrupts, restore the material, order, destination, and note.
- **Recognize the place.** Projects, recent discussion, and personal labels help people recognize work without memorizing session titles.

Clico’s “bring agent to the pages” and [Manuscript](https://manuscriptapp.github.io/manuscript/#features) prompted this discussion. Beamhop needs to apply those ideas to actual handoffs between apps. These references do not establish what integrations either product supports.

## The destination can outlast the session

“Codex” is a tool name. “The place where we discussed that task yesterday” is the destination the user has in mind.

A destination can be shown in two layers. The first names recognizable work, such as “Beamhop · Keep reading.” The second names the tool and session currently receiving material, such as “Codex · Focus investigation.”

A project is not necessarily a repository. One repository can contain several goals, and one piece of work can span code, documents, and design files. Repository names, paths, and app names provide clues; none can stand in for the intent of the work on its own.

Sessions can end, change hands, or move while the work keeps its name. Updating the receiving session requires checking the new address. Similar titles are no reason to redirect material silently.

This does not require building a project management system first. A small starting point is a frequently used destination with a meaningful name, bound to a connected receiving address that can be confirmed. When someone is already working in the target session, they have a good opportunity to register it.

Connecting for the first time has a real cost; the demo must not skip that step. Only sessions and work context that the receiving tool permits should appear as candidates. Opening an app or activating a window does not mean reaching the right session.

## Material can serve several purposes; actions need a recipient

One task may take several sessions to complete. Repeatedly forking sessions or adding topics can leave the user with more work to understand and organize.

We discussed two kinds of relationships. The evidence trail concerns how material supports, limits, or revises a judgment. The work trail concerns who takes it on, what they plan to do, and how far they have got. Both can refer to the same material.

For example, a test note saying that the browser lost focus after sending and the participant forgot their reading position on return can inform a design discussion about the cause of an interruption. It can also go to an implementation session with a request to inspect what triggered window activation. The original and its source stay the same; the purpose and instructions can differ for each handoff.

Material may mix observations, opinions, speculation, and constraints. A clip is not automatically an established fact, and a single observation does not establish causation. Preserve the original, its source, and its context of use, then let the recipient assess its meaning.

Initially, Beamhop only needs to remember where a passage came from, which work received it, what instructions accompanied it, and how far receipt was confirmed. When someone looks back, those relationships can show what a judgment rests on or who has received the material. The user need not maintain a knowledge graph first.

## Let the model narrow the search and confirmation build trust

A passage about task interruption may fit both product design and an article. A model that finds both projects may be correctly judging relevance while still missing why the user selected this sentence now.

A small model or a model used for classification can help narrow candidates, add recognizable context, and explain recommendations. Model size is not the first product question here; the missing work intent is.

- When the destination is unclear, offer a few explainable candidates for the user to recognize.
- Once confirmed for this round of work, keep the destination visible so the next passage can go straight there.
- When the user explicitly defines a rule, route according to that rule and retain a record they can inspect and correct.

A change in recommendations must not silently overwrite a confirmed destination. Relevance must not automatically start a task, either. Adding background and requesting execution have different handoff meanings, and the receiving tool must support that distinction.

Automatic routing remains a direction to test. We first need to establish the scope of a rule, how a change of work is detected, and how a mistaken delivery is corrected. A high-looking confidence score cannot make those decisions on the user’s behalf.

## Keep sending in place; show the shelf when needed

This discussion explicitly recommends keeping selection followed by sending from the source app as the main interaction. The shelf is temporary help, not a required stop before every send.

That does not mean retaining every detail of the old interface. Keep the action: select, recognize the receiving work, send, continue reading. The old panel can shrink, destinations can become easier to recognize, and a confirmed destination can make the next send faster.

A clipboard is good at remembering what someone copied. Beamhop has a more worthwhile problem to solve: which ongoing work should receive this passage? If its home screen becomes an ever-growing copy history, users may find themselves collecting, organizing, and only then sending again.

Three situations call for keeping material nearby: the recipient is still unclear; several pieces need to be sent together; or another task needs attention and this batch should wait.

The interface should follow that order. By default, show the current selection and a clear receiving destination. The shelf takes a passage only after the user chooses to keep it. With no saved material, it can be absent. The first version need not record every copy action; it holds what the user deliberately leaves there.

Starting with one shelf is reasonable, but it must not mix all clips indiscriminately. The minimum recovery capability is to remember which pieces belong to the current batch, their order, the intended recipient, and any note. Those should remain when the user returns.

The first version need not introduce multiple shelves, unlimited groups, or topic trees. Test sending several selected passages together first, then observe whether real interruptions justify setting a batch aside and picking it up again. Support for the complexity of nonlinear work can appear as it is needed.

Feedback on October 20, 2026 clarified this boundary further. The second essay had expanded saved material into a work window that users had to enter and manage, still interrupting their main activity. In the revision, the article itself is the reading surface and a sending popover appears beside the selection. Saving only increases the count in the bottom-right corner; it does not expand the shelf or take input focus. The list, selection controls, and notes appear only when explicitly expanded, and remain when collapsed. The interface itself must show restraint; saying “no interruption” in the prose is not enough.

Whether the shelf should become the main form depends on actual use. If users repeatedly return to old material and get most of the value from collecting and recombining it across work sessions, the decision is worth revisiting. This discussion does not yet have that evidence. An appealing shelf demo supports adding it as an aid; it is not enough to redirect the whole product.

## Judge features through use

By “Jobs-like” judgment, we mean assessing features through specific human actions: whether people recognize them on first use, whether they feel easy to handle, and whether the product is willing to narrow its scope. This is a design requirement, not a quotation of Steve Jobs’s views.

Mac style cannot stop at red, yellow, and green window buttons. Toolbars, sidebars, selections, popovers, and small utility panels should make the hierarchy clear: the source app remains, and Beamhop appears for the handoff.

The prose explains the judgments; the interactions let readers test them. A demo should show more than the ideal outcome: first finding a destination, a session ending, failed receipt, and recovery after an interruption all matter.

Copied, filled into an input field, received by the destination, and task completed each promise different things. Status must be accurate. An attractive success animation cannot substitute for receipt confirmation.

## What to test first, and what to defer

Test three things first: remembering the current work as a reusable destination, handing over several pieces with their sources and order, and showing who has already received a piece of material.

On that basis, test pause and resume and destination recommendations. Stable session addressing, background delivery, and distinct handoff intentions all require checking support in the receiving tool. The presence of MCP alone does not establish that these capabilities exist.

Defer a general knowledge graph, full task management, automatic creation of many topics, and Beamhop’s own generative workspace. They introduce objects that need ongoing maintenance while sending from the source app still needs to prove its value.

Evaluate real actions: does a second send to the same place require less searching? Can the user continue reading? How often must destinations be corrected? Can the original order and instructions be recovered after setting material aside? Does failure preserve the material and offer a clear way to recover? A successful demo does not mean these questions have been answered through actual use.

If a new feature adds a step to something that could be sent directly, it owes the user a reason.

## What to investigate next

Continue testing actual work across multiple agents: how users recognize work, when they are willing to register a destination, when they only mean to add background, and when a batch really needs to be set aside. How much judgment the model should take on must be determined through those handoffs.

The sessions, material, model suggestions, and receipts in these essays are simulated. They explore interaction principles and do not claim shipped capabilities. The [Beamhop repository](https://github.com/willamhou/beamhop) remains the source for application code and progress; the [product positioning document](https://github.com/willamhou/beamhop/blob/main/docs/product-positioning.md) gives the background on capture in the current app and handoff to external tools.

**Send it easily when it is ready. Keep it nearby when it is not.**
