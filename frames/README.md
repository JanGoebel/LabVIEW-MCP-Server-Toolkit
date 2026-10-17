# Every case frame of the VIs changed in pull request 27

Rendered with LabVIEW's documentation printer (Print.VI To HTML), one picture per frame. The CI diff report shows each case structure only on its visible frame.

## `Add Control Details To Schema.vi` (added)

| Frame | Picture |
|---|---|
| Whole diagram (outer case: False; element case: "Array"; bounds case: "number") | ![](Add-Control-Details-To-Schema/0-overview.png) |
| Outer case: True (error in, or invalid control reference), passes the schema through | ![](Add-Control-Details-To-Schema/1-outer-case-True.png) |
| Bounds case: Default (no numeric schema type), no bound, no unit | ![](Add-Control-Details-To-Schema/2-bounds-case-Default.png) |
| Bounds case: "integer" | ![](Add-Control-Details-To-Schema/3-bounds-case-integer.png) |
| Element case: Default, no child controls | ![](Add-Control-Details-To-Schema/4-element-case-Default.png) |
| Element case: "Cluster" | ![](Add-Control-Details-To-Schema/5-element-case-Cluster.png) |

`Get Connector Pane Info.vi` and `Test_MCP_Server.vi` changed only on their visible frames; the test VIs have no case structures.
