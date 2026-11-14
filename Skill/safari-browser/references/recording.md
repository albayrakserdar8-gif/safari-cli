# Recording what the user does (`record`)

When the user would rather show you a task than describe it:

```bash
safari t5 record          # start; ask the user to do the task in that tab
safari t5 record --stop   # prints the commands
```

Output:

```
# replay: export SAFARI_TAB=<tab>; run each line
safari go 'https://shop.example/login'
safari fill --sel 'input[name="email"]' 'ada@example.com'
safari fill --sel 'input[name="password"]' "$PASSWORD"
safari key Enter --sel 'input[name="password"]'
# → https://shop.example/account
safari click --sel 'a[href="/orders"]'
```

- Recorded: clicks (`click`, `dblclick`), typed field values (one `fill` per field, the last value), `<select>` choices, Enter in a field, Escape, and addresses the user typed (`go`). `# →` lines note pages a click or key loaded; they need no command.
- Password values are never recorded: the line says `"$PASSWORD"`. Ask the user how to supply it, or let them type it.
- Targets are stable selectors (see `selectors.md`), so the commands work on a fresh load. Check positional ones (`nth-of-type`) and read the list before replaying it.
- `<select>` choices are recorded from the change, however the user made it (`select` itself has no `--os` mode).
- Only the user's own actions count; safari's commands are not recorded. Text typed into rich editors (contenteditable) is not recorded.
- Recording covers one site in one tab: moving to another site ends it, and `--stop` then says it is not recording.
- Replay with the tab id after `safari` on each line (`safari t9 go …`); the header's `export SAFARI_TAB` works only where the shell lasts between commands. Read the result after each step that matters, and ask before replaying anything that submits, buys or deletes.
