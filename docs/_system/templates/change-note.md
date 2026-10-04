---
subject: {{SUBJECT}}
---

# Change note: {{TITLE}}

<!-- A change note is a lead for the documentation coordinator, not a
draft document. Record what the code cannot reveal about this change;
the code itself is read at processing time. Delete these comments as
you fill the sections; "None" is a valid entry for any of them.

subject names the feature, behaviour, or decision the change concerns,
in a few words. It is how a later change on the same subject finds this
note to revise instead of filing another, so name the subject, not the
documents it may touch.

Keep the note stating the net change until it is processed: when a
later task or change revises or reverses something recorded here,
rewrite that text rather than adding beneath it. Git keeps every
earlier version.

Record only what you verified. Quote a human or external source
verbatim, with what identifies it: its time, message id, subject, or
path. -->

## Purpose

<!-- Why the change was made, in one to three sentences. -->

## What changed

<!-- Behaviour-level summary and the main files or areas touched. Not
a diff. -->

## Documentation impact

<!-- The impact notes from each task in this change, carried here as
leads, not as text to carry forward: which documents may now be wrong,
what knowledge is new, what a future reader would need to find. When
the change implies many separate document edits, say so. -->

## Decisions and rejected alternatives

<!-- Choices made during the change that a future reader could not
recover from the code: what was chosen, what was rejected, and why. -->

## Terms

<!-- Domain terms coined, resolved, or sharpened during the change. -->

## Human-provided facts

<!-- Anything the owner stated that repository inspection cannot
establish, quoted verbatim with its source. -->
