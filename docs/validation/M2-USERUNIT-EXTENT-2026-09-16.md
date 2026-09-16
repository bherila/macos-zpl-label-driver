# Actual-size UserUnit discriminator

Advances the M2-AC01/03 physical-placement regression coverage without claiming
installed printing or physical acceptance. The existing supplied compensated
UserUnit equivalence fixture and independent oracle remain unchanged.

An analytic test keeps raw page geometry and lower-half black vector artwork
identical, changing only `/UserUnit` from 1 to 2. On the same 40-by-40-dot canvas
at one dot per PDF point, actual-size placement must span 10 versus 20 dots
horizontally and 5 versus 10 black rows. Every canvas dot is independently checked,
including centering, white surroundings and top-down direction. A fixed-canvas
fit equivalence cannot establish this distinction.

PASS: pre-change offline accelerator suite, exit 0, including 132 independent
round trips and inert ABI/filter pipeline checks.
PASS: `swift test --package-path Packages/LabelMac --filter QuartzPDFRendererTests`,
26 tests, zero failures, exit 0. Native environment: macOS 26.6.2 build 25G83,
Apple Silicon, Swift 6.3.3. These results concern the working implementation;
the full combined gate and this slice's hosted CI remain pending.

No rendering implementation, shipped fixture, public schema, encoding or transport
changes. No queues installed, jobs submitted or printer I/O. Exact minimum runtime,
manual GUI operation and physical sizing/scanning remain NOT RUN.
