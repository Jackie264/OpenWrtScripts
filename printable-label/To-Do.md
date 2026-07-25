# To-Do

- [x] Doesn't need save/apply / save / cancel -- never defined handleSave/handleSaveApply/handleReset, so LuCI's footer never renders them
- [x] needs print button
- [x] Print displays only the table and the power-brick label (not the intro text or "why is this safe" text)
- [x] More info around the table -- power-brick label + "Why is this safe?" placeholder heading below (text TBD, you said you'd expand it)
- Table
  - [x] must be compact
  - [x] Right-justify labels
  - [x] put in its own `<div>` for printing (`.rl-print-area`, now also wraps the power-brick label since both print)
- [x] Separate power brick label from the table
- [x] Put "Login PW" as editable field on the row
- [x] Change "Connect to" to "Browse to"
- [x] Change "or" to "SSH to" (rendered as plain text, not a link, per your answer)
- [x] .lan or **.local**? -- went with .local, matching print-router-label.sh's own documented example
- [x] "Configured" or "Date configured"? -- went with "Date configured"
- [x] "LAN Address"

## Next round

- More comments on table labels/values and other fussy details (pending)
- Fill in real "Why is this safe?" text (currently a placeholder)
- Decide what the top intro text above the table should say (currently unchanged)
- Check how the Login PW `<input>` actually looks when printed (browsers print the
  current value inside the input's box -- may want a plain-text swap for print only)
