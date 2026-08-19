#!/usr/bin/env bash
# tests/fm-composer-lib.test.sh - the shared composer-content classifier
# (bin/fm-composer-lib.sh), the ONE fleet-wide owner every backend adapter
# delegates its empty|pending|unknown verdict to.
#
# The load-bearing contract, task fm-composer-shellglyph-safety:
#   1. A BARE shell prompt glyph (`>`/`$`/`%`/`#`) on an unstructured row is a
#      dead shell, NOT an empty agent composer - it must read `unknown`
#      (unsafe-for-injection), never `empty`. This is the safety fix.
#   2. The SAME shell glyph INSIDE a bordered composer box is the harness's own
#      prompt and still reads `empty` (existing behavior preserved).
#   3. The AGENT prompt glyphs `❯` (claude) and `›` (codex) are a genuine empty
#      agent composer either way, bordered or bare.
#   4. Real unsubmitted text reads `pending`; a known idle placeholder reads
#      `empty`.
#
# Task away-mode-composer-guard-blind-aw3 adds one more, without touching those:
#   5. A composer holding only INVISIBLE blanks is visually empty and reads
#      `empty`. Claude Code 2.x pads its bare `❯` with U+00A0, which POSIX
#      [[:space:]] never matches, so every trim walked past it and an idle
#      composer read `pending` on every backend - the away-mode injection wedge.
#      The normalization decides nothing on its own; it only lets rules 1-4 see
#      the row the way a human sees it.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck source=/dev/null
. "$ROOT/bin/fm-composer-lib.sh"

# classify <bordered> <content> [idle_re] -> echoes the verdict.
classify() { fm_composer_classify_content "$@"; }

# --- Safety fix: bare shell prompt is NOT an empty agent composer -----------

test_bare_shell_glyphs_are_unknown() {
  local g out
  for g in '>' '$' '%' '#'; do
    out=$(classify 0 "$g")
    [ "$out" = unknown ] \
      || fail "bare shell glyph '$g' must read unknown (dead shell, unsafe), got '$out'"
  done
  pass "fm_composer_classify_content: a bare shell prompt glyph (>/\$/%/#) reads unknown, never empty"
}

test_stripped_unbordered_content_uses_plain_content() {
  local plain out
  for plain in '$' 'user@host $'; do
    out=$(classify 0 '' '' sensitive "$plain")
    [ "$out" = unknown ] \
      || fail "stripped unbordered content '$plain' must retain its unknown safety verdict, got '$out'"
  done
  for plain in '❯' '›'; do
    out=$(classify 0 '' '' sensitive "$plain")
    [ "$out" = empty ] \
      || fail "a stripped agent glyph '$plain' must remain empty, got '$out'"
  done
  pass "fm_composer_classify_content: stripped unbordered content is unknown except verified agent glyphs"
}

test_bare_shell_prompt_with_command_is_not_empty() {
  local out
  # A dead shell showing a typed command must not read empty either.
  out=$(classify 0 '$ ls -la')
  [ "$out" != empty ] || fail "a bare shell prompt with a command must not read empty, got '$out'"
  pass "fm_composer_classify_content: a bare shell prompt carrying a command is not empty"
}

# --- Preserved: shell glyph inside a composer box is the harness prompt ------

test_bordered_shell_glyph_is_empty() {
  local g out
  for g in '>' '$' '%' '#'; do
    out=$(classify 1 "$g")
    [ "$out" = empty ] \
      || fail "a shell glyph '$g' inside a bordered composer box must read empty, got '$out'"
  done
  pass "fm_composer_classify_content: a bare prompt glyph inside a bordered composer box reads empty (claude's own idle composer)"
}

# --- Agent glyphs are empty either way --------------------------------------

test_agent_glyphs_are_empty_bordered_and_bare() {
  local out
  out=$(classify 0 '❯'); [ "$out" = empty ] || fail "bare claude '❯' should read empty, got '$out'"
  out=$(classify 0 '›'); [ "$out" = empty ] || fail "bare codex '›' should read empty, got '$out'"
  out=$(classify 1 '❯'); [ "$out" = empty ] || fail "bordered claude '❯' should read empty, got '$out'"
  out=$(classify 1 '›'); [ "$out" = empty ] || fail "bordered codex '›' should read empty, got '$out'"
  pass "fm_composer_classify_content: agent prompt glyphs (❯ claude, › codex) read empty bordered or bare"
}

# --- Empty content and idle placeholder -------------------------------------

test_empty_content_is_empty() {
  local out
  out=$(classify 0 ''); [ "$out" = empty ] || fail "empty bare content should read empty, got '$out'"
  out=$(classify 1 ''); [ "$out" = empty ] || fail "empty bordered content should read empty, got '$out'"
  pass "fm_composer_classify_content: an empty composer reads empty"
}

test_idle_placeholder_is_empty() {
  local idle='^Type a message\.\.\.$' out
  # Placeholder with no prompt glyph (grok's bordered empty composer).
  out=$(classify 1 'Type a message...' "$idle")
  [ "$out" = empty ] || fail "the grok idle placeholder should read empty, got '$out'"
  # Placeholder after an agent glyph (post-strip match).
  out=$(classify 0 '❯ Type a message...' "$idle")
  [ "$out" = empty ] || fail "the idle placeholder after a glyph should read empty, got '$out'"
  # Without the idle regex it is just text -> pending.
  out=$(classify 1 'Type a message...')
  [ "$out" = pending ] || fail "without an idle regex the placeholder text is pending, got '$out'"
  pass "fm_composer_classify_content: a known idle placeholder reads empty, before and after glyph stripping"
}

test_idle_placeholder_case_mode_is_explicit() {
  local idle='^Type a message\.\.\.$' out
  out=$(classify 1 'type a message...' "$idle")
  [ "$out" = pending ] || fail "a case-variant idle placeholder should remain pending by default, got '$out'"
  out=$(classify 1 'type a message...' "$idle" insensitive)
  [ "$out" = empty ] || fail "an explicitly insensitive idle placeholder should read empty, got '$out'"
  pass "fm_composer_classify_content: idle matching preserves the caller's case mode"
}

# --- Rule 5: invisible composer padding -------------------------------------

test_nbsp_padded_agent_glyph_is_empty() {
  local out blank glyph hex
  glyph=$(printf '\xe2\x9d\xaf')
  # U+00A0 first: the exact byte pair captured live from the wedged pane.
  out=$(classify 0 "${glyph}$(printf '\xc2\xa0')")
  [ "$out" = empty ] \
    || fail "the live claude composer '❯'+U+00A0 must read empty, got '$out'"
  # Then every blank this owner declares, so the set cannot grow untested.
  for blank in "${FM_COMPOSER_BLANK_CHARS[@]}"; do
    hex=$(printf '%s' "$blank" | od -An -tx1 | tr -d ' \n')
    out=$(classify 0 "${glyph}${blank}")
    [ "$out" = empty ] \
      || fail "an agent glyph padded with blank 0x$hex must read empty, got '$out'"
    out=$(classify 1 "$blank")
    [ "$out" = empty ] \
      || fail "a bordered composer holding only blank 0x$hex must read empty, got '$out'"
  done
  pass "fm_composer_classify_content: a composer padded with invisible blanks reads empty"
}

test_nbsp_padded_shell_glyph_keeps_its_safety_verdict() {
  local out g
  # The dead-shell rule is untouched: normalizing blanks must not turn a bare
  # shell prompt into an injection target.
  for g in '>' '$' '%' '#'; do
    out=$(classify 0 "$(printf "%s\xc2\xa0" "$g")")
    [ "$out" = unknown ] \
      || fail "a U+00A0-padded bare shell glyph '$g' must stay unknown, got '$out'"
    out=$(classify 0 '' '' sensitive "$(printf "%s\xc2\xa0" "$g")")
    [ "$out" = unknown ] \
      || fail "a U+00A0-padded stripped shell glyph '$g' must stay unknown, got '$out'"
  done
  pass "fm_composer_classify_content: blank normalization leaves the dead-shell rule intact"
}

test_blank_padded_real_text_is_still_pending() {
  local out
  # The guard's whole purpose - never merge a digest into half-typed input -
  # must survive whatever padding surrounds the text.
  out=$(classify 0 "$(printf '\xe2\x9d\xaf\xc2\xa0fix findings 1 and 3')")
  [ "$out" = pending ] || fail "U+00A0-padded typed text must stay pending, got '$out'"
  out=$(classify 1 "$(printf '\xe3\x80\x80deploy staging\xc2\xa0')")
  [ "$out" = pending ] || fail "blank-padded bordered text must stay pending, got '$out'"
  out=$(classify 0 "$(printf '\xc2\xa0\xc2\xa0')" '' sensitive "$(printf '\xc2\xa0\xc2\xa0')")
  [ "$out" = empty ] || fail "a row of nothing but blanks must read empty, got '$out'"
  pass "fm_composer_classify_content: blank-padded real text is still pending"
}

test_normalize_blanks_leaves_visible_text_alone() {
  local out
  out='plain ascii text'
  fm_composer_normalize_blanks out
  [ "$out" = 'plain ascii text' ] || fail "normalization altered plain ASCII: '$out'"
  # A multibyte glyph that is NOT a blank must survive byte-for-byte.
  out=$(printf '\xe2\x9d\xaf')
  fm_composer_normalize_blanks out
  [ "$out" = "$(printf '\xe2\x9d\xaf')" ] || fail "normalization damaged the '❯' glyph"
  out=$(printf 'caf\xc3\xa9 \xe6\x97\xa5\xe6\x9c\xac')
  fm_composer_normalize_blanks out
  [ "$out" = "$(printf 'caf\xc3\xa9 \xe6\x97\xa5\xe6\x9c\xac')" ] \
    || fail "normalization damaged accented or CJK text: '$out'"
  # Interior blanks are normalized without collapsing the text around them.
  out=$(printf 'ship\xc2\xa0it')
  fm_composer_normalize_blanks out
  [ "$out" = 'ship it' ] || fail "an interior blank was not normalized to a space: '$out'"
  pass "fm_composer_normalize_blanks: visible text, including multibyte, is untouched"
}

# --- Real text is pending ---------------------------------------------------

test_real_text_is_pending() {
  local out
  out=$(classify 0 '❯ fix findings 1 and 3'); [ "$out" = pending ] || fail "bare '❯ <text>' should be pending, got '$out'"
  out=$(classify 1 '> deploy staging now'); [ "$out" = pending ] || fail "bordered '> <text>' should be pending, got '$out'"
  # A slash-command popup argument-hint placeholder is still unsubmitted text.
  out=$(classify 1 '/compact compaction instructions'); [ "$out" = pending ] || fail "a popup placeholder fill should be pending, got '$out'"
  pass "fm_composer_classify_content: real unsubmitted text reads pending (including a popup argument-hint fill)"
}

test_bare_shell_glyphs_are_unknown
test_stripped_unbordered_content_uses_plain_content
test_bare_shell_prompt_with_command_is_not_empty
test_bordered_shell_glyph_is_empty
test_agent_glyphs_are_empty_bordered_and_bare
test_empty_content_is_empty
test_idle_placeholder_is_empty
test_idle_placeholder_case_mode_is_explicit
test_real_text_is_pending
test_nbsp_padded_agent_glyph_is_empty
test_nbsp_padded_shell_glyph_keeps_its_safety_verdict
test_blank_padded_real_text_is_still_pending
test_normalize_blanks_leaves_visible_text_alone
