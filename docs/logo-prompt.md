# Logo prompt — for Gemini

Paste the block in section 2. Sections 1 and 3 are context for you, so you can steer the
follow-ups without drifting off the identity.

---

## 1. What the mark has to carry

ProveOut is a cross-chain job escrow where money moves only against cryptographic proof, and
where **anyone can prove a job failed** and is paid for doing it. The whole product is about
evidence: a receipt, a status bit, a thing that either checks out or does not.

So the mark should feel like a **verification stamp on a record**, not like a blockchain
startup. The two states, proved and refused, are the same mechanism pointed in opposite
directions, and a mark that carries that duality is more ownable than one that just says
"secure" or "connected".

The interface it sits in is deliberately plain: neutral greyscale, Geist and Geist Mono, one
accent, green and red used only where they mean settled and refused. The logo must not fight
that.

## 2. The prompt — paste this into Gemini

> Design a logo for **ProveOut**, a cross-chain escrow protocol where payment is released only
> against cryptographic proof that work was completed, and where any stranger can prove that
> work failed and collect a bounty for it.
>
> **The idea to express:** verification that cuts both ways. A single mechanism that either
> confirms or refuses. Think of a verification stamp pressed onto a record, a receipt status
> bit, or a proof path that converges to a single point of decision.
>
> **Constraints, all of them firm:**
> - Geometric, flat, monoline. No gradients, no 3D, no bevels, no glow, no drop shadows.
> - Must survive at 16×16 pixels as a favicon and still read at 512×512.
> - Must work in one flat colour on both a near-white and a near-black ground, and must not
>   rely on colour to be legible.
> - Square or near-square lockup, plus a horizontal lockup with the wordmark "ProveOut" set in
>   a clean geometric grotesque with tight letterspacing.
> - The wordmark is one word, capital P and capital O, no space: ProveOut.
>
> **Palette:** near-black `#252525` on near-white `#ffffff` as the primary. Two accents used
> sparingly and only where they carry meaning: `#138546` for proved, `#d31130` for refused.
> Do not introduce a third colour.
>
> **Avoid, hard:** chain links, cubes, blocks stacked in isometric view, hexagons, shields,
> padlocks, globes, circuitry, network-node constellations, glowing edges, purple-to-blue
> gradients, anything that could sit on any other crypto project.
>
> **Give me three distinct directions, not three variations of one:**
> 1. **The stamp.** A mark that reads as an impression pressed into a document. The negative
>    space carries a checkmark one way and a strike the other, so the same form says proved or
>    refused depending on orientation or fill.
> 2. **The converging path.** A small set of straight segments joining from many to one, the
>    shape of a Merkle path collapsing to a root. Abstract enough to read as a mark, not a
>    diagram.
> 3. **The receipt bit.** A minimal glyph built from the letterforms P and O, where the O is a
>    status indicator that can be shown filled for settled and hollow for refused.
>
> For each direction give me: the mark alone on white, the mark alone on near-black, the
> horizontal lockup with the wordmark, and a 16-pixel favicon crop. Vector-style flat artwork,
> clean edges, no mockups, no photographic scenes, no text other than the wordmark.

## 3. Steering the follow-ups

- If a direction comes back busy, ask for it again with **one fewer element**. Every good
  version of this mark is simpler than the first attempt.
- If Gemini adds a tagline, drop it. The tagline lives on the page, not in the mark.
- Ask for the strongest direction as **flat SVG-style artwork with no anti-aliased gradients**,
  then have it traced or rebuilt as a real SVG. A PNG logo will look soft against Geist.
- Check it at favicon size before choosing. A mark that needs 64 pixels to read is the wrong
  mark for a product whose surface is mostly a browser tab and a slide corner.
- Once chosen, it replaces the emoji-free tab in `web/app/` and goes top-left on slide 1 of
  `deck/slides.html`, small. It does not go on every slide.
