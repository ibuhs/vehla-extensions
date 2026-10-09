# Math 108X equation guide

Reviewed the 12-lesson [Math for the Real World textbook](https://books.byui.edu/math_for_the_real_world/) and its [299-page PDF](https://books.byui.edu/pdf/694). QuickNote's numeric helpers cover the equation-based work below. All examples are available through **More → Math 108X Examples**, which creates an editable note using the normal note lifecycle and persistence. No existing notes are rewritten.

**More → Math Reference…** opens a searchable native utility window with every supported built-in function, syntax, examples, units and limits. It remains open while typing or moving between notes, until its close button or Done is used. Opening it does not change notes; select example text to copy it. Unloading the extension closes the window.

Start a note or section with `math`, put one expression on each line, and end queries in `=`. Assignment lines use `name = expression`. Function definitions use `f(x) = 5x - 2`; calls show the substituted rule and result, such as `f(4) =` → `5(4) - 2 = 18`. Highlight the read-only inline answer and press ⌘C to copy it without changing the note. Hover an answer for its complete text. **More → Math Result Color** saves an appearance choice (Automatic, Match Note Text, White, Black, Yellow, Orange, Green, Cyan or Pink) for both the widget and pop-out editors. Repeating calls produces input/output rows. Multi-parameter functions, nested functions, redefinitions and cross-section variables work. A definition's parameters stay local; other variables use values in effect at the calling line.

## Course coverage

| Lessons | Equation support |
| --- | --- |
| 1–3: prerequisites, reasoning, budgets | Fractions as division, parentheses, powers, percentages, sum/mean, GCD/LCM, rates and compatible unit conversions; named formulas for budget models |
| 4: logic | Numeric comparisons and truth functions with 1=true, 0=false |
| 5–6: summaries and visualization | Center/spread/percentiles; numeric values and input/output lists for charts |
| 7: Excel functions | Function notation, sample statistics, PMT/FV, cash-flow conventions |
| 8–9: function families and change | Linear/quadratic/exponential expressions, slope, vertices, real roots, growth, periodic compound interest, PV/NPER |
| 10: prediction | Linear, quadratic and exponential least-squares coefficients; correlation and linear R² |
| 11: systems | Unique solutions of two linear equations; real quadratic roots also help solve line/parabola intersections after forming their difference |
| 12: probability and intervals | Frequency probability, the textbook's approximate margin/interval/sample-size formulas |

Charts, arbitrary symbolic rearrangement, proofs, general nonlinear equation solving, and Excel cell/range syntax are not supplied. Graphing/data-presentation assignments still use the class's spreadsheet/graphing tools. These helpers evaluate numbers and named rules, not screenshots, prose, or LaTeX. Use `^2` for a square. Implicit multiplication (`5x`, `2sin(x)`, `3(x+1)`) has the same left-to-right precedence as `*` and `/`; parenthesize denominators explicitly.

## Helpers and argument order

All names are case-insensitive for built-ins. Commas separate arguments. Use ungrouped numbers inside parentheses. `...` below means additional comma-separated values, not literal syntax. Rates/probabilities are decimal fractions (`5%` or `0.05`). Results display at most six decimal places; calculations retain Double precision.

| Syntax | Result/convention |
| --- | --- |
| `sum(values...)`, `mean(values...)`, `average(values...)` | Total or arithmetic mean; at least one value |
| `median(values...)` | Sorted middle value, or average of middle pair |
| `mode(values...)` | Most frequent value; smallest tied mode; error if none repeats |
| `stdev(values...)`, `variance(values...)` | Sample standard deviation/variance, divisor n−1; at least two values |
| `stdevp(values...)`, `variancep(values...)` | Population versions, divisor n |
| `percentile(k, values...)` | Inclusive interpolation at rank k(n−1), 0≤k≤1; k comes FIRST, unlike Excel range syntax |
| `percentrank(value, data...)` | Fraction of data values ≤ value; empirical rank, not Excel's interpolated PERCENTRANK |
| `gcd(a,b)`, `lcm(a,b)` | Nonnegative common divisor/multiple; integer inputs with magnitude ≤10¹² |
| `percentchange(old,new)` | (new−old)/old; old must be nonzero |
| `slope(x1,y1,x2,y2)` | (y2−y1)/(x2−x1); rejects vertical lines |
| `vertexx(a,b)`, `vertexy(a,b,c)` | Vertex of ax²+bx+c, x=−b/(2a), y evaluated there; a≠0 |
| `discriminant(a,b,c)` | b²−4ac |
| `quadraticroot(a,b,c,which)` | Smaller real root for which=−1, larger for which=1; rejects a=0 or negative discriminant; stable formula avoids cancellation |
| `systemx(a,b,c,d,e,f)`, `systemy(a,b,c,d,e,f)` | x/y for ax+by=c and dx+ey=f; rejects parallel/coincident or numerically degenerate systems |
| `growth(initial,rate,periods)` | initial·(1+rate)^periods; rate>−1 |
| `compound(principal,annualRate,years[,frequency])` | principal·(1+annualRate/frequency)^(frequency·years); default frequency=12; integer frequency>0 |
| `regslope(x1,y1,x2,y2,...)`, `regintercept(...)` | Linear least-squares y=mx+b; at least two points with distinct x |
| `correlation(pairs...)`, `rsquared(pairs...)` | Pearson r and r² for linear regression; reject constant x or y |
| `expfit_a(pairs...)`, `expfit_b(pairs...)` | Fit y=a·b^x via linear least squares on ln(y); every y>0 |
| `quadfit_a(pairs...)`, `quadfit_b(pairs...)`, `quadfit_c(pairs...)` | Least-squares y=ax²+bx+c; at least three distinct x; centered/scaled system with pivoting; reject degenerate data |
| `probability(successes,total)` | successes/total, integer counts, 0≤successes≤total, total>0 |
| `margin(n)` | Textbook approximation 1/√n, positive integer n |
| `cilower(successes,n)`, `ciupper(successes,n)` | successes/n ∓ 1/√n; unrounded, not clipped to [0,1] |
| `cisample(margin)` | ceil(1/margin²), 0<margin≤1; sample size for that course approximation |
| `eq(a,b)`, `lt(a,b)`, `le(a,b)`, `gt(a,b)`, `ge(a,b)` | Equal / less / less-or-equal / greater / greater-or-equal; 1 or 0 |
| `and(values...)`, `or(values...)`, `not(value)` | Boolean numeric inputs must be 0 or 1; all inputs are evaluated, no short circuit |

### Finance helpers

`pmt(rate,periods,pv[,fv[,type]])`, `fv(rate,periods,pmt[,pv[,type]])`, `pv(rate,periods,pmt[,fv[,type]])`, `nper(rate,pmt,pv[,fv[,type]])` follow Excel's cash-flow signs. Optional balances default to zero; type defaults to 0 (end-of-period), with 1 meaning beginning-of-period. Include a zero argument when skipping a balance. The interest rate is PER PERIOD: monthly payments use `annualRate/12` and `years*12`. Cash paid out is negative; cash received is positive. PMT requires positive periods; FV/PV allow zero periods; rates must exceed −1. Zero interest is handled without division by zero. NPER rejects unattainable or negative-duration results. All assume constant rate and payment amounts.

Examples checked against the textbook:

```text
math
pmt(4.2%/12, 10*12, 2800) =
fv(0.95%/12, 5*12, -210) =
pmt(1.5%/12, 12, -1000, 5000) =
```

Payment results have a negative cash-out sign. `abs(payment)*periods-principal` finds total interest when the final balance is zero. `-fv(rate,k,payment,principal)` gives the balance after k end-of-period payments. No periodic cent-rounding, fees or taxes are modeled. These are mathematical models for class exercises.

## Sources and limits

Reviewed [statistics](https://books.byui.edu/math_for_the_real_world/lesson_5_summarizing_data), [functions/finance](https://books.byui.edu/math_for_the_real_world/lesson_7_functions_in_excel), [function families](https://books.byui.edu/math_for_the_real_world/lesson_8_functions_and_their_graphs), [change](https://books.byui.edu/math_for_the_real_world/lesson_9_change_over_time), [prediction](https://books.byui.edu/math_for_the_real_world/lesson_10_making_predictions_from_data), [systems](https://books.byui.edu/math_for_the_real_world/lesson_11_solving_systems_of_equations), and [probability/intervals](https://books.byui.edu/math_for_the_real_world/lesson_12_probability_and_confidence_intervals). Verified Excel conventions against Microsoft's [PMT documentation](https://support.microsoft.com/en-us/excel/functions/pmt-function) and [payments/savings guide](https://support.microsoft.com/en-gb/excel/using-excel-formulas-to-figure-out-payments-and-savings).

The course's confidence formula is a simplified approximate 95% interval, not an exact interval or a general statistical-inference engine. Trendline coefficients do not establish causation or guarantee predictions outside the observed range. Extremely ill-conditioned systems/fits can be rejected or lose precision; no complex-valued roots are returned. Invalid inputs report “Check expression”.

Expressions are bounded to 512 tokens/16 KiB; each top-level calculation shares a 4096-atom work budget across nested functions. User functions have 1–16 distinct parameters, up to 64 definitions per analysis, and at most 16 nested calls. All evaluation, fitting, substitution and caching preparation runs on the existing ScratchTools actor. UI code only draws prepared answers and exposes their full text through native tooltips/accessibility. Definitions and example notes use normal note persistence/import/export.
