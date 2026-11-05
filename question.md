# Demo questions for the Auto Patching AI (release-note Q&A)

How the AI behaves (from its own answers):
- It answers only about the selected PostgreSQL releases (the version range shown in the tool) and how they affect this instance.
- It can check catalog facts of the instance (extensions, index types, settings, collations) against the release notes.
- It cannot read business data, credentials, hosts or connection details.

So every question is about fixes, risks or behaviour changes in the selected range, and about what that means for this instance's extensions, index types, settings and collations.

## UC01: PostgreSQL 16.2 -> 16.3

1. "What are the most important fixes and behaviour changes between 16.2 and 16.3?"

2. "Does 16.3 include a security fix that needs a manual step after the upgrade, for example running a SQL script on every database? Which behaviour changes for non-owner users?"

3. "Based on the extensions installed on this instance, which fixes or risks in 16.3 affect them? Do any of them need to be updated or reloaded after the upgrade?"

4. "Based on the index types used on this instance (B-tree, GIN, GiST, BRIN, Hash), are there any fixes in 16.3 that affect them? Do I need to reindex anything?"

5. "Based on the settings and collations of this instance, is there any risk or behaviour change in 16.3 that I should check before and after patching?"

## UC02: PostgreSQL 15.6 -> 15.16

1. "Are there any known bugs in the releases between 15.6 and 15.16? Which release should I avoid?"

2. "I heard `substring()` on TOAST-ed text with multi-byte characters can fail after a recent minor release. Which release in this range is affected, which release fixes it, and what is the CVE?"

3. "Based on the encoding and collations of this instance, am I exposed to the 15.16 multi-byte text issue? What error would I see?"

4. "Based on the extensions and index types used on this instance, which fixes in the range 15.6 to 15.16 affect me? Is there anything I need to reindex or recreate?"


## Optional follow-ups

- "Summarize the risks of every minor release in the selected range in one table."
- "Give me a pre-upgrade and post-upgrade checklist for this version range."

## Demo tips

- Ask UC01 first to show the "safe" case (a CVE fix script and a small view change), then UC02 to show the tool warning about a bad release.
- UC02 questions 2 and 3 are the highlight: the AI should point out 15.16 as the affected release and the next release (15.17) as the fix.
- Do not ask about specific tables, rows, users, hosts or passwords. The AI will refuse.
- If the AI says it only answers about the selected releases, rephrase the question around the version range shown in the tool.
- Check the real answers before the demo and drop any question where the answer is weak.
