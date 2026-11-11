# Quote Fuse frontend design contract — Stage 4B

## Intent

Make the version gate legible in one glance. The circuit is the product metaphor: an authenticated blue callback travels across the three networks and opens the protected quote's switch while the control path stays continuous. The landing page is deliberately only navigation, a split hero, two matched slips, and one quiet proof link. Replay carries the details.

The visual structure draws on the [fintech landing page reference](https://dribbble.com/shots/26865836-Fintech-Landing-Page-Design) for generous headline/action hierarchy, [Harry Beck's Tube map](https://www.londonmuseum.org.uk/collections/london-stories/harry-beck-revolutionised-tube-map/) for simple routed junctions, and the [single leading marker interaction](https://60fps.design/shots/runmo-lab-pulse-heart-ecg-interaction) for one short signal animation. No asset or layout is copied from those references.

## Tokens and typography

| Role | Value | Use |
| --- | --- | --- |
| Canvas | `#F8F7F2` | Warm ivory page background |
| Surface | `#FFFFFF` | Nav, slips, evidence panels |
| Ink | `#19232D` | Primary copy and action |
| Callback | `#E8F0FC` with `#245398` text | Active navigation, replay state, circuit signal |
| Stale | `#FFF0D7` with `#86551A` text | Open protected path and stale error |
| Confirmed | `#E5F2E9` with `#275E42` text | Successful fills |

Instrument Sans carries headings, navigation, and prose. IBM Plex Mono carries chain IDs, versions, amounts, basis points, receipts, and compact diagram labels. Color never bears outcome alone: each state has a word (`Fillable`, `Stale`, `Filled`) and a structural change in the switch.

## Composition

- **Navigation:** one centered white pill with the wordmark, Overview, Replay, and GitHub. The active link receives a powder-blue inset pill. Semantic links keep keyboard navigation simple.
- **Overview:** at desktop widths, a 44/56 split gives the exact headline, one-sentence explanation, and replay CTA a quiet left column. A right-side white circuit board contains three network nodes, a version readout, and two aligned quote slips with identical initial terms. It fits inside a 1440 × 900 viewport, including both outcomes.
- **Replay:** a separate hash-routed view has transport controls, six discrete steps, a threshold meter with the 300 bps boundary, the version switch, three chain evidence nodes, and control/stale/fresh outcome cards. The observed `10.43 s` timing badge stays visible and does not follow playback speed.
- **Responsive:** the hero stacks below 760 px, retaining the two slips close together. On narrow phones, the chain evidence route becomes a readable vertical sequence. The pill nav retains all four destinations without horizontal scrolling.

## Interaction and data rules

- Overview runs one signal pass and holds the final state: control `Fillable`, protected `Stale`, and protected settlement `v1`. With reduced motion, it renders that final comparison immediately.
- Replay starts at step 0 and offers Play, Pause, Step, Reset, and direct step buttons. Reset restores the initial fixture state and selected evidence. Reduced-motion Play jumps to the recorded final state; manual Step remains available.
- Each chain node is keyboard-activatable. Its evidence appears once the replay reaches that chain and includes the fixture's receipt hash, block, gas, decoded event, and explorer link.
- The stale quote is always labeled **“Simulated against the live contract.”** Its proof is a historical `eth_call` revert, not a broadcasted failed transaction.
- All displayed quantities, receipt links, versions, and timing are imported from `deployments/stage-3-replay.json` at build time. That fixture and `docs/frontend-handoff.md` were present in the committed Stage 4A backend; no required field was missing for Overview or Replay. The five exported ABIs are present in `abi/` and reserved for the later Live State view.
- The site has no wallet connection and makes no live RPC calls in this pass. Its replay remains a historical record after the original quote expiry.

## Sloppi rendered review

The interface was reviewed at desktop 1440 × 900, tablet 834 × 1112, and mobile 390 × 844. The first desktop render showed the headline, CTA, and both quote slips within the viewport. No viewport had horizontal overflow or a JavaScript page error. The review caught a hidden GitHub word label and cramped three-column chain nodes on mobile; both were revised. The content has one product-specific circuit and one real threshold meter, with no generic card grid on the landing page, fabricated metric, ambient gradient, or looping animation. The circuit still communicates the two outcomes without motion.

## Scope boundary

Stage 4B contains Overview and Replay only. Live state reads, wallet actions, and repeated latency measurements are outside this pass.
