@IsTest
private class RollupLimitsTest {
  @IsTest
  static void correctlyReferencesOrgLimits() {
    Assert.areEqual(false, new RollupLimits.Tester(RollupControl__mdt.getInstance(Rollup.CONTROL_ORG_DEFAULTS), false).hasExceededOrgAsyncLimit());
  }

  @IsTest
  static void doesNotThrowForNullControl() {
    RollupLimits.stubbedQueryRows = 50001;

    Boolean hasExceededLimits = Rollup.hasExceededCurrentRollupLimits(null);

    Assert.isTrue(hasExceededLimits);
  }
}
