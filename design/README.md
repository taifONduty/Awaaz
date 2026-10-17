# Awaaz design source

[Figma design and linked prototype](https://www.figma.com/design/8C7LHBjpEzvRXol0XuPd1R?node-id=9-119). The user selected the currently connected primary Figma account after discussing Turjo's account.

Eight 390 × 844 phone views cover Explore, route comparison, active journey, deviation check-in, Community, report composer, Circle and SOS preview. The controls reuse Material 3 button/navigation instances. Local cards expose text properties. Aliased colour/spacing variables and Manrope/Noto Sans Bengali text styles are shared. All UI content is editable; maps are schematic vector illustrations, not a rasterized screen or actual Dhaka map.

`figma-state.json` is the resumable ID ledger. The result JSON files retain all created/mutated IDs. `figma-review.png` is the reviewed composition after correcting library colours and button widths. No report or route is real.

The primary account's Starter-plan MCP limit was reached after the screen and visual-review work. The empty construction wrapper `5:51` could not be removed. It contains no visible UI. Further design refinements need renewed connector quota; the existing file remains accessible.

Browser QA improved the Flutter version with fixed journey actions above navigation and SOS in the journey header. These are recorded implementation adjustments and are not yet synchronized to Figma because of that quota.

Material Symbols SVGs in `icons/` come from [google/material-design-icons](https://github.com/google/material-design-icons), Apache 2.0. Manrope and Noto Sans Bengali come from [Google Fonts](https://github.com/google/fonts); their SIL Open Font licenses are bundled with the mobile assets. Taste skill informed restraint, typography and trust-first styling; Android interaction patterns use Material 3 and the official Flutter/Figma skills.
