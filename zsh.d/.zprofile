brewpath="/opt/homebrew/bin/brew"
if [[ -f "$brewpath" ]]; then
  eval $(/opt/homebrew/bin/brew shellenv)
fi

