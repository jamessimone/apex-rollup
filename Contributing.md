# Contributions are welcome

I'm open to collaborating! Please make sure you install this repo's dependencies using NPM or Yarn:

```bash
yarn
# or
npm -i
```

## Setting Up Your Salesforce Development Environment

### Be aware of your development options

Apex Rollup is a monorepo that contains both the base unlocked package's source code and the source code for various plugin packages. Not _all_ of the code is required to be deployed if you aren't looking to work on plugins, but because the "Apex Rollup - Nebula Logger" plugin relies on [Nebula Logger](https://github.com/jongpie/NebulaLogger/) being installed, you have some choices to make if you want to use the `Push Source To Default Org` and CLI equivalents in a Source Tracking-enabled development environment.

You can either:

1. Install the Nebula Logger version provided in the `sfdx-project.json`'s `packageAliases` attribute. Using the CLI, do it like this:

```bash
sf package install -p <package version 04t> -w 30 -r
```

or:

2. Deploy the unlocked package source directories:

```bash
sf project deploy start --source-dir ./rollup
sf project deploy start --source-dir ./extra-tests
```

or:

3. Comment out the "Apex Rollup - Nebula Logger" plugin within the `packageDirectories` list in `sfdx-project.json` - this will allow `Push Source...` commands to work. Just remember to uncomment that plugin prior to submitting anything to be reviewed!

### Make sure to assign permissions to your user

The app is available to users that have the two permissions. For development purposes we recommend having at least the two main permission sets assigned to your user. Assign them with these commands:

```bash
sf org assign permset -n See_Rollup_App
sf org assign permset -n See_Rollup_Button
```

## Prior To Submitting A Change/Pull Request

When submitting a pull request, please follow these guidelines:

- there should be no errors when running `npm run scan` or `yarn scan`
- ensure your dependencies have been installed and that any/all file(s) changed have had prettier-apex run on them (usually as simple as enabling "Format On Save" in your editor's options); alternatively you can always format the document in Vs Code using `Shift + Ctrl + F` or `cmd + Shift + F` once you're done writing. Your mileage may vary as to the hotkey if you're using Illuminated Cloud or another text editor; you always have the option of invoking prettier on the command-line
- ensure that tests have been run against a scratch org with multi-currency enabled (you can look at [`scripts/test.ps1`](https://github.com/jamessimone/apex-rollup/blob/main/scripts/test.ps1) to see how the scratch org is created and the currency ISO codes are loaded).
- ensure that any change to production code comes with the addition of tests. It's possible that I will accept PRs where _only_ production-level code is changed, if an optimization is put in place -- but otherwise, try to write a failing test first!

