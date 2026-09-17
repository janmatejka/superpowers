# Doklad — Link Conventions
Part of contract 3.x — evidence read on demand, never the home of a rule.

## Why no #fragment anchors

  The reason is not style: heading slugs are **renderer-specific**. Bitbucket
  Cloud, GitHub and IDE preview each derive a different slug from the same
  heading, so an anchor that resolves in one viewer silently dead-ends in the
  others, and no single spelling can be correct everywhere. A section title is
  stable across all of them, survives a renderer change, and stays meaningful in
  a plain-text read. It follows that headings must never be reworded merely to
  make a slug come out a particular way.
