# frozen_string_literal: true

begin
  IRB.conf[:AUTO_INDENT]  = true  # automatically indents blocks when input spans lines
  IRB.conf[:VERBOSE]      = true  # adds some amount of detail to certain output
  IRB.conf[:SAVE_HISTORY] = 10_000 # lines of history to save
ensure
  puts 'customized irbrc is loaded'
end
