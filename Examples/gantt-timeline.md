# Pilot timeline

```mermaid
gantt
    title md2png pilot
    dateFormat  YYYY-MM-DD
    axisFormat  %b %d
    section Product
    MVP implementation       :done,    mvp, 2026-08-10, 3d
    Brand and packaging      :done,    pkg, 2026-08-12, 2d
    Pilot feedback           :active,  pilot, 2026-08-14, 8d
    section Release
    Developer ID certificate :active,  cert, 2026-08-14, 5d
    Notarization validation  :         note, after cert, 2d
    General availability     :milestone, ga, 2026-09-04, 0d
```
