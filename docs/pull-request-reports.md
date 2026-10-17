# Pull request reports for VI changes

GitHub cannot diff VIs, so a reviewer of this repository judges a change from
pictures of block diagrams. Every pull request that changes VIs carries two
layers of them:

| Layer | Where | Purpose | Contains |
|---|---|---|---|
| **Detailed diff report** | `report.md` on the branch `pr-assets/pr-<n>`, opened from the button in the review report comment | Complete record | Every changed spot, before and after; the whole block diagram and front panel of every changed VI; **every case frame** of added VIs and of the "after" side of modified VIs |
| **Code summary** | Section 3 of the pull request description | A quick overview a reviewer reads first | Only the pictures needed to explain the change, cropped, with numbered highlights and short text |

The review report comment (test result, one thumbnail per modified VI, the
button to the detailed report) stays compact, as described in `CLAUDE.md`.

## Detailed diff report

- Produced by `tools/ci/New-ViDiffReport.ps1` in the pull request workflow, or
  locally with the same script; see `CLAUDE.md` for the comparison LabVIEW.
- It must show every case frame. LabVIEW's comparison images show each case
  structure only on its visible frame. LabVIEW's documentation printer (Print.VI
  To HTML) writes one picture per frame (`<name>d.png`, `<name>d1.png` ...); the
  `lvai_render_diagrams` tool drives it. Until the script renders the frames
  itself, render them with that tool and publish them with the summary images
  (below) as a `frames/README.md` page with one row per frame, named by its case
  selector, and link that page from the Code summary.

## Code summary

Write it once the review report is posted, and refresh it whenever a push
changes the diagrams. The reader should get what changed and why in one
scroll, without opening the detailed report.

### Layout

1. **Intro line** (a quote block): orange numbered boxes match the numbered
   points; click a picture for full size; link to the detailed report and, if
   separate, to the frames page.
2. **Overview table**, one row per VI, in reading order (the VI that carries
   the change first, tests last):

   | VI | Status | Change in one line |
   |---|---|---|
   | [`Name.vi`](#anchor) | modified / **added** / deleted | what it does differently, in plain words |

   Test VIs that only follow the existing pattern may share one row.
3. **One section per VI**, headed `` ### `Name.vi` — modified `` (or `added`):
   - one sentence: what the VI does now, or what the change does in it;
   - one picture per spot that needs explaining, **cropped** to that spot with
     enough context to recognise where it is, and **highlighted** with numbered
     orange boxes;
   - a numbered list under each picture, one point per box, in box order, one
     or two sentences each: what happens there and why. Start a point with a
     bold tag when it helps (**New:**, **Removed:**, **Work list:**);
   - for a modified spot where the old version matters, a Before | After table
     with both pictures;
   - for an added VI with case structures: the overview picture with its
     visible frames, then a `####` sub-section per frame that is needed to
     understand it. Frames that only pass data through (error case, empty
     default) are named in one sentence and left to the detailed report.
4. **Test VIs** in a short bullet list without pictures, unless their diagram
   is the point of the change.

### Pictures

- Make them with `tools/ci/New-SummaryImage.ps1`: it crops a source picture,
  draws numbered orange boxes around the given spots and scales it to at most
  1600 px wide. Coordinates are pixels of the source picture; open the source
  image to find them, then open the result to check that every box sits on the
  node it names.
- Sources: the "after" images and whole diagrams of the detailed report
  (`images/...` on `pr-assets/pr-<n>`, usable by URL), or frames rendered with
  `lvai_render_diagrams`.
- Show the picture large: `width="880"` for whole diagrams and frames (the
  width of the description column), smaller only for small spots. Wrap each
  picture in a link to its full-size file. Do not put two large diagrams side by
  side; they become unreadable. Small spots may share a table row.
- Never show more frames than the text explains. A highlight without a numbered
  point, or a point without a highlight, is a mistake.

### Where the pictures live

The workflow replaces `pr-assets/pr-<n>` with a single new commit on every
run, so anything added there by hand disappears at the next push. Put summary
pictures (and the frames page, while the script does not render frames) on
their own branch, `pr-assets/pr-<n>-summary`, with ordinary commits:

```
summary/<vi>_<spot>.png      cropped and highlighted pictures
frames/<VI-Name>/<n>-<case>-<selector>.png
frames/README.md             one row per frame
```

Link them by commit (`https://raw.githubusercontent.com/<repo>/<commit>/...`),
not by branch name, so the description keeps showing the pictures it was
written for. When later pushes change the diagrams, add a new commit with new
pictures and update the links. Delete both `pr-assets` branches once the pull
request is closed.

### Checklist before asking for review

- [ ] Every modified and added VI has a row and a section.
- [ ] Every picture is cropped to the spot, highlighted, and readable at the
      width shown (check the rendered pull request page, not only the file).
- [ ] Box numbers and list numbers match, in the same order.
- [ ] Every frame the text relies on is shown; every frame of the VI is in the
      detailed report or on the frames page.
- [ ] Links point to commits, and every picture loads.
