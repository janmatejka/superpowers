# Doklad — Session Intent Baton
Part of contract 3.x — evidence read on demand, never the home of a rule.

## Why the baton's format is closed

Emitting verbatim would let a body close the reader's own wrapper tag and
continue as top-level instruction text — whitelisting key names is not enough,
because a legitimate key can still carry a value that closes the wrapper early,
so the check rejects the character class rather than any one tag's spelling.
**The format category (`\p{Cf}`) is in that class for the same argument one
step further, and it is stated here because this is the class's single home:**
U+202E RIGHT-TO-LEFT OVERRIDE, U+200B and the U+2066–U+2069 isolates carry no
glyph at all, so they survive trimming and every length bound and then REORDER
what the reader emits — the Trojan-source shape, where what a model reads is
not what the bytes say. No legitimate value of a closed pointer format — a
path, a branch, a slug, a ticket key, a skill name, a state word — has any
reason to carry one. **Every reader in this layer that lifts text out of an
untrusted file rejects this same class**, not only the baton's: the `NOW`
block's values and any other excerpt of a foreign progress ledger are bound by
it by reference ("The `NOW` Block"), so a reader widening or narrowing it
alone would be the drift this single home exists to prevent.
