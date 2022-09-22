# Contributions Welcome

I'm open to collaborating! Please make sure you install this repo's dependencies using NPM or Yarn:

```bash
yarn
# or
npm -i
```

## Ensure All Rollup Files Are Installed

Whether you are developing on a sandbox or a new scratch org, please be sure to also deploy the `extra-tests` directory. I've included helper scripts to aid in programmatically testing only Apex Rollup's test classes when developing in a sandbox within the `package.json` file - one need only invoke the tests like such on the command line:

- `yarn test`
- or `npm run test`

Within a scratch org, validating that all of the tests run is as simple as invoking `sfdx force:apex:test:run -w 10`.

When submitting a pull request, please follow these guidelines:

- there should be no errors when running `npm run scan` or `yarn scan`
- ensure your dependencies have been installed and that any/all file(s) changed have had prettier-apex run on them (usually as simple as enabling "Format On Save" in your editor's options); alternatively you can always format the document in Vs Code using `Shift + Ctrl + F` or `cmd + Shift + F` once you're done writing. Your mileage may vary as to the hotkey if you're using Illuminated Cloud or another text editor; you always have the option of invoking prettier on the command-line
- ensure that tests have been run against a scratch org with multi-currency enabled (you can look at [`scripts/test.ps1`](https://github.com/jamessimone/apex-rollup/blob/main/scripts/test.ps1) to see how the scratch org is created and the currency ISO codes are loaded).
- ensure that any change to production code comes with the addition of tests. It's possible that I will accept PRs where _only_ production-level code is changed, if an optimization is put in place -- but otherwise, try to write a failing test first!
- if you are testing on a scratch org, `sfdx force:source:push` will fail due to the Rollup Nebula Logger Adapter plugin. You can either:
  - temporarily comment out that plugin within the `packageDirectories` list in `sfdx-project.json`
  - install whichever `04t...` version of Nebula Logger the plugin relies upon by looking at the dependency listed within `sfdx-project.json`'s `packageAliases` object
