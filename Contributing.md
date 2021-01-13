# Contributions Welcome

If you'd like to submit a contribution to `Rollup`, please do!

When submitting a pull request, please follow these guidelines:

- ensure your dependencies have been installed and that any/all file(s) changed have had prettier-apex run on them (usually as simple as enabling "Format On Save" in your editor's options); alternatively you can always format the document in Vs Code using `Shift + Ctrl + F` or `cmd + Shift + F` once you're done writing. Your mileage may vary as to the hotkey if you're using Illuminated Cloud or another text editor; you always have the option of invoking prettier on the command-line
- ensure that tests have been run against a scratch org. You can use `sfdx force:org:display --verbose` to get the `Sfdx Auth Url` for the org you're developing against - just store the value of that in a text file named `DEVHUB_SFDX_URL.txt` in the root directory of this repo (it's Git ignored; you'll never commit your credentials or expose them in any way). After that, validating that everything is working correctly is as simple as running the included `scripts/test.sh` script, or `scripts/test.ps1` if you're on a Windows machine.
- ensure that any change to production code comes with the addition of tests. It's possible that I will accept PRs where _only_ production-level code is changed, if an optimization is put in place -- but otherwise, try to write a failing test first!
