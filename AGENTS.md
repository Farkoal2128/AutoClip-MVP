# AutoClip distribution work

Read `docs/requirements/distribution.md` and `docs/BUILDING.md` before release work.
Every public application update, including hotfixes, must also update, validate
and publish the matching full Windows installer. Fresh Setup must install the
released application directly. Deliver the app-update ZIP for existing users.
Do not mark a public update complete with only the wheel or update ZIP.

Preserve historical release assets, root compatibility feeds, installed
receipt-bound helpers, unrelated work and user media. Use immutable inputs and
new output directories. Demonstrate RED before meaningful production changes,
then run the distribution suite and exact generated installer lifecycle.
Record hashes, public download checks and any unperformed qualification paths.
