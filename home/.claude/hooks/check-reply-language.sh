#!/usr/bin/env bash
# Stop hook (checker): when the user's last message is in Japanese and the reply
# that just ended is not, send Claude back to rewrite it. Fails open.
set -euo pipefail

input=$(cat)
transcript=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null) || exit 0
[[ -r $transcript ]] || exit 0
[[ $(jq -r '.stop_hook_active // false' <<<"$input") == true ]] && exit 0

# Only the tail is read: a long session's transcript runs to tens of megabytes.
tail -n 400 "$transcript" | jq -rs '
  def text_of: if type == "string" then . else [.[]? | select(.type == "text") | .text] | join("\n") end;
  def jp: [scan("[\\p{Hiragana}\\p{Katakana}\\p{Han}]")] | length;
  def latin: [scan("[A-Za-z]+")] | length;
  # Drop code, inline code, and URLs: they are English in any reply.
  def prose: gsub("(?s)```.*?```"; "") | gsub("`[^`]*`"; "") | gsub("https?://\\S+"; "");
  [.[] | select(.type == "user" or .type == "assistant")] as $entries
  | ([$entries | to_entries[]
      | select(.value.type == "user")
      | select((.value.message.content | text_of | prose | jp) >= 5)
      | .key] | last) as $u
  | if $u == null then empty else
      ([$entries[$u + 1:][] | select(.type == "assistant") | .message.content | text_of] | join("\n") | prose) as $reply
      | ($reply | jp) as $j | ($reply | latin) as $l
      | if ($j + $l) >= 20 and ($j * 3) < $l then
          {decision: "block",
           reason: "The user wrote in Japanese, but this reply is in English. Rewrite the whole reply in Japanese (code, identifiers, commands, and quoted text stay as they are), then finish."}
        else empty end
    end
' 2>/dev/null || exit 0
