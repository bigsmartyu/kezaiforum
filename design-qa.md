# Design QA

## Comparison target

- Source style: `evidence/innox-homepage.png` at the Innoxsz official desktop viewport.
- Source assets: the user-supplied official logo crop and founder portrait.
- Implementations: `evidence/join-v1.1-desktop-final2.png`, `evidence/join-v1.1-mobile-390-final2.png`, and `evidence/avatar-preview-v1.1-final.png`.
- Combined visual evidence: `evidence/design-qa-comparison.png`.

## Findings

- No P0, P1, or P2 mismatch remains.
- Typography: the Chinese display heading is bold and compact like the official hero; supporting copy remains readable at desktop and 390 px mobile width with no orphaned final character.
- Spacing and layout: desktop uses the official dark hero / light action panel split; mobile changes to a clear vertical sequence with no text-photo collision or horizontal overflow.
- Colors: near-black, white, official royal blue, and coral-red accents match the supplied logo and official homepage direction.
- Image quality: the official logo remains sharp, the supplied founder portrait keeps its original identity and proportions, and the selected avatar is visibly previewed in a circular crop before submission.
- Copy: the page uses Innoxsz's verified themes of talent cultivation, project incubation, and entrepreneurship empowerment while clearly explaining one-time registration and remembered login.
- Interaction: name entry, image selection, live avatar preview, ordinary-member registration, member-ID display, remembered return, and administrator entry were all exercised against the deployed page.

## Accepted P3 notes

- The native file-picker button language follows the phone/browser language; this is operating-system chrome rather than page copy.
- Raw-LAN HTTP produces a browser warning about advanced cross-window isolation, but it does not affect registration, preview, login memory, forum access, or chat.

## Final result

final result: passed
