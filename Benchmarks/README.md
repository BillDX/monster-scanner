# Benchmarks

M2 model benchmark results. Synthetic test results (no real people) are committed here as CSV; results for real people stay in `private/`, which git ignores.

## Running the accuracy benchmark

1. Put up to 10 photos of willing friends in `Benchmarks/photos/` (JPEG, PNG or HEIC). The folder is git-ignored: the photos are of real people and must never be committed.
2. Fill in `Benchmarks/photos/labels.csv`, one row per photo:

   ```
   file,hair_color,eye_color,shirt_color,age_band,expression,accessories
   alex.jpg,brown,blue,navy blue,30s,smiling,glasses
   sam.heic,hidden,brown,red plaid,20s,serious,hat;earrings
   ```

   | Column | Allowed values |
   |---|---|
   | hair_color | black, brown, blonde, red, gray, white, dyed-other, hidden, unknown |
   | eye_color | brown, blue, green, hazel, gray, unknown |
   | shirt_color | any short colour name (scored by colour family, so "navy" = "blue") |
   | age_band | child, teen, 20s, 30s, 40s, 50s, 60+, unknown |
   | expression | smiling, serious, surprised, sleepy, silly-face, unknown |
   | accessories | up to 3 of glasses, sunglasses, hat, hood, headphones, earrings, necklace, scarf, mask, separated by `;`, or `none` |

3. With the iPhone plugged in and unlocked, and a Debug build installed, run `scripts/run-benchmark.sh`.

Accuracy = share of the 6 labelled attributes (hair, eyes, shirt colour family, age band, expression, accessories as an exact set) that match. Classic Mode is scored on the same photos.
