
### Translatable text

Use this module if the game may be played in more than one language: it is far
cheaper to start that way than to retrofit it. State the source language
(English here); translations come later.

- **Anything a player reads goes through `tr()`**: labels, buttons, hints,
  tooltips, the words for why a round ended. Write the source-language sentence
  inside the call: `button.text = tr("Ready")`.
- **Never build a sentence from pieces.** Word order differs between
  languages, so `"Waiting for " + str(n) + " players"` can't be translated.
  Translate the whole sentence with a placeholder:
  `tr("Waiting for %d more to ready up") % n`.
- **Plurals use `tr_n()`**, not an `"s" if n != 1 else ""` choice in code.
- **Names, numbers and times:** a player's name is shown as typed, whatever its
  script; don't assume a name, a number or a clock is Latin or left to right.
- **Developer-facing text is exempt:** debug overlays, tools, console `print()`
  output and logs stay in the source language and need no `tr()`.
- **Back the habit with a test.** A GUT test can count hardcoded text lines in
  the UI scripts and fail if a file exceeds a recorded baseline (a JSON file
  that may only go down; require it to match the count exactly so slack can't
  let new text in unseen). It is a line-based check and can miss things: the
  habit is the rule, the test is the backstop.
